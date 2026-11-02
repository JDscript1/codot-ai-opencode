package org.godotengine.editor

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Color
import android.graphics.Rect
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.view.inputmethod.InputMethodManager
import android.webkit.ConsoleMessage
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.lang.ref.WeakReference
import kotlin.math.roundToInt

/**
 * Native terminal surface for the embedded OpenCode TUI.
 *
 * The page is a local asset (vendored xterm.js) with a narrow bridge: keystrokes
 * and resizes go to the PTY, output arrives as base64 chunks. No remote origin
 * can be loaded and no privileged JavaScript interface is exposed to the web.
 */
object AIOpenCodeWindow {
    private const val TAG = "GodotOpenCode"
    private const val PAGE = "file:///android_asset/ai/opencode/terminal.html"
    private const val BUFFER_LIMIT = 2 * 1024 * 1024
    private var host = WeakReference<Activity>(null)
    private var anchor = WeakReference<View>(null)
    private var web: WebView? = null
    private var container: FrameLayout? = null
    private var bounds = DoubleArray(4)
    private var shown = false
    private var pageReady = false
    @Volatile private var resync = false
    private val pending = ByteArrayOutputStream()
    private val handler = Handler(Looper.getMainLooper())
    private val layout = View.OnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> position() }
    private val globalLayout = ViewTreeObserver.OnGlobalLayoutListener { position() }
    private val flush = Runnable { flushNow() }

    fun register(activity: Activity, renderView: View? = null) {
        activity.runOnUiThread {
            if (host.get() !== activity) dispose()
            host = WeakReference(activity)
            if (renderView != null && anchor.get() !== renderView) {
                anchor.get()?.removeOnLayoutChangeListener(layout)
                anchor = WeakReference(renderView)
                renderView.addOnLayoutChangeListener(layout)
            }
            position()
        }
    }

    fun embed(rectangle: DoubleArray) {
        require(rectangle.size == 4 && rectangle.all { it.isFinite() && it in 0.0..1.0 } &&
            rectangle[2] > 0 && rectangle[3] > 0 && rectangle[0] + rectangle[2] <= 1.001 &&
            rectangle[1] + rectangle[3] <= 1.001) { "Încadrarea terminalului este invalidă." }
        val activity = host.get() ?: error("Editorul Android nu este activ.")
        check(!activity.isFinishing && !activity.isDestroyed && anchor.get() != null) { "Suprafața editorului nu este pregătită." }
        activity.runOnUiThread {
            if (host.get() !== activity || activity.isFinishing || activity.isDestroyed) return@runOnUiThread
            if (web == null) create(activity)
            bounds = rectangle.copyOf()
            shown = true
            container?.visibility = View.VISIBLE
            position()
            web?.onResume()
            web?.requestFocus()
            handler.post(flush)
        }
    }

    fun hide() {
        host.get()?.runOnUiThread {
            shown = false
            web?.let { browser ->
                browser.evaluateJavascript("window.opencodeDismissKeyboard && window.opencodeDismissKeyboard()", null)
                if (browser.hasFocus()) {
                    (browser.context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager)
                        ?.hideSoftInputFromWindow(browser.windowToken, 0)
                }
                browser.clearFocus()
            }
            container?.visibility = View.GONE
            web?.onPause()
        }
    }

    fun pause(activity: Activity) {
        if (host.get() === activity) web?.onPause()
    }

    fun resume(activity: Activity) {
        if (host.get() === activity && shown) web?.onResume()
    }

    fun release(activity: Activity) {
        activity.runOnUiThread {
            if (host.get() === activity) {
                dispose()
                host.clear()
            }
        }
    }

    fun refreshStatus() {
        handler.post { position() }
    }

    fun push(chunk: ByteArray) {
        if (chunk.isEmpty()) return
        synchronized(pending) {
            if (pending.size() + chunk.size > BUFFER_LIMIT) {
                // The live terminal fell too far behind: drop the queued bytes
                // and resynchronize from the bounded runtime scrollback.
                pending.reset()
                resync = true
            }
            pending.write(chunk)
        }
        handler.post(flush)
    }

    private fun flushNow() {
        val browser = web ?: return
        if (!pageReady) return
        if (resync) {
            resync = false
            synchronized(pending) { pending.reset() }
            val snapshot = Base64.encodeToString(AIOpenCodeRuntime.snapshot(), Base64.NO_WRAP)
            browser.evaluateJavascript("window.opencodeResync && window.opencodeResync('$snapshot')", null)
            return
        }
        val chunk = synchronized(pending) {
            if (pending.size() == 0) return
            val data = pending.toByteArray()
            pending.reset()
            data
        }
        val encoded = Base64.encodeToString(chunk, Base64.NO_WRAP)
        browser.evaluateJavascript("window.opencodeWrite && window.opencodeWrite('$encoded')", null)
        synchronized(pending) {
            if (pending.size() > 0) handler.postDelayed(flush, 16)
        }
    }

    private fun ready() {
        // Called from the JavaScript bridge thread: WebView and flush state are
        // UI-thread only.
        handler.post {
            if (web == null) return@post
            pageReady = true
            resync = false
            synchronized(pending) { pending.reset() }
            push(AIOpenCodeRuntime.snapshot())
            flushNow()
            web?.requestFocus()
        }
    }

    private fun paste() {
        val activity = host.get() ?: return
        val manager = activity.getSystemService(ClipboardManager::class.java) ?: return
        val text = manager.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)
            ?.coerceToText(activity)?.toString().orEmpty()
        if (text.isEmpty()) return
        web?.evaluateJavascript("window.opencodePaste && window.opencodePaste(${JSONObject.quote(text)})", null)
    }

    private fun pasteFromBridge() {
        handler.post { paste() }
    }

    private fun dismissKeyboard() {
        web?.let { browser ->
            (browser.context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager)
                ?.hideSoftInputFromWindow(browser.windowToken, 0)
        }
    }

    private fun dismissKeyboardFromBridge() {
        handler.post { dismissKeyboard() }
    }

    private fun create(activity: Activity) {
        val root = activity.findViewById<ViewGroup>(android.R.id.content)
        val frame = FrameLayout(activity).apply { visibility = View.GONE; setBackgroundColor(Color.rgb(16, 16, 22)) }
        val browser = WebView(activity).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            // file:///android_asset remains readable even with file access off;
            // the terminal never needs the wider filesystem.
            settings.setSupportZoom(false)
            settings.builtInZoomControls = false
            settings.displayZoomControls = false
            settings.useWideViewPort = true
            settings.loadWithOverviewMode = false
            setBackgroundColor(Color.rgb(16, 16, 22))
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    val url: Uri = request.url
                    return !(url.scheme == "file" && url.host == "android_asset" &&
                        url.path?.startsWith("/ai/opencode/") == true)
                }
            }
            webChromeClient = object : WebChromeClient() {
                override fun onConsoleMessage(message: ConsoleMessage): Boolean {
                    Log.d(TAG, "${message.message()} (${message.sourceId()}:${message.lineNumber()})")
                    return true
                }
            }
            addJavascriptInterface(Bridge(), "GodotTerminal")
            loadUrl(PAGE)
        }
        frame.addView(browser, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        root.addView(frame, FrameLayout.LayoutParams(1, 1, Gravity.TOP or Gravity.LEFT))
        root.addOnLayoutChangeListener(layout)
        root.viewTreeObserver.addOnGlobalLayoutListener(globalLayout)
        web = browser
        container = frame
        pageReady = false
    }

    // Bounds are normalized against the Godot render surface, so display
    // scaling, system bars, rotation and the Android IME are accounted for.
    private fun position() {
        if (host.get() == null) return
        val surface = anchor.get() ?: return
        val frame = container ?: return
        val root = frame.parent as? ViewGroup ?: return
        if (!shown || !surface.isShown || surface.width <= 0 || surface.height <= 0) {
            frame.visibility = View.GONE
            return
        }
        val origin = IntArray(2); surface.getLocationInWindow(origin)
        val parent = IntArray(2); root.getLocationInWindow(parent)
        val left = origin[0] - parent[0] + (bounds[0] * surface.width).roundToInt()
        val top = origin[1] - parent[1] + (bounds[1] * surface.height).roundToInt()
        val requested = Rect(left, top, left + (bounds[2] * surface.width).roundToInt(),
            top + (bounds[3] * surface.height).roundToInt())
        val visible = Rect()
        root.getWindowVisibleDisplayFrame(visible)
        val screen = IntArray(2); root.getLocationOnScreen(screen)
        visible.offset(-screen[0], -screen[1])
        if (!requested.intersect(visible) || requested.isEmpty) {
            frame.visibility = View.GONE
            return
        }
        val current = frame.layoutParams as? FrameLayout.LayoutParams
        if (current == null || current.width != requested.width() || current.height != requested.height() ||
            current.leftMargin != requested.left || current.topMargin != requested.top) {
            frame.layoutParams = FrameLayout.LayoutParams(requested.width(), requested.height(), Gravity.TOP or Gravity.LEFT).apply {
                leftMargin = requested.left; topMargin = requested.top
            }
        }
        frame.visibility = View.VISIBLE
    }

    private fun dispose() {
        shown = false
        pageReady = false
        synchronized(pending) { pending.reset() }
        (container?.parent as? ViewGroup)?.let { root ->
            root.removeOnLayoutChangeListener(layout)
            root.viewTreeObserver.removeOnGlobalLayoutListener(globalLayout)
            root.removeView(container)
        }
        web?.stopLoading()
        web?.removeJavascriptInterface("GodotTerminal")
        web?.destroy()
        web = null
        container = null
        anchor.get()?.removeOnLayoutChangeListener(layout)
        anchor.clear()
    }

    /** Only the local asset page can reach these methods. */
    private class Bridge {
        @JavascriptInterface
        fun input(data: String) {
            try {
                AIOpenCodeRuntime.write(Base64.decode(data, Base64.NO_WRAP))
            } catch (_: Exception) {
            }
        }

        @JavascriptInterface
        fun resize(columns: Int, rows: Int) {
            AIOpenCodeRuntime.resize(columns, rows)
        }

        @JavascriptInterface
        fun ready() {
            AIOpenCodeWindow.ready()
        }

        @JavascriptInterface
        fun paste() {
            AIOpenCodeWindow.pasteFromBridge()
        }

        @JavascriptInterface
        fun dismissKeyboard() {
            AIOpenCodeWindow.dismissKeyboardFromBridge()
        }

        @JavascriptInterface
        fun log(message: String) {
            Log.d(TAG, message.take(400))
        }
    }
}
