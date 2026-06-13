package com.example.sign_app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.holisticlandmarker.HolisticLandmarker
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MediaPipePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var landmarker: HolisticLandmarker? = null
    private val executor = Executors.newSingleThreadExecutor()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "sign.language.mediapipe")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        landmarker?.close()
        executor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(result)
            "extractKeypoints" -> {
                val width = call.argument<Int>("width")
                val height = call.argument<Int>("height")
                val rotation = call.argument<Int>("rotation") ?: 0
                @Suppress("UNCHECKED_CAST")
                val planes = call.argument<List<ByteArray>>("planes")
                val bytesPerRow = call.argument<List<Int>>("bytesPerRow")
                val bytesPerPixel = call.argument<List<Int>>("bytesPerPixel")
                if (width == null || height == null || planes == null ||
                    bytesPerRow == null || bytesPerPixel == null || planes.size < 3
                ) {
                    result.error("INVALID", "frame verisi eksik/bozuk", null)
                    return
                }
                executor.execute {
                    val kp = extractKeypoints(width, height, rotation, planes, bytesPerRow, bytesPerPixel)
                    result.success(kp)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun initialize(result: MethodChannel.Result) {
        try {
            val options = HolisticLandmarker.HolisticLandmarkerOptions.builder()
                .setBaseOptions(
                    BaseOptions.builder()
                        .setModelAssetPath("holistic_landmarker.task")
                        .setDelegate(Delegate.GPU)
                        .build()
                )
                .setRunningMode(RunningMode.IMAGE)
                .setMinFaceDetectionConfidence(0.5f)
                .setMinFacePresenceConfidence(0.5f)
                .setMinPoseDetectionConfidence(0.5f)
                .setMinHandLandmarksConfidence(0.5f)
                .build()
            landmarker = HolisticLandmarker.createFromOptions(context, options)
            result.success(null)
        } catch (e: Exception) {
            result.error("INIT_ERROR", e.message, null)
        }
    }

    private fun extractKeypoints(
        width: Int,
        height: Int,
        rotationDegrees: Int,
        planes: List<ByteArray>,
        bytesPerRow: List<Int>,
        bytesPerPixel: List<Int>,
    ): List<Double>? {
        val lm = landmarker ?: return null

        val bitmap = yuv420ToBitmap(width, height, planes, bytesPerRow, bytesPerPixel)
        val upright = rotateBitmap(bitmap, rotationDegrees)
        val mpImage = BitmapImageBuilder(upright).build()

        val detection = try {
            lm.detect(mpImage)
        } catch (e: Exception) {
            return null
        }

        val kp = DoubleArray(1692)
        var idx = 0

        // Pose: 33 × 4 (x, y, z, visibility)
        val poseLms = detection.poseLandmarks()
        for (i in 0 until 33) {
            if (i < poseLms.size) {
                kp[idx]     = poseLms[i].x().toDouble()
                kp[idx + 1] = poseLms[i].y().toDouble()
                kp[idx + 2] = poseLms[i].z().toDouble()
                kp[idx + 3] = poseLms[i].visibility().orElse(0f).toDouble()
            }
            idx += 4
        }

        // Face: 478 × 3 (x, y, z)
        val faceLms = detection.faceLandmarks()
        for (i in 0 until 478) {
            if (i < faceLms.size) {
                kp[idx]     = faceLms[i].x().toDouble()
                kp[idx + 1] = faceLms[i].y().toDouble()
                kp[idx + 2] = faceLms[i].z().toDouble()
            }
            idx += 3
        }

        // Sol el: 21 × 3 (x, y, z)
        val lhLms = detection.leftHandLandmarks()
        for (i in 0 until 21) {
            if (i < lhLms.size) {
                kp[idx]     = lhLms[i].x().toDouble()
                kp[idx + 1] = lhLms[i].y().toDouble()
                kp[idx + 2] = lhLms[i].z().toDouble()
            }
            idx += 3
        }

        // Sağ el: 21 × 3 (x, y, z)
        val rhLms = detection.rightHandLandmarks()
        for (i in 0 until 21) {
            if (i < rhLms.size) {
                kp[idx]     = rhLms[i].x().toDouble()
                kp[idx + 1] = rhLms[i].y().toDouble()
                kp[idx + 2] = rhLms[i].z().toDouble()
            }
            idx += 3
        }

        return kp.toList()
    }

    /// YUV_420_888 (ayrı Y/U/V plane'leri, stride'lara göre) → ARGB_8888 Bitmap.
    /// ITU-R BT.601 limited-range dönüşümü, tamsayı aritmetiği ile.
    private fun yuv420ToBitmap(
        width: Int,
        height: Int,
        planes: List<ByteArray>,
        bytesPerRow: List<Int>,
        bytesPerPixel: List<Int>,
    ): Bitmap {
        val yPlane = planes[0]
        val uPlane = planes[1]
        val vPlane = planes[2]
        val yRowStride = bytesPerRow[0]
        val uvRowStride = bytesPerRow[1]
        val uvPixelStride = bytesPerPixel[1]

        val argb = IntArray(width * height)
        for (row in 0 until height) {
            val yRowOffset = row * yRowStride
            val uvRowOffset = (row shr 1) * uvRowStride
            for (col in 0 until width) {
                val y = yPlane[yRowOffset + col].toInt() and 0xFF
                val uvIndex = uvRowOffset + (col shr 1) * uvPixelStride
                val u = (uPlane[uvIndex].toInt() and 0xFF) - 128
                val v = (vPlane[uvIndex].toInt() and 0xFF) - 128

                val c = y - 16
                var r = (298 * c + 409 * v + 128) shr 8
                var g = (298 * c - 100 * u - 208 * v + 128) shr 8
                var b = (298 * c + 516 * u + 128) shr 8

                r = r.coerceIn(0, 255)
                g = g.coerceIn(0, 255)
                b = b.coerceIn(0, 255)

                argb[row * width + col] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
        return Bitmap.createBitmap(argb, width, height, Bitmap.Config.ARGB_8888)
    }

    /// Görüntüyü dik (upright) hale getirmek için saat yönünde döndürür.
    private fun rotateBitmap(bitmap: Bitmap, degrees: Int): Bitmap {
        if (degrees == 0) return bitmap
        val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }
}
