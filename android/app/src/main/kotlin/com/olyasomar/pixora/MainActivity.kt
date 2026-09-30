package com.olyasomar.pixora

import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

/**
 * Hands `.pixora` files opened from other apps ("Open with", share) to
 * Dart over the `pixora/open_file` channel:
 *  - `getInitialFiles` (Dart → native): files that arrived before Dart
 *    was ready, e.g. the one the app was launched with.
 *  - `openFile` (native → Dart): files that arrive while running.
 *
 * Also encodes exports with the system codecs over `pixora/codec`
 * (`encode`: premultiplied RGBA → WebP / JPEG), far faster and lighter
 * than encoding in Dart.
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pixora/codec")
            .setMethodCallHandler { call, result ->
                if (call.method != "encode") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val rgba = call.argument<ByteArray>("rgba")
                val width = call.argument<Int>("width") ?: 0
                val height = call.argument<Int>("height") ?: 0
                val format = call.argument<String>("format") ?: "webp"
                val quality = call.argument<Int>("quality") ?: 92
                val lossless = call.argument<Boolean>("lossless") ?: false
                if (rgba == null || width <= 0 || height <= 0) {
                    result.error("encode", "bad arguments", null)
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        val bytes = encode(rgba, width, height, format, quality, lossless)
                        runOnUiThread { result.success(bytes) }
                    } catch (e: Throwable) {
                        runOnUiThread { result.error("encode", e.toString(), null) }
                    }
                }.start()
            }
        handleIntent(intent)
    }

    @Suppress("DEPRECATION")
    private fun encode(
        rgba: ByteArray,
        width: Int,
        height: Int,
        format: String,
        quality: Int,
        lossless: Boolean,
    ): ByteArray {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        try {
            // ARGB_8888 keeps premultiplied R, G, B, A bytes in memory order.
            bitmap.copyPixelsFromBuffer(ByteBuffer.wrap(rgba))
            val (compress, q) = when {
                format == "jpg" -> Bitmap.CompressFormat.JPEG to quality
                Build.VERSION.SDK_INT >= 30 ->
                    if (lossless) Bitmap.CompressFormat.WEBP_LOSSLESS to 100
                    else Bitmap.CompressFormat.WEBP_LOSSY to quality
                // Before Android 11, quality 100 means lossless.
                else -> Bitmap.CompressFormat.WEBP to
                    (if (lossless) 100 else quality.coerceAtMost(99))
            }
            val out = ByteArrayOutputStream(width * height / 2)
            if (!bitmap.compress(compress, q, out)) throw IllegalStateException("compress failed")
            return out.toByteArray()
        } finally {
            bitmap.recycle()
        }
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
