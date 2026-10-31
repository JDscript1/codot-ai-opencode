import org.godotengine.editor.AIZivaUpdates
import org.godotengine.editor.AIZivaPackage
import org.json.JSONArray
import org.json.JSONObject

fun main() {
    var checks = 0
    val spec = AIZivaPackage.RELEASE
    fun asset(name: String, url: String, size: Long, hash: String) = JSONObject().put("name", name)
        .put("browser_download_url", url).put("size", size).put("digest", "sha256:$hash")
    fun addon() = asset(spec.url.substringAfterLast('/'), spec.url, spec.archiveSize, spec.archiveHash)
    fun runtime() = asset(spec.runtimeUrl.substringAfterLast('/'), spec.runtimeUrl, spec.runtimeSize, spec.runtimeHash)
    fun metadata(vararg assets: JSONObject) = JSONObject().put("tag_name", spec.version).put("assets", JSONArray(assets.toList()))
    fun reject(value: JSONObject) {
        var rejected = false
        try { AIZivaUpdates.release(value) } catch (_: Exception) { rejected = true }
        check(rejected); checks++
    }
    val official = AIZivaUpdates.release(metadata(addon(), runtime()))
    check(official.archiveHash == spec.archiveHash && official.runtimeHash == spec.runtimeHash); checks++
    reject(metadata(addon(), runtime()).put("draft", true)); reject(metadata(addon(), runtime()).put("prerelease", true))
    reject(metadata(addon().put("digest", "md5:1234"), runtime()))
    reject(metadata(addon().put("digest", "sha256:"), runtime()))
    reject(metadata(addon().put("size", 99999999999L), runtime()))
    reject(metadata(addon().put("browser_download_url", "https://evil.invalid/ziva.zip"), runtime()))
    reject(metadata(addon().put("name", "ziva-linux-x86_64.zip"), runtime()))
    reject(metadata(addon(), runtime().put("digest", "sha256:")))
    reject(metadata(addon(), runtime().put("size", 0L)))
    reject(metadata(addon(), runtime().put("browser_download_url", "https://evil.invalid/runtime.zip")))
    reject(metadata(addon(), runtime().put("name", "ziva-runtime-linux-x64.zip")))
    reject(metadata(addon()))
    reject(metadata(addon(), addon(), runtime()))
    reject(metadata().put("tag_name", "../../outside"))
    check(AIZivaUpdates.newer("v3.10.0", "v3.9.9")); checks++
    check(!AIZivaUpdates.newer("v3.3.2", "v3.3.2") && !AIZivaUpdates.newer("v3.3.1", "v3.3.2")); checks++
    check(!AIZivaUpdates.newer("v3.3.3-beta", "v3.3.2")); checks++
    println("Ziva official updates: $checks checks, 0 failures")
}
