package com.pixora.pixora

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hands `.pixora` files opened from other apps ("Open with", share) to
 * Dart over the `pixora/open_file` channel:
 *  - `getInitialFiles` (Dart → native): files that arrived before Dart
 *    was ready, e.g. the one the app was launched with.
 *  - `openFile` (native → Dart): files that arrive while running.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private val pending = mutableListOf<Map<String, Any>>()
    private var dartReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pixora/open_file").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialFiles" -> {
                        dartReady = true
                        val out = ArrayList(pending)
                        pending.clear()
                        result.success(out)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(incoming: Intent?) {
        val intent = incoming ?: return
        val uri: Uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            }
            else -> null
        } ?: return
        // Consume the intent so a configuration change doesn't reopen it.
        intent.action = null

        Thread {
            val file = read(uri) ?: return@Thread
            runOnUiThread {
                val ch = channel
                if (dartReady && ch != null) ch.invokeMethod("openFile", file) else pending.add(file)
            }
        }.start()
    }

    private fun read(uri: Uri): Map<String, Any>? = try {
        var name = uri.lastPathSegment ?: "project.pixora"
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (i >= 0) c.getString(i)?.let { name = it }
            }
        }
        val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
        if (bytes == null) null else mapOf("name" to name, "bytes" to bytes)
    } catch (e: Exception) {
        null
    }
}
