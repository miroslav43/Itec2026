import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        guard let controller = window?.rootViewController as? FlutterViewController else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }

        let factory = ArPosterViewFactory(messenger: controller.binaryMessenger)
        registrar(forPlugin: "ArPosterPlugin")?.register(factory, withId: "ar_poster_view")

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
