import ARKit
import Flutter
import SceneKit
import UIKit

// MARK: - Factory

class ArPosterViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return ArPosterFlutterView(frame: frame, messenger: messenger)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

// MARK: - Platform View

class ArPosterFlutterView: NSObject, FlutterPlatformView {
    private let arView: ARSCNView
    private let coordinator: ArPosterCoordinator

    init(frame: CGRect, messenger: FlutterBinaryMessenger) {
        arView = ARSCNView(frame: frame)
        coordinator = ArPosterCoordinator(arView: arView, messenger: messenger)
        super.init()
        arView.delegate = coordinator
        arView.session.delegate = coordinator
        arView.autoenablesDefaultLighting = false
        arView.rendersCameraGrain = false
    }

    func view() -> UIView { arView }
}

// MARK: - Coordinator (handles ARKit + channels)

class ArPosterCoordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate, FlutterStreamHandler {
    private weak var arView: ARSCNView?
    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    private var eventSink: FlutterEventSink?
    private var trackedNames = Set<String>()

    init(arView: ARSCNView, messenger: FlutterBinaryMessenger) {
        self.arView = arView
        methodChannel = FlutterMethodChannel(name: "com.itec.override/ar_method", binaryMessenger: messenger)
        eventChannel = FlutterEventChannel(name: "com.itec.override/ar_events", binaryMessenger: messenger)
        super.init()
        eventChannel.setStreamHandler(self)
        methodChannel.setMethodCallHandler(handle(_:result:))
    }

    // MARK: FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    // MARK: MethodChannel

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            guard let args = call.arguments as? [String: Any],
                  let posterIds = args["posterIds"] as? [String]
            else { result(nil); return }
            let widths = args["widths"] as? [String: Double] ?? [:]
            let texturePaths = args["texturePaths"] as? [String: String] ?? [:]
            setupARKit(posterIds: posterIds, widths: widths, texturePaths: texturePaths)
            result(nil)
        case "dispose":
            arView?.session.pause()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func setupARKit(posterIds: [String], widths: [String: Double], texturePaths: [String: String]) {
        var refImages = Set<ARReferenceImage>()
        for id in posterIds {
            var uiImage: UIImage?
            if let filePath = texturePaths[id] {
                uiImage = UIImage(contentsOfFile: filePath)
            } else {
                // Load from Flutter assets bundle (flutter_assets/assets/posters/<id>.png)
                let assetKey = "flutter_assets/assets/posters/\(id)"
                if let path = Bundle.main.path(forResource: assetKey, ofType: "png") {
                    uiImage = UIImage(contentsOfFile: path)
                } else {
                    print("[ArPosterPlugin] Asset not found in bundle: \(assetKey).png — skipping \(id)")
                }
            }
            guard let image = uiImage, let cgImage = image.cgImage else { continue }
            let physW = CGFloat(widths[id] ?? 0.3)
            let ref = ARReferenceImage(cgImage, orientation: .up, physicalWidth: physW)
            ref.name = id
            refImages.insert(ref)
        }
        let config = ARImageTrackingConfiguration()
        config.trackingImages = refImages
        config.maximumNumberOfTrackedImages = 10
        arView?.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    // MARK: ARSCNViewDelegate

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let ia = anchor as? ARImageAnchor else { return }
        let name = ia.referenceImage.name ?? ""
        trackedNames.insert(name)
        sendEvent(type: "detected", anchor: ia, renderer: renderer)
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let ia = anchor as? ARImageAnchor, ia.isTracked else { return }
        sendEvent(type: "updated", anchor: ia, renderer: renderer)
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        guard let ia = anchor as? ARImageAnchor else { return }
        let name = ia.referenceImage.name ?? ""
        trackedNames.remove(name)
        DispatchQueue.main.async { self.eventSink?(["type": "lost", "posterId": name]) }
    }

    // MARK: Projection

    private func sendEvent(type: String, anchor: ARImageAnchor, renderer: SCNSceneRenderer) {
        let name = anchor.referenceImage.name ?? ""
        let physW = Float(anchor.referenceImage.physicalSize.width)
        let physH = Float(anchor.referenceImage.physicalSize.height)
        let t = anchor.transform

        // Poster center in world space
        let center = SCNVector3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        let screenCenter = renderer.projectPoint(center)

        // Right and up vectors scaled to half-extents
        let right = SIMD3<Float>(t.columns.0.x, t.columns.0.y, t.columns.0.z) * (physW / 2)
        let fwd   = SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z) * (physH / 2)

        let c0 = SCNVector3(t.columns.3.x - right.x - fwd.x,
                            t.columns.3.y - right.y - fwd.y,
                            t.columns.3.z - right.z - fwd.z)
        let c1 = SCNVector3(t.columns.3.x + right.x - fwd.x,
                            t.columns.3.y + right.y - fwd.y,
                            t.columns.3.z + right.z - fwd.z)

        let sc0 = renderer.projectPoint(c0)
        let sc1 = renderer.projectPoint(c1)

        let dx = sc1.x - sc0.x
        let dy = sc1.y - sc0.y
        let widthPx = sqrt(dx * dx + dy * dy)
        let angle = atan2(dy, dx) * (180.0 / .pi)
        let ratio = Double(physH) / Double(physW)

        let event: [String: Any] = [
            "type": type,
            "posterId": name,
            "cx": Double(screenCenter.x),
            "cy": Double(screenCenter.y),
            "widthPx": Double(widthPx),
            "heightPx": Double(widthPx) * ratio,
            "angle": Double(angle)
        ]
        DispatchQueue.main.async { self.eventSink?(event) }
    }
}
