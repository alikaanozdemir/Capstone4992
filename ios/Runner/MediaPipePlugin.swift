import Flutter
import UIKit
import CoreVideo
import MediaPipeTasksVision

/// Flutter ↔ Swift köprüsü: MediaPipe HolisticLandmarker
///
/// Kanal adı: "sign.language.mediapipe"
/// Metodlar:
///   initialize()      → holistic_landmarker.task'ı yükle
///   extractKeypoints(width, height, rotation, planes, bytesPerRow, bytesPerPixel)
///     → [Float] (1692 eleman) döner. [planes] BGRA8888 tek plane içerir.
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
                  let width = args["width"] as? Int,
                  let height = args["height"] as? Int,
                  let rotation = args["rotation"] as? Int,
                  let bytesPerRowList = args["bytesPerRow"] as? [Int],
                  let bytesPerRow = bytesPerRowList.first,
                  let planes = args["planes"] as? [FlutterStandardTypedData],
                  let plane = planes.first else {
                result(FlutterError(code: "BAD_ARGS", message: "frame verisi eksik/bozuk", details: nil))
                return
            }
            let bgraBytes = plane.data
            DispatchQueue.global(qos: .userInitiated).async {
                let kp = self.extractKeypoints(
                    bgraBytes: bgraBytes,
                    width: width,
                    height: height,
                    bytesPerRow: bytesPerRow,
                    rotationDegrees: rotation
                )
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
        options.baseOptions.delegate = .GPU
        options.runningMode = .image
        options.minFaceDetectionConfidence    = 0.5
        options.minFacePresenceConfidence     = 0.5
        options.minPoseDetectionConfidence    = 0.5
        options.minHandLandmarksConfidence    = 0.5

        landmarker = try HolisticLandmarker(options: options)
    }

    // ── Ham frame → CVPixelBuffer ────────────────────────────────────────────

    /// Kameradan gelen ham BGRA8888 byte'larından bir CVPixelBuffer oluşturur.
    private func makePixelBuffer(from bytes: Data, width: Int, height: Int, bytesPerRow: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let destBytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        bytes.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            guard let srcBase = src.baseAddress else { return }
            if destBytesPerRow == bytesPerRow {
                memcpy(baseAddress, srcBase, bytes.count)
            } else {
                let rowBytes = min(bytesPerRow, destBytesPerRow)
                for row in 0..<height {
                    memcpy(
                        baseAddress.advanced(by: row * destBytesPerRow),
                        srcBase.advanced(by: row * bytesPerRow),
                        rowBytes
                    )
                }
            }
        }

        return buffer
    }

    // ── Keypoint çıkarımı ─────────────────────────────────────────────────────

    private func extractKeypoints(bgraBytes: Data, width: Int, height: Int, bytesPerRow: Int, rotationDegrees: Int) -> [Float]? {
        guard let landmarker = landmarker else {
            print("[MediaPipePlugin] landmarker nil (init başarısız)")
            return nil
        }
        guard let pixelBuffer = makePixelBuffer(from: bgraBytes, width: width, height: height, bytesPerRow: bytesPerRow) else {
            print("[MediaPipePlugin] CVPixelBuffer oluşturulamadı, size=\(width)x\(height)")
            return nil
        }

        // Option A: BGRA kamera akışı zaten dik (upright) geliyor; HolisticLandmarker
        // .up dışındaki orientation değerlerini Code=3 ile reddediyor.
        let mpImage: MPImage
        do {
            mpImage = try MPImage(pixelBuffer: pixelBuffer, orientation: .up)
        } catch {
            print("[MediaPipePlugin] MPImage init hatası: \(error), size=\(width)x\(height)")
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
