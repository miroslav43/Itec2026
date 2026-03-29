import Flutter
import UIKit

/// On-device Stable Diffusion via shared C bridge + libsd_ios_complete.a (same MethodChannel as Android).
public class StableDiffusionPlugin: NSObject, FlutterPlugin {
  private static var instanceRetainer: StableDiffusionPlugin?

  /// Used when a `FlutterPluginRegistrar` is available (e.g. tests).
  public static func register(with registrar: FlutterPluginRegistrar) {
    register(messenger: registrar.messenger())
  }

  /// Registers using the implicit engine's application registrar messenger.
  public static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.itec.override/stable_diffusion",
      binaryMessenger: messenger
    )
    let instance = StableDiffusionPlugin()
    instanceRetainer = instance
    channel.setMethodCallHandler { call, result in
      instance.handle(call, result: result)
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isModelLoaded":
      result(sd_bridge_is_model_loaded())

    case "loadModel":
      guard let args = call.arguments as? [String: Any],
            let path = args["modelPath"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "modelPath is required", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let ok = sd_bridge_load_model(path)
        DispatchQueue.main.async {
          if ok {
            result(nil)
          } else {
            result(FlutterError(code: "LOAD_FAILED", message: "Failed to load model at: \(path)", details: nil))
          }
        }
      }

    case "generateImage":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
        return
      }
      let prompt = args["prompt"] as? String ?? ""
      let neg = args["negativePrompt"] as? String ?? ""
      let width = args["width"] as? Int ?? 64
      let height = args["height"] as? Int ?? 64
      let steps = args["steps"] as? Int ?? 6
      let cfg = Float((args["cfg"] as? Double) ?? 2.0)
      let seed = (args["seed"] as? Int).map { Int64($0) } ?? 42

      DispatchQueue.global(qos: .userInitiated).async {
        var out: UnsafeMutablePointer<UInt8>?
        var len: Int32 = 0
        let ok: Bool = prompt.withCString { pPrompt in
          neg.withCString { pNeg in
            sd_bridge_generate_rgb(
              pPrompt, pNeg,
              Int32(width), Int32(height),
              Int32(steps), cfg, seed,
              &out, &len
            )
          }
        }
        let byteCount = Int(len)
        if !ok || out == nil || byteCount <= 0 {
          DispatchQueue.main.async {
            result(FlutterError(code: "GEN_FAILED", message: "Native image generation returned null", details: nil))
          }
          return
        }
        let data = Data(bytes: out!, count: byteCount)
        free(out)
        guard let png = Self.rgbToPng(rgb: data, width: width, height: height) else {
          DispatchQueue.main.async {
            result(FlutterError(code: "ENCODE_FAILED", message: "PNG encode failed", details: nil))
          }
          return
        }
        DispatchQueue.main.async {
          result(FlutterStandardTypedData(bytes: png))
        }
      }

    case "freeModel":
      sd_bridge_free_model()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func rgbToPng(rgb: Data, width: Int, height: Int) -> Data? {
    let expected = width * height * 3
    guard rgb.count >= expected else { return nil }

    UIGraphicsBeginImageContextWithOptions(CGSize(width: CGFloat(width), height: CGFloat(height)), true, 1.0)
    defer { UIGraphicsEndImageContext() }
    guard let ctx = UIGraphicsGetCurrentContext() else { return nil }

    rgb.withUnsafeBytes { raw in
      let ptr = raw.bindMemory(to: UInt8.self).baseAddress!
      for y in 0..<height {
        for x in 0..<width {
          let i = (y * width + x) * 3
          let r = CGFloat(ptr[i]) / 255.0
          let g = CGFloat(ptr[i + 1]) / 255.0
          let b = CGFloat(ptr[i + 2]) / 255.0
          ctx.setFillColor(red: r, green: g, blue: b, alpha: 1.0)
          ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
      }
    }

    guard let image = UIGraphicsGetImageFromCurrentImageContext() else { return nil }
    return image.pngData()
  }
}
