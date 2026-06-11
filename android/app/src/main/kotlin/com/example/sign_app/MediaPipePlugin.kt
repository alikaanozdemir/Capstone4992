package com.example.sign_app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.util.Base64
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.holisticlandmarker.HolisticLandmarker
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
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
                val frame = call.argument<String>("frame")
                if (frame == null) {
                    result.error("INVALID", "frame is null", null)
                    return
                }
                executor.execute {
                    val kp = extractKeypoints(frame)
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

    private fun extractKeypoints(base64Frame: String): List<Double>? {
        val lm = landmarker ?: return null

        val bytes = Base64.decode(base64Frame, Base64.DEFAULT)
        val raw = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        val bitmap = fixRotation(raw, bytes)
        val mpImage = BitmapImageBuilder(bitmap).build()

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

    private fun fixRotation(bitmap: Bitmap, jpegBytes: ByteArray): Bitmap {
        val exif = try {
            ExifInterface(ByteArrayInputStream(jpegBytes))
        } catch (e: Exception) {
            return bitmap
        }
        val degrees = when (exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
            ExifInterface.ORIENTATION_ROTATE_90  -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> return bitmap
        }
        val matrix = Matrix().apply { postRotate(degrees) }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }
}
