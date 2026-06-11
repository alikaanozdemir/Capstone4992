import Flutter
import UIKit
import MediaPipeTasksVision

/// Flutter MethodChannel handler — MediaPipe HolisticLandmarker
///
/// Kanal adı: "sign.language.mediapipe"
/// Metodlar:
///   initialize()                         → holistic_landmarker.task'ı yükle
///   extractKeypoints(frame: String)      → [Float] (1692 eleman) döner
class MediaPipePlugin: NSObject, FlutterPlugin {

    private var landmarker: HolisticLandmarker?

    // Keypoint boyutları (Python recognition.py ile aynı)
    private let poseDim = 132   // 33 × 4  (x, y, z, visibility)
    private let faceDim = 1434  // 478 × 3 (x, y, z)
    private let handDim = 63    // 21 × 3  (x, y, z)
    private let totalDim = 1692

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "sign.language.mediapipe",
            binaryMessenger: registrar.messenger()
        )
        let instance = MediaPipePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            do {
                try setupLandmarker()
                result(nil)
            } catch {
                result(FlutterError(code: "INIT_ERROR", message: error.localizedDescription, details: nil))
            }

        case "extractKeypoints":
            guard let args = call.arguments as? [String: Any],
                  let base64 = args["frame"] as? String else {
                result(FlutterError(code: "BAD_ARGS", message: "frame eksik", details: nil))
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let kp = self.extractKeypoints(from: base64)
                DispatchQueue.main.async {
                    result(kp)
                }
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ── Landmarker kurulumu ───────────────────────────────────────────────────

    private func setupLandmarker() throws {
        guard let taskPath = Bundle.main.path(forResource: "holistic_landmarker", ofType: "task") else {
            throw NSError(domain: "MediaPipe", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "holistic_landmarker.task bulunamadı"])
        }

        let options = HolisticLandmarkerOptions()
        options.baseOptions.modelAssetPath = taskPath
        options.runningMode = .image
        options.minFaceDetectionConfidence    = 0.5
        options.minFacePresenceConfidence     = 0.5
        options.minPoseDetectionConfidence    = 0.5
        options.minHandLandmarksConfidence    = 0.5

        landmarker = try HolisticLandmarker(options: options)
    }

    // ── Yardımcılar ───────────────────────────────────────────────────────────

    /// EXIF yönlendirmesini piksellere "pişirerek" imageOrientation = .up yapar.
    private func normalizedToUp(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    // ── Keypoint çıkarımı ─────────────────────────────────────────────────────

    private func extractKeypoints(from base64: String) -> [Float]? {
        guard let landmarker = landmarker else {
            print("[MediaPipePlugin] landmarker nil (init başarısız)")
            return nil
        }
        guard let data = Data(base64Encoded: base64) else {
            print("[MediaPipePlugin] base64 decode başarısız, len=\(base64.count)")
            return nil
        }
        guard let uiImage = UIImage(data: data) else {
            print("[MediaPipePlugin] UIImage decode başarısız, bytes=\(data.count)")
            return nil
        }

        // HolisticLandmarker yalnızca imageOrientation = .up destekler;
        // kameradan gelen JPEG'ler genelde .right/.left EXIF yönüyle gelir.
        let uprightImage = normalizedToUp(uiImage)

        let mpImage: MPImage
        do {
            mpImage = try MPImage(uiImage: uprightImage)
        } catch {
            print("[MediaPipePlugin] MPImage init hatası: \(error), size=\(uprightImage.size), orientation=\(uprightImage.imageOrientation.rawValue)")
            return nil
        }

        let result: HolisticLandmarkerResult
        do {
            result = try landmarker.detect(image: mpImage)
        } catch {
            print("[MediaPipePlugin] detect() hatası: \(error)")
            return nil
        }

        var kp = [Float](repeating: 0, count: totalDim)
        var idx = 0

        // Pose: 33 × [x, y, z, visibility]
        let poseLms = result.poseLandmarks
        for i in 0..<33 {
            if i < poseLms.count {
                let lm = poseLms[i]
                kp[idx]   = lm.x
                kp[idx+1] = lm.y
                kp[idx+2] = lm.z
                kp[idx+3] = lm.visibility?.floatValue ?? 0
            }
            idx += 4
        }

        // Face: 478 × [x, y, z]
        let faceLms = result.faceLandmarks
        for i in 0..<478 {
            if i < faceLms.count {
                let lm = faceLms[i]
                kp[idx]   = lm.x
                kp[idx+1] = lm.y
                kp[idx+2] = lm.z
            }
            idx += 3
        }

        // Sol el: 21 × [x, y, z]
        let lhLms = result.leftHandLandmarks
        for i in 0..<21 {
            if i < lhLms.count {
                let lm = lhLms[i]
                kp[idx]   = lm.x
                kp[idx+1] = lm.y
                kp[idx+2] = lm.z
            }
            idx += 3
        }

        // Sağ el: 21 × [x, y, z]
        let rhLms = result.rightHandLandmarks
        for i in 0..<21 {
            if i < rhLms.count {
                let lm = rhLms[i]
                kp[idx]   = lm.x
                kp[idx+1] = lm.y
                kp[idx+2] = lm.z
            }
            idx += 3
        }

        return kp
    }
}
