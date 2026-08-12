import AudioToolbox
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var nearbyHostService: NearbyHostService?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    guard
      let registrar = registrar(
        forPlugin: "com.chronosync.native_channels"
      )
    else {
      return false
    }
    let messenger = registrar.messenger()

    let nearbyHostService = NearbyHostService()
    self.nearbyHostService = nearbyHostService
    let nearbyHostChannel = FlutterMethodChannel(
      name: "com.chronosync/nearby_host",
      binaryMessenger: messenger
    )
    nearbyHostChannel.setMethodCallHandler { [weak nearbyHostService] call, result in
      nearbyHostService?.handle(call, result: result)
    }
    let nearbyHostEvents = FlutterEventChannel(
      name: "com.chronosync/nearby_host/events",
      binaryMessenger: messenger
    )
    nearbyHostEvents.setStreamHandler(nearbyHostService)

    // Setup device audio channel
    let deviceAudioChannel = FlutterMethodChannel(
      name: "com.chronosync/device_audio_ios",
      binaryMessenger: messenger
    )

    deviceAudioChannel.setMethodCallHandler {
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "getAvailableSounds":
        self?.getAvailableSounds(result: result)
      case "previewSound":
        guard let args = call.arguments as? [String: Any],
          let filePath = args["filePath"] as? String
        else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing filePath", details: nil))
          return
        }
        self?.previewSound(filePath: filePath, result: result)
      case "stopPreview":
        self?.stopPreview(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Device Audio Methods

  private func getAvailableSounds(result: @escaping FlutterResult) {
    result(Self.availableDeviceSounds())
  }

  static func availableDeviceSounds() -> [[String: Any]] {
    [
      [
        "id": "system_default",
        "displayName": "System Default",
        "filePath": "system_default",
        "isSystemSound": true,
      ],
    ]
  }

  private func previewSound(filePath: String, result: @escaping FlutterResult) {
    guard let soundID = Self.previewSystemSoundID(for: filePath) else {
      result(
        FlutterError(
          code: "UNSUPPORTED_SOUND",
          message: "This sound is not available on iPhone.",
          details: nil
        )
      )
      return
    }
    AudioServicesPlaySystemSound(soundID)
    result(nil)
  }

  static func previewSystemSoundID(for filePath: String) -> SystemSoundID? {
    filePath == "system_default" ? 1007 : nil
  }

  private func stopPreview(result: @escaping FlutterResult) {
    result(nil)
  }
}
