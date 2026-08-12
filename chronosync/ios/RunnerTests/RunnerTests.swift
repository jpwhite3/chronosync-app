import Flutter
import UIKit
import XCTest

@testable import Runner

class RunnerTests: XCTestCase {

  func testIOSAdvertisesOnlyTheSupportedAlertChoice() {
    let sounds = AppDelegate.availableDeviceSounds()

    XCTAssertEqual(sounds.count, 1)
    XCTAssertEqual(sounds.first?["id"] as? String, "system_default")
    XCTAssertEqual(
      sounds.first?["displayName"] as? String,
      "System Default"
    )
  }

  func testUnsupportedIOSSoundHasNoPreviewMapping() {
    XCTAssertEqual(AppDelegate.previewSystemSoundID(for: "system_default"), 1007)
    XCTAssertNil(AppDelegate.previewSystemSoundID(for: "chime"))
    XCTAssertNil(AppDelegate.previewSystemSoundID(for: "assets/audio/custom.mp3"))
  }

  func testWebSocketHandshakeUsesRFC6455AcceptValue() {
    XCTAssertEqual(
      NearbyHostService.websocketAccept(for: "dGhlIHNhbXBsZSBub25jZQ=="),
      "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
    )
  }

  func testDisplayWebSocketIsReceiveOnly() {
    XCTAssertTrue(NearbyHostService.roleCanSendCommands("participant"))
    XCTAssertTrue(NearbyHostService.roleCanSendCommands("controller"))
    XCTAssertFalse(NearbyHostService.roleCanSendCommands("display"))
    XCTAssertFalse(NearbyHostService.roleCanSendCommands(nil))
  }

  func testPeerRoleUpdatesAreCanonicalAndCannotGrantHost() {
    let token = String(repeating: "a", count: 43)
    let update = NearbyHostService.peerRoleUpdate(
      from: ["deviceToken": token, "role": "controller"]
    )

    XCTAssertEqual(update?.deviceToken, token)
    XCTAssertEqual(update?.role, "controller")
    XCTAssertNil(
      NearbyHostService.peerRoleUpdate(
        from: ["deviceToken": token, "role": "host"]
      )
    )
    XCTAssertNil(
      NearbyHostService.peerRoleUpdate(
        from: ["deviceToken": "not-a-token", "role": "participant"]
      )
    )
  }

  func testHostRoleOverrideAuthenticatesReconnects() {
    let token = String(repeating: "a", count: 43)

    XCTAssertEqual(
      NearbyHostService.effectivePeerRole(
        requestedRole: "participant",
        deviceToken: token,
        overrides: [token: "controller"]
      ),
      "controller"
    )
    XCTAssertEqual(
      NearbyHostService.effectivePeerRole(
        requestedRole: "participant",
        deviceToken: token,
        overrides: [token: "participant"]
      ),
      "participant"
    )
    XCTAssertEqual(
      NearbyHostService.effectivePeerRole(
        requestedRole: "host",
        deviceToken: token,
        overrides: [token: "controller"]
      ),
      "host"
    )
  }

  func testFallbackJoinPageScrubsInviteFragmentBeforeParsing() {
    XCTAssertTrue(NearbyHostService.fallbackJoinPageScrubsFragment())
  }

  func testNearbyEnvelopeDirectionsAreRestrictedByRole() {
    XCTAssertTrue(
      NearbyHostService.hostCanBroadcastEnvelopeKind("snapshot")
    )
    XCTAssertFalse(
      NearbyHostService.hostCanBroadcastEnvelopeKind("command")
    )
    XCTAssertTrue(
      NearbyHostService.clientCanSendEnvelopeKind(
        "command",
        role: "participant"
      )
    )
    XCTAssertFalse(
      NearbyHostService.clientCanSendEnvelopeKind(
        "snapshot",
        role: "participant"
      )
    )
    XCTAssertFalse(
      NearbyHostService.clientCanSendEnvelopeKind(
        "command",
        role: "display"
      )
    )
  }

  func testWebSocketMessageCapMatchesTheDartEnvelopePreflight() {
    XCTAssertTrue(
      NearbyHostService.webSocketMessageSizeAllowed(320 * 1024)
    )
    XCTAssertFalse(
      NearbyHostService.webSocketMessageSizeAllowed(320 * 1024 + 1)
    )
    XCTAssertFalse(NearbyHostService.webSocketMessageSizeAllowed(-1))
  }

  func testHeartbeatFramesDoNotGrantCommandAccess() {
    XCTAssertTrue(NearbyHostService.isHeartbeatPing(#"{"type":"ping"}"#))
    XCTAssertFalse(NearbyHostService.isHeartbeatPing(#"{"type":"command"}"#))
    XCTAssertFalse(NearbyHostService.isHeartbeatPing("not-json"))
    XCTAssertFalse(NearbyHostService.roleCanSendCommands("display"))
  }

  func testSilentClientHeartbeatExpiresAfterBoundedTimeout() {
    let lastSeen = Date(timeIntervalSince1970: 1_000)
    XCTAssertFalse(
      NearbyHostService.heartbeatExpired(
        lastSeen: lastSeen,
        now: lastSeen.addingTimeInterval(18)
      )
    )
    XCTAssertTrue(
      NearbyHostService.heartbeatExpired(
        lastSeen: lastSeen,
        now: lastSeen.addingTimeInterval(18.001)
      )
    )
  }

  func testIncompleteHTTPHandshakeExpiresAfterBoundedDeadline() {
    let acceptedAt = Date(timeIntervalSince1970: 1_000)
    XCTAssertFalse(
      NearbyHostService.httpHandshakeExpired(
        acceptedAt: acceptedAt,
        now: acceptedAt.addingTimeInterval(10)
      )
    )
    XCTAssertTrue(
      NearbyHostService.httpHandshakeExpired(
        acceptedAt: acceptedAt,
        now: acceptedAt.addingTimeInterval(10.001)
      )
    )
  }

  func testHTTPHandshakeSweepEvictsExpiredClientAndRecoversCapacity() {
    let now = Date(timeIntervalSince1970: 2_000)
    let expiredClientID = UUID()
    let closingClientID = UUID()
    let websocketClientID = UUID()
    var clients = (0..<50).map { _ in
      NearbyHostService.HTTPHandshakeSweepClient(
        id: UUID(),
        acceptedAt: now,
        isAwaitingHandshake: true,
        isClosing: false
      )
    }
    clients[0] = NearbyHostService.HTTPHandshakeSweepClient(
      id: expiredClientID,
      acceptedAt: now.addingTimeInterval(-10.001),
      isAwaitingHandshake: true,
      isClosing: false
    )
    clients[1] = NearbyHostService.HTTPHandshakeSweepClient(
      id: closingClientID,
      acceptedAt: now.addingTimeInterval(-10.001),
      isAwaitingHandshake: true,
      isClosing: true
    )
    clients[2] = NearbyHostService.HTTPHandshakeSweepClient(
      id: websocketClientID,
      acceptedAt: now.addingTimeInterval(-10.001),
      isAwaitingHandshake: false,
      isClosing: false
    )

    let result = NearbyHostService.httpHandshakeSweep(
      clients: clients,
      now: now,
      maximumClients: 50
    )

    XCTAssertEqual(result.expiredClientIDs, [expiredClientID])
    XCTAssertEqual(result.retainedClientCount, 49)
    XCTAssertTrue(result.hasAvailableCapacity)
  }

  func testNearbyCapacityAllowsExactlyFiftyGuestDevices() {
    XCTAssertTrue(
      NearbyHostService.hasAvailableClientCapacity(
        clientCount: 49,
        maximumClients: 50
      )
    )
    XCTAssertFalse(
      NearbyHostService.hasAvailableClientCapacity(
        clientCount: 50,
        maximumClients: 50
      )
    )
  }

  func testNearbyTeardownCreatesDisconnectPresenceForAuthenticatedPeers() {
    let clientID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
    let event = NearbyHostService.clientDisconnectedEvent(
      clientID: clientID,
      role: "display",
      deviceToken: String(repeating: "d", count: 43)
    )

    XCTAssertEqual(event?["type"] as? String, "client_disconnected")
    XCTAssertEqual(event?["clientId"] as? String, clientID.uuidString)
    XCTAssertEqual(event?["role"] as? String, "display")
    XCTAssertEqual(
      event?["deviceToken"] as? String,
      String(repeating: "d", count: 43)
    )
    XCTAssertNil(
      NearbyHostService.clientDisconnectedEvent(
        clientID: clientID,
        role: nil,
        deviceToken: String(repeating: "d", count: 43)
      )
    )
  }

  func testTargetedDisconnectAcceptsOnlyCanonicalClientIDs() {
    let clientID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

    XCTAssertEqual(
      NearbyHostService.disconnectClientID(
        from: ["connectionId": clientID.uuidString]
      ),
      clientID
    )
    XCTAssertNil(
      NearbyHostService.disconnectClientID(
        from: ["connectionId": "not-a-client-id"]
      )
    )
    XCTAssertNil(NearbyHostService.disconnectClientID(from: nil))
  }

  func testDeviceTokenAdmissionRejectsBlockedAndMalformedTokens() {
    let token = String(repeating: "a", count: 43)
    let protocols = [
      "chronosync.v1",
      "role.participant",
      "cap.\(String(repeating: "b", count: 43))",
      "device.\(token)",
    ]

    XCTAssertEqual(
      NearbyHostService.admittedDeviceToken(
        from: protocols,
        blockedTokens: []
      ),
      token
    )
    XCTAssertNil(
      NearbyHostService.admittedDeviceToken(
        from: protocols,
        blockedTokens: [token]
      )
    )
    XCTAssertNil(
      NearbyHostService.admittedDeviceToken(
        from: ["chronosync.v1", "device.raw device id"],
        blockedTokens: []
      )
    )
  }

  func testDeviceRevocationParsesTokenAndMatchesEveryParallelSocket() {
    let token = String(repeating: "a", count: 43)

    XCTAssertEqual(
      NearbyHostService.revokeDeviceToken(from: ["deviceToken": token]),
      token
    )
    XCTAssertNil(
      NearbyHostService.revokeDeviceToken(
        from: ["deviceToken": "not a token"]
      )
    )
    XCTAssertTrue(
      NearbyHostService.shouldCloseClient(
        deviceToken: token,
        revokedToken: token
      )
    )
    XCTAssertTrue(
      NearbyHostService.shouldCloseClient(
        deviceToken: token,
        revokedToken: token
      )
    )
    XCTAssertFalse(
      NearbyHostService.shouldCloseClient(
        deviceToken: String(repeating: "b", count: 43),
        revokedToken: token
      )
    )
  }

}
