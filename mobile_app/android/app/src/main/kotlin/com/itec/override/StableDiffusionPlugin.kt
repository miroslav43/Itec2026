package com.itec.override

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.ByteArrayOutputStream

/**
 * Flutter plugin that exposes on-device Stable Diffusion inference
 * via stable-diffusion.cpp (compiled as libstable_diffusion_jni.so).
 *
 * Channel: com.itec.override/stable_diffusion
 *
 * Methods:
 *   isModelLoaded()                    → Boolean
 *   loadModel(modelPath: String)       → void  (runs off main thread)
 *   generateImage(prompt, negativePrompt, width, height, steps, cfg, seed)
 *                                      → ByteArray (PNG)  (runs off main thread)
 *   freeModel()                        → void
 */
class StableDiffusionPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private val mainHandler = Handler(Looper.getMainLooper())

    // ── Native declarations ────────────────────────────────────────────────────

    private external fun nativeIsModelLoaded(): Boolean
    private external fun nativeLoadModel(modelPath: String): Boolean
    private external fun nativeGenerateImage(
        prompt: String,
        negativePrompt: String,
        width: Int,
        height: Int,
        steps: Int,
        cfg: Float,
        seed: Long
    ): ByteArray?
    private external fun nativeFreeModel()

    // ── FlutterPlugin ──────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.itec.override/stable_diffusion")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    // ── Method dispatch ────────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isModelLoaded" -> result.success(nativeIsModelLoaded())

            "loadModel" -> {
                val modelPath = call.argument<String>("modelPath")
                    ?: return result.error("INVALID_ARGS", "modelPath is required", null)

                Thread {
                    val ok = nativeLoadModel(modelPath)
                    mainHandler.post {
                        if (ok) result.success(null)
                        else result.error("LOAD_FAILED", "Failed to load model at: $modelPath", null)
                    }
                }.start()
            }

            "generateImage" -> {
                val prompt      = call.argument<String>("prompt")        ?: ""
                val negPrompt   = call.argument<String>("negativePrompt") ?: ""
                val width       = call.argument<Int>("width")            ?: 64
                val height      = call.argument<Int>("height")           ?: 64
                val steps       = call.argument<Int>("steps")            ?: 6
                val cfg         = (call.argument<Double>("cfg")          ?: 2.0).toFloat()
                val seed        = call.argument<Long>("seed")            ?: 42L

                Thread {
                    val rgbBytes = nativeGenerateImage(
                        prompt, negPrompt, width, height, steps, cfg, seed
                    )

                    if (rgbBytes == null) {
                        mainHandler.post {
                            result.error("GEN_FAILED", "Native image generation returned null", null)
                        }
                        return@Thread
                    }

                    // Convert raw RGB bytes → Android Bitmap → PNG bytes
                    val pngBytes = rgbToPng(rgbBytes, width, height)
                    mainHandler.post { result.success(pngBytes) }
                }.start()
            }

            "freeModel" -> {
                nativeFreeModel()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    /**
     * Encodes a flat RGB byte array into PNG via Android's Bitmap API.
     * [rgbBytes] must have length == width * height * 3.
     */
    private fun rgbToPng(rgbBytes: ByteArray, width: Int, height: Int): ByteArray {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val pixels = IntArray(width * height)
        for (i in pixels.indices) {
            val r = rgbBytes[i * 3].toInt()     and 0xFF
            val g = rgbBytes[i * 3 + 1].toInt() and 0xFF
            val b = rgbBytes[i * 3 + 2].toInt() and 0xFF
            pixels[i] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
        }
        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        return out.toByteArray()
    }

    companion object {
        init {
            System.loadLibrary("stable_diffusion_jni")
        }
    }
}
