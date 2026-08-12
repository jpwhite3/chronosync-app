import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldTerminate(
    _ sender: NSApplication
  ) -> NSApplication.TerminateReply {
    let activeWindows = sender.windows.compactMap {
      $0 as? MainFlutterWindow
    }.filter {
      $0.hasActiveLiveActivity
    }
    guard let window = activeWindows.first else {
      return super.applicationShouldTerminate(sender)
    }
    guard window.confirmStoppingLiveSession() else {
      return .terminateCancel
    }
    for activeWindow in activeWindows {
      activeWindow.endAllLiveActivities()
    }
    return super.applicationShouldTerminate(sender)
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
