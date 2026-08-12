import Cocoa
import FlutterMacOS
import XCTest
@testable import ChronoSync

class RunnerTests: XCTestCase {

  func testDisplayFullscreenCommandsResolveToExpectedWindowState() {
    XCTAssertEqual(
      MainFlutterWindow.fullscreenTarget(
        method: "enter",
        isFullscreen: false
      ),
      true
    )
    XCTAssertEqual(
      MainFlutterWindow.fullscreenTarget(
        method: "exit",
        isFullscreen: true
      ),
      false
    )
    XCTAssertEqual(
      MainFlutterWindow.fullscreenTarget(
        method: "toggle",
        isFullscreen: false
      ),
      true
    )
    XCTAssertEqual(
      MainFlutterWindow.fullscreenTarget(
        method: "toggle",
        isFullscreen: true
      ),
      false
    )
    XCTAssertNil(
      MainFlutterWindow.fullscreenTarget(
        method: "unsupported",
        isFullscreen: false
      )
    )
  }
}
