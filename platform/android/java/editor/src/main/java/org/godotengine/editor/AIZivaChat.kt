package org.godotengine.editor

import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * Sends prompts into the official Ziva sidecar through its own local oRPC.
 * These procedures are private to the official plugin and may change between
 * releases; failures are reported, never hidden, so the assistant can retry.
 */
object AIZivaChat {
    const val TITLE = "Godot AI"
    private const val POLL_MS = 1500L
    private const val MAX_RUNNING = 4
    private const val MAX_JOBS = 24
    private const val KEEP_FINISHED_MS = 30 * 60_000L

    private val jobs = ConcurrentHashMap<String, Job>()

    private class Job(val id: String, val port: Int, val prompt: String, val timeoutMs: Long) {
        @Volatile var state = "running"
        @Volatile var error: String? = null
        @Volatile var answer = ""
        @Volatile var finish = ""
        @Volatile var chatId = ""
        @Volatile var messageId = ""
        @Volatile var tools = 0
        @Volatile var waiting: JSONObject? = null
        @Volatile var cancelled = false
        val startedAt = System.currentTimeMillis()
        val deadline = startedAt + timeoutMs
        @Volatile var finishedAt = 0L
    }

    private class RpcFailure(message: String) : Exception(message)

    fun send(port: Int, prompt: String, chatId: String, timeoutSeconds: Int): JSONObject {
        val text = prompt.trim()
        if (text.isEmpty()) return failure("Cererea către Ziva este goală.", "ziva_invalid_prompt")
        if (text.length > 32000) return failure("Cererea către Ziva este prea lungă (maximum 32000 de caractere).", "ziva_invalid_prompt")
        prune()
        if (jobs.values.count { it.state == "running" || it.state == "permission_required" || it.state == "question_required" } >= MAX_RUNNING)
            return failure("Ziva are deja $MAX_RUNNING sarcini în lucru.", "ziva_busy")
        val job = Job(UUID.randomUUID().toString(), port, text, timeoutSeconds.coerceIn(30, 1800) * 1000L)
        job.chatId = chatId.trim()
        jobs[job.id] = job
        Thread({ execute(job) }, "ZivaChat").apply { isDaemon = true }.start()
        return JSONObject().put("ok", true).put("job_id", job.id).put("state", job.state)
    }

    fun poll(jobId: String): JSONObject {
        val job = jobs[jobId] ?: return failure("Sarcina Ziva nu mai există; pornește una nouă.", "ziva_job_unknown")
        val result = JSONObject().put("ok", true).put("job_id", job.id).put("state", job.state)
            .put("chat_id", job.chatId).put("message_id", job.messageId)
            .put("answer", job.answer).put("answer_length", job.answer.length)
            .put("tools", job.tools).put("finish", job.finish)
        job.error?.let { result.put("error", it) }
        job.waiting?.let { result.put("waiting", it) }
        return result
    }

    fun cancel(jobId: String): JSONObject {
        val job = jobs[jobId] ?: return failure("Sarcina Ziva nu mai există.", "ziva_job_unknown")
        job.cancelled = true
        if (job.finishedAt == 0L) {
            job.state = "cancelled"
            job.finishedAt = System.currentTimeMillis()
        }
        abort(job)
        return JSONObject().put("ok", true).put("job_id", job.id).put("state", job.state)
    }

    fun replyPermission(port: Int, requestId: String, reply: String): JSONObject {
        if (requestId.isBlank() || requestId.length > 200) return failure("Cererea de permisiune Ziva este invalidă.", "ziva_invalid_request")
        if (reply !in setOf("once", "always", "reject")) return failure("Răspunsul de permisiune Ziva este invalid.", "ziva_invalid_reply")
        val result = rpc(port, "permissions/reply", JSONObject().put("requestId", requestId).put("reply", reply))
        return JSONObject().put("ok", true).put("request_id", requestId).put("reply", reply).put("result", result)
    }

    fun replyQuestion(port: Int, requestId: String, answers: JSONArray): JSONObject {
        if (requestId.isBlank() || requestId.length > 200) return failure("Întrebarea Ziva este invalidă.", "ziva_invalid_request")
        if (answers.length() !in 1..8) return failure("Răspunsurile Ziva lipsesc.", "ziva_invalid_answers")
        for (index in 0 until answers.length()) {
            val choices = answers.optJSONArray(index) ?: return failure("Răspunsurile Ziva sunt invalide.", "ziva_invalid_answers")
            if (choices.length() !in 1..20) return failure("Răspunsurile Ziva sunt invalide.", "ziva_invalid_answers")
            for (choice in 0 until choices.length()) {
                val value = choices.optString(choice, "")
                if (value.isEmpty() || value.length > 4000) return failure("Răspunsurile Ziva sunt invalide.", "ziva_invalid_answers")
            }
        }
        val result = rpc(port, "questions/reply", JSONObject().put("requestId", requestId).put("answers", answers))
        return JSONObject().put("ok", true).put("request_id", requestId).put("result", result)
    }

    fun rejectQuestion(port: Int, requestId: String): JSONObject {
        if (requestId.isBlank() || requestId.length > 200) return failure("Întrebarea Ziva este invalidă.", "ziva_invalid_request")
        val result = rpc(port, "questions/reject", JSONObject().put("requestId", requestId))
        return JSONObject().put("ok", true).put("request_id", requestId).put("result", result)
    }

    private fun execute(job: Job) {
        try {
            if (job.cancelled) { finish(job, "cancelled", null); return }
            val chat = resolveChat(job)
            val id = chat.optString("id", "").ifBlank { job.chatId }
            if (id.isBlank()) throw RpcFailure("Conversația Ziva nu are identificator.")
            job.chatId = id
            val selection = chat.optJSONObject("modelSelection") ?: defaultSelection(job.port)
            val started = System.currentTimeMillis()
            rpc(job.port, "chats/sendPrompt", JSONObject()
                .put("chatId", id)
                .put("parts", JSONArray().put(JSONObject().put("type", "text").put("text", job.prompt)
                    .put("time", JSONObject().put("started", started))))
                .put("modelSelection", selection))
            awaitTurn(job, started)
        } catch (error: RpcFailure) {
            finish(job, "error", error.message?.take(600) ?: "Comunicarea cu Ziva a eșuat.")
        } catch (error: Exception) {
            finish(job, "error", error.message?.take(600) ?: "Comunicarea cu Ziva a eșuat.")
        }
    }

    private fun resolveChat(job: Job): JSONObject {
        if (job.chatId.isNotEmpty()) {
            val snapshot = rpc(job.port, "chats/snapshot", JSONObject().put("chatId", job.chatId))
            return snapshot.optJSONObject("chat") ?: throw RpcFailure("Conversația indicată nu există în Ziva.")
        }
        val bootstrap = rpc(job.port, "plugin/bootstrap", JSONObject())
        val chats = bootstrap.optJSONObject("sidebar")?.optJSONArray("chats") ?: JSONArray()
        for (index in 0 until chats.length()) {
            val chat = chats.optJSONObject(index) ?: continue
            if (chat.optString("title", "") == TITLE || chat.optString("fallbackTitle", "") == TITLE) return chat
        }
        val created = rpc(job.port, "chats/create", JSONObject()
            .put("title", TITLE).put("fallbackTitle", TITLE).put("provider", "zivacode")
            .put("modelSelection", defaultSelection(bootstrap)))
        return created.optJSONObject("chat") ?: throw RpcFailure("Conversația dedicată «$TITLE» nu a putut fi creată.")
    }

    private fun defaultSelection(port: Int): JSONObject {
        val bootstrap = try { rpc(port, "plugin/bootstrap", JSONObject()) } catch (_: RpcFailure) { JSONObject() }
        return defaultSelection(bootstrap)
    }

    private fun defaultSelection(bootstrap: JSONObject): JSONObject {
        var model = ""
        val providers = bootstrap.optJSONArray("providers") ?: JSONArray()
        for (index in 0 until providers.length()) {
            val provider = providers.optJSONObject(index) ?: continue
            if (provider.optString("provider", "") != "zivacode") continue
            model = provider.optString("defaultModelSlug", "")
            if (model.isNotEmpty()) break
            val models = provider.optJSONArray("models") ?: JSONArray()
            for (choice in 0 until models.length()) {
                val slug = models.optJSONObject(choice)?.optString("slug", "").orEmpty()
                if (slug.isNotEmpty()) { model = slug; break }
            }
            if (model.isNotEmpty()) break
        }
        if (model.isEmpty()) model = "ziva/luna"
        return JSONObject().put("provider", "zivacode").put("modelId", model)
    }

    private fun awaitTurn(job: Job, started: Long) {
        var misses = 0
        var idle = 0
        while (true) {
            if (job.cancelled) { finish(job, "cancelled", null); return }
            if (System.currentTimeMillis() > job.deadline) {
                abort(job)
                finish(job, "timeout", "Ziva nu a încheiat răspunsul în ${job.timeoutMs / 1000} secunde.")
                return
            }
            try { Thread.sleep(POLL_MS) } catch (_: InterruptedException) { finish(job, "cancelled", null); return }
            val snapshot = try {
                rpc(job.port, "chats/snapshot", JSONObject().put("chatId", job.chatId)).also { misses = 0 }
            } catch (error: RpcFailure) {
                if (++misses >= 5) throw RpcFailure("Sesiunea Ziva nu mai răspunde: ${error.message}")
                continue
            }
            val pending = snapshot.optJSONObject("pending")
            val permission = pending?.optJSONArray("permissions")?.optJSONObject(0)
            if (permission != null) {
                job.waiting = JSONObject().put("kind", "permission").put("permission", permission)
                job.state = "permission_required"
                continue
            }
            val question = pending?.optJSONArray("questions")?.optJSONObject(0)
            if (question != null) {
                job.waiting = JSONObject().put("kind", "question").put("question", question)
                job.state = "question_required"
                continue
            }
            job.waiting = null
            if (job.state == "permission_required" || job.state == "question_required") job.state = "running"

            val status = snapshot.optJSONObject("chat")?.optJSONObject("status")
            val statusType = status?.optString("type", "").orEmpty()
            if (statusType == "error") {
                finish(job, "error", status?.optString("error", "").orEmpty().ifBlank { "Ziva a raportat o eroare." })
                return
            }
            val messages = snapshot.optJSONArray("messages") ?: JSONArray()
            val turn = findTurn(messages, started, job.prompt)
            if (turn == null) {
                idle = if (statusType == "idle") idle + 1 else 0
                if (idle >= 4) {
                    finish(job, "error", "Ziva a încheiat turul fără un răspuns.")
                    return
                }
                continue
            }
            idle = 0
            val info = turn.optJSONObject("info") ?: continue
            job.messageId = info.optString("id", job.messageId)
            val failure = info.optJSONObject("error")
            if (failure != null) {
                finish(job, "error", describe(failure))
                return
            }
            val created = info.optJSONObject("time")?.optLong("created", 0L) ?: 0L
            val completed = info.optJSONObject("time")?.optLong("completed", 0L) ?: 0L
            if (created > 0 && completed > 0) {
                job.answer = textOf(turn)
                job.finish = info.optString("finish", "")
                job.tools = toolCount(turn)
                finish(job, "completed", null)
                return
            }
        }
    }

    private fun findTurn(messages: JSONArray, started: Long, prompt: String): JSONObject? {
        val expected = prompt.trim()
        var userId = ""
        for (index in 0 until messages.length()) {
            val message = messages.optJSONObject(index) ?: continue
            val info = message.optJSONObject("info") ?: continue
            if (info.optString("role", "") != "user") continue
            val created = info.optJSONObject("time")?.optLong("created", 0L) ?: 0L
            if (created > 0 && created < started - 5000L) continue
            if (textOf(message).trim() == expected) { userId = info.optString("id", ""); break }
        }
        if (userId.isEmpty()) return null
        for (index in 0 until messages.length()) {
            val message = messages.optJSONObject(index) ?: continue
            val info = message.optJSONObject("info") ?: continue
            if (info.optString("role", "") == "assistant" && info.optString("parentId", "") == userId) return message
        }
        return null
    }

    private fun textOf(message: JSONObject): String {
        val parts = message.optJSONArray("parts") ?: return ""
        val text = StringBuilder()
        for (index in 0 until parts.length()) {
            val part = parts.optJSONObject(index) ?: continue
            if (part.optString("type", "") != "text") continue
            if (part.optBoolean("synthetic", false) || part.optBoolean("ignored", false)) continue
            val value = part.optString("text", "")
            if (value.isEmpty()) continue
            if (text.isNotEmpty()) text.append("\n\n")
            text.append(value)
        }
        return text.toString()
    }

    private fun toolCount(message: JSONObject): Int {
        val parts = message.optJSONArray("parts") ?: return 0
        var count = 0
        for (index in 0 until parts.length()) {
            if (parts.optJSONObject(index)?.optString("type", "") == "tool") count++
        }
        return count
    }

    private fun describe(error: JSONObject): String {
        val data = error.optJSONObject("data")
        val text = error.optString("message", "").ifBlank { data?.optString("message", "").orEmpty() }
            .ifBlank { error.optString("name", "") }
        return text.ifBlank { "Ziva a raportat o eroare." }.take(600)
    }

    private fun finish(job: Job, state: String, error: String?) {
        job.state = state
        job.error = error
        job.finishedAt = System.currentTimeMillis()
    }

    private fun abort(job: Job) {
        if (job.chatId.isEmpty()) return
        Thread({
            try { rpc(job.port, "chats/abort", JSONObject().put("chatId", job.chatId)) } catch (_: Exception) { }
        }, "ZivaChatAbort").apply { isDaemon = true }.start()
    }

    private fun prune() {
        val now = System.currentTimeMillis()
        for (job in jobs.values) {
            if (job.finishedAt > 0 && now - job.finishedAt > KEEP_FINISHED_MS) jobs.remove(job.id)
        }
        if (jobs.size < MAX_JOBS) return
        jobs.values.filter { it.finishedAt > 0 }.sortedBy { it.finishedAt }
            .take(jobs.size - MAX_JOBS + 1).forEach { jobs.remove(it.id) }
    }

    private fun rpc(port: Int, path: String, input: JSONObject): JSONObject {
        val connection = URL("http://127.0.0.1:$port/api/rpc/$path").openConnection() as HttpURLConnection
        return try {
            connection.connectTimeout = 2000
            connection.readTimeout = 15000
            connection.instanceFollowRedirects = false
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Accept", "application/json")
            connection.outputStream.use { it.write(JSONObject().put("json", input).toString().toByteArray(Charsets.UTF_8)) }
            val code = connection.responseCode
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.use { source ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (output.size() < 8 * 1024 * 1024) {
                    val read = source.read(buffer)
                    if (read < 0) break
                    output.write(buffer, 0, read)
                }
                output.toString("UTF-8")
            }.orEmpty()
            val body = try { JSONObject(text) } catch (_: Exception) { null }
            val json = body?.opt("json")
            if (code !in 200..299) {
                val payload = json as? JSONObject
                val message = payload?.optString("message", "").orEmpty().ifBlank {
                    body?.optString("message", "").orEmpty()
                }.ifBlank { "HTTP $code" }
                throw RpcFailure(message.take(600))
            }
            json as? JSONObject ?: throw RpcFailure("Răspuns RPC Ziva invalid.")
        } catch (error: RpcFailure) {
            throw error
        } catch (error: Exception) {
            throw RpcFailure(error.message?.take(300) ?: "Conexiunea locală cu Ziva a eșuat.")
        } finally {
            connection.disconnect()
        }
    }

    private fun failure(message: String, code: String): JSONObject =
        JSONObject().put("ok", false).put("error", message).put("code", code)
}
