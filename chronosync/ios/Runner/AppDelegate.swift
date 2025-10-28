import Flutter
import UIKit
import AVFoundation
import AudioToolbox

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var audioPlayer: AVAudioPlayer?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    
    // Setup device audio channel
    let deviceAudioChannel = FlutterMethodChannel(
      name: "com.chronosync/device_audio_ios",
      binaryMessenger: controller.binaryMessenger
    )
    
    deviceAudioChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "getAvailableSounds":
        self?.getAvailableSounds(result: result)
      case "previewSound":
        guard let args = call.arguments as? [String: Any],
              let filePath = args["filePath"] as? String else {
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
    // iOS system notification sounds (commonly available)
    let sounds: [[String: Any]] = [
      [
        "id": "system_default",
        "displayName": "System Default",
        "filePath": "system_default",
        "isSystemSound": true
      ],
      [
        "id": "tri-tone",
        "displayName": "Tri-tone",
        "filePath": "tri-tone",
        "isSystemSound": true
      ],
      [
        "id": "chime",
        "displayName": "Chime",
        "filePath": "chime",
        "isSystemSound": true
      ],
      [
        "id": "glass",
        "displayName": "Glass",
        "filePath": "glass",
        "isSystemSound": true
      ],
      [
        "id": "horn",
        "displayName": "Horn",
        "filePath": "horn",
        "isSystemSound": true
      ],
      [
        "id": "bell",
        "displayName": "Bell",
        "filePath": "bell",
        "isSystemSound": true
      ],
      [
        "id": "electronic",
        "displayName": "Electronic",
        "filePath": "electronic",
        "isSystemSound": true
      ]
    ]
    
    result(sounds)
  }
  
  private func previewSound(filePath: String, result: @escaping FlutterResult) {
    // Stop any currently playing preview
    audioPlayer?.stop()
    audioPlayer = nil
    
    // Handle system default
    if filePath == "system_default" {
      // Play system sound
      AudioServicesPlaySystemSound(1007) // SMS alert tone
      result(nil)
      return
    }
    
    // Try to play from bundle if it's a custom sound
    if filePath.hasPrefix("assets/") {
      // Custom asset sound
      let fileName = (filePath as NSString).lastPathComponent
      let fileNameWithoutExt = (fileName as NSString).deletingPathExtension
      let fileExt = (fileName as NSString).pathExtension
      
      if let soundPath = Bundle.main.path(forResource: fileNameWithoutExt, ofType: fileExt) {
        do {
          audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: soundPath))
          audioPlayer?.prepareToPlay()
          audioPlayer?.play()
          result(nil)
          return
        } catch {
          result(FlutterError(code: "PLAYBACK_FAILED", message: "Failed to play sound: \(error.localizedDescription)", details: nil))
          return
        }
      }
    }
    
    // For system sounds, play the appropriate system sound ID
    // This is a simplified approach - iOS doesn't allow direct access to system notification sounds
    AudioServicesPlaySystemSound(1007)
    result(nil)
  }
  
  private func stopPreview(result: @escaping FlutterResult) {
    audioPlayer?.stop()
    audioPlayer = nil
    result(nil)
  }
}
