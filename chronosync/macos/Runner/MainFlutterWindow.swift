import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  static let displayFullscreenChannelName =
    "com.chronosync/display_fullscreen"

  private var displayFullscreenChannel: FlutterMethodChannel?
  private var displayFullscreenObservers: [NSObjectProtocol] = []
  private var liveActivityChannel: FlutterMethodChannel?
  private var liveActivities: [String: NSObjectProtocol] = [:]

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerDisplayFullscreenChannel(
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    registerLiveActivityChannel(
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    super.awakeFromNib()
  }

  private func registerDisplayFullscreenChannel(
    binaryMessenger: FlutterBinaryMessenger
  ) {
    let channel = FlutterMethodChannel(
      name: Self.displayFullscreenChannelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let window = self else {
        result(
          FlutterError(
            code: "window_unavailable",
            message: "The ChronoSync window is unavailable.",
            details: nil
          )
        )
        return
      }

      let isFullscreen = window.styleMask.contains(.fullScreen)
      guard let target = Self.fullscreenTarget(
        method: call.method,
        isFullscreen: isFullscreen
      ) else {
        result(FlutterMethodNotImplemented)
        return
      }
      if target != isFullscreen {
        window.toggleFullScreen(nil)
      }
      result(target)
    }
    let notificationCenter = NotificationCenter.default
    displayFullscreenObservers = [
      notificationCenter.addObserver(
        forName: NSWindow.didEnterFullScreenNotification,
        object: self,
        queue: .main
      ) { _ in
        channel.invokeMethod("stateChanged", arguments: true)
      },
      notificationCenter.addObserver(
        forName: NSWindow.didExitFullScreenNotification,
        object: self,
        queue: .main
      ) { _ in
        channel.invokeMethod("stateChanged", arguments: false)
      },
    ]
    displayFullscreenChannel = channel
  }

  static func fullscreenTarget(
    method: String,
    isFullscreen: Bool
  ) -> Bool? {
    switch method {
    case "enter":
      return true
    case "exit":
      return false
    case "toggle":
      return !isFullscreen
    default:
      return nil
    }
  }

  var hasActiveLiveActivity: Bool {
    return !liveActivities.isEmpty
  }

  override func performClose(_ sender: Any?) {
    guard hasActiveLiveActivity else {
      super.performClose(sender)
      return
    }
    if confirmStoppingLiveSession() {
      endAllLiveActivities()
      super.performClose(sender)
    }
  }

  func confirmStoppingLiveSession() -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Quit during the live session?"
    alert.informativeText =
      "ChronoSync will leave immediately. If this Mac is the host, connected devices will stop receiving updates and the final summary may be incomplete."
    alert.addButton(withTitle: "Keep Session Open")
    alert.addButton(withTitle: "Quit Anyway")
    return alert.runModal() == .alertSecondButtonReturn
  }

  func endAllLiveActivities() {
    for activity in liveActivities.values {
      ProcessInfo.processInfo.endActivity(activity)
    }
    liveActivities.removeAll()
  }

  private func registerLiveActivityChannel(
    binaryMessenger: FlutterBinaryMessenger
  ) {
    let channel = FlutterMethodChannel(
      name: "com.chronosync/live_activity",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let window = self else {
        result(
          FlutterError(
            code: "window_unavailable",
            message: "The ChronoSync window is unavailable.",
            details: nil
          )
        )
        return
      }

      switch call.method {
      case "begin":
        guard
          let arguments = call.arguments as? [String: Any],
          let reason = arguments["reason"] as? String,
          let keepDisplayAwake = arguments["keepDisplayAwake"] as? Bool
        else {
          result(
            FlutterError(
              code: "invalid_arguments",
              message: "A live activity requires a reason and display policy.",
              details: nil
            )
          )
          return
        }
        var options: ProcessInfo.ActivityOptions = [
          .userInitiated,
          .idleSystemSleepDisabled,
          .automaticTerminationDisabled,
        ]
        if keepDisplayAwake {
          options.insert(.idleDisplaySleepDisabled)
        }
        let activity = ProcessInfo.processInfo.beginActivity(
          options: options,
          reason: reason
        )
        let token = UUID().uuidString
        window.liveActivities[token] = activity
        result(token)
      case "end":
        guard
          let arguments = call.arguments as? [String: Any],
          let token = arguments["token"] as? String,
          let activity = window.liveActivities.removeValue(forKey: token)
        else {
          result(nil)
          return
        }
        ProcessInfo.processInfo.endActivity(activity)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    liveActivityChannel = channel
  }

  deinit {
    for observer in displayFullscreenObservers {
      NotificationCenter.default.removeObserver(observer)
    }
    endAllLiveActivities()
  }
}
