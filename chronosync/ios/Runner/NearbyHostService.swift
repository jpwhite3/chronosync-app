import CryptoKit
import Darwin
import Flutter
import Foundation
import Network
import UIKit

/// Foreground-only HTTP/WebSocket host for nearby ChronoSync sessions.
///
/// The native layer authenticates the role-scoped invitation capability and
/// transports opaque, encrypted session envelopes. Session authorization and
/// state changes remain in the Dart host.
final class NearbyHostService: NSObject, FlutterStreamHandler {
  private struct Configuration {
    let sessionID: String
    let participantCapability: String?
    let displayCapability: String?
    let expiresAt: Date
  }

  private enum ClientPhase {
    case http
    case websocket
  }

  private final class Client {
    init(connection: NWConnection) {
      self.connection = connection
    }

    let id = UUID()
    let connection: NWConnection
    var phase = ClientPhase.http
    var buffer = Data()
    var role: String?
    var deviceToken: String?
    var isClosing = false
    var fragmentedOpcode: UInt8?
    var fragmentedPayload = Data()
    let acceptedAt = Date()
    var lastHeartbeatAt = Date()
  }

  struct HTTPHandshakeSweepClient {
    let id: UUID
    let acceptedAt: Date
    let isAwaitingHandshake: Bool
    let isClosing: Bool
  }

  struct HTTPHandshakeSweepResult {
    let expiredClientIDs: [UUID]
    let retainedClientCount: Int
    let hasAvailableCapacity: Bool
  }

  struct PeerRoleUpdate {
    let deviceToken: String
    let role: String
  }

  private static let serviceType = "_chronosync._tcp"
  private static let protocolName = "chronosync.v1"
  private static let maximumHeaderBytes = 16 * 1024
  private static let maximumWebSocketMessageBytes = 320 * 1024
  private static let maximumClients = 50
  private static let maximumRetainedDevices = 250
  private static let heartbeatSweepInterval: TimeInterval = 5
  private static let heartbeatTimeout: TimeInterval = 18
  private static let httpHandshakeTimeout: TimeInterval = 10

  private let queue = DispatchQueue(label: "com.chronosync.nearby-host")
  private var listener: NWListener?
  private var configuration: Configuration?
  private var clients: [UUID: Client] = [:]
  private var eventSink: FlutterEventSink?
  private var latestHostEnvelope: String?
  private var preferredPort: NWEndpoint.Port?
  private var pendingStart: ((Result<[String: Any], Error>) -> Void)?
  private var heartbeatTimer: DispatchSourceTimer?
  private var blockedDeviceTokens: Set<String> = []
  private var roleOverridesByDeviceToken: [String: String] = [:]
  private var isSuspended = false
  private var isRestartingAfterForeground = false

  override init() {
    super.init()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationWillEnterForeground),
      name: UIApplication.willEnterForegroundNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationWillTerminate),
      name: UIApplication.willTerminateNotification,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    listener?.cancel()
    heartbeatTimer?.cancel()
    for client in clients.values {
      client.connection.cancel()
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startHost":
      startHost(arguments: call.arguments, result: result)
    case "startHostWithInvitation":
      startHostWithInvitation(arguments: call.arguments, result: result)
    case "broadcast", "send":
      broadcast(arguments: call.arguments, result: result)
    case "disconnectClient":
      disconnectClient(arguments: call.arguments, result: result)
    case "revokeDevice":
      revokeDevice(arguments: call.arguments, result: result)
    case "setPeerRole":
      setPeerRole(arguments: call.arguments, result: result)
    case "stopHost":
      stopHost(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - FlutterStreamHandler

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    queue.async { [weak self] in
      self?.eventSink = events
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    queue.async { [weak self] in
      self?.eventSink = nil
    }
    return nil
  }

  // MARK: - Flutter methods

  private func startHost(arguments: Any?, result: @escaping FlutterResult) {
    guard UIApplication.shared.applicationState == .active else {
      result(
        FlutterError(
          code: "FOREGROUND_REQUIRED",
          message: "Keep ChronoSync open while starting a nearby session.",
          details: nil
        )
      )
      return
    }
    guard
      let arguments = arguments as? [String: Any],
      let sessionID = nonemptyString(arguments["sessionId"]),
      let participantCapability = nonemptyString(arguments["participantCapability"]),
      let displayCapability = nonemptyString(arguments["displayCapability"]),
      nonemptyString(arguments["sessionSecret"]) != nil,
      let expiresAtString = nonemptyString(arguments["expiresAt"]),
      let expiresAt = parseDate(expiresAtString)
    else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS",
          message: "A session ID, both role capabilities, and an expiry are required.",
          details: nil
        )
      )
      return
    }
    guard expiresAt > Date() else {
      result(
        FlutterError(
          code: "INVITATION_EXPIRED",
          message: "The nearby-session invitation has already expired.",
          details: nil
        )
      )
      return
    }

    let configuration = Configuration(
      sessionID: sessionID,
      participantCapability: normalizedCapability(participantCapability),
      displayCapability: normalizedCapability(displayCapability),
      expiresAt: expiresAt
    )
    beginHosting(configuration: configuration) { outcome in
      switch outcome {
      case .success(let response):
        result(response)
      case .failure(let error):
        result(
          FlutterError(
            code: "HOST_START_FAILED",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
  }

  private func startHostWithInvitation(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard UIApplication.shared.applicationState == .active else {
      result(
        FlutterError(
          code: "FOREGROUND_REQUIRED",
          message: "Keep ChronoSync open while starting a nearby session.",
          details: nil
        )
      )
      return
    }
    guard
      let arguments = arguments as? [String: Any],
      let invitation = arguments["invitation"] as? [String: Any],
      (invitation["protocolVersion"] as? NSNumber)?.intValue == 1,
      nonemptyString(invitation["transport"]) == "nearbyLan",
      let sessionID = nonemptyString(invitation["sessionId"]),
      let capability = nonemptyString(invitation["capability"]),
      let role = nonemptyString(invitation["requestedRole"]),
      let expiresAtString = nonemptyString(invitation["expiresAt"]),
      let expiresAt = parseDate(expiresAtString),
      role == "participant" || role == "display"
    else {
      result(
        FlutterError(
          code: "INVALID_INVITATION",
          message: "The nearby invitation is incomplete or unsupported.",
          details: nil
        )
      )
      return
    }
    guard expiresAt > Date() else {
      result(
        FlutterError(
          code: "INVITATION_EXPIRED",
          message: "The nearby-session invitation has already expired.",
          details: nil
        )
      )
      return
    }

    let configuration = Configuration(
      sessionID: sessionID,
      participantCapability: role == "participant" ? normalizedCapability(capability) : nil,
      displayCapability: role == "display" ? normalizedCapability(capability) : nil,
      expiresAt: expiresAt
    )
    beginHosting(configuration: configuration) { outcome in
      switch outcome {
      case .success:
        result(nil)
      case .failure(let error):
        result(
          FlutterError(
            code: "HOST_START_FAILED",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
  }

  private func broadcast(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let arguments = arguments as? [String: Any],
      let envelope = nonemptyString(arguments["envelope"])
    else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS",
          message: "An encoded session envelope is required.",
          details: nil
        )
      )
      return
    }

    queue.async { [weak self] in
      guard let self = self, let configuration = self.configuration else {
        self?.complete(
          result,
          with: FlutterError(
            code: "HOST_NOT_RUNNING",
            message: "The nearby host is not running.",
            details: nil
          )
        )
        return
      }
      guard
        self.validEnvelope(envelope, sessionID: configuration.sessionID),
        Self.hostCanBroadcastEnvelopeKind(self.envelopeKind(envelope))
      else {
        self.complete(
          result,
          with: FlutterError(
            code: "INVALID_ENVELOPE",
            message: "The host envelope is malformed or belongs to another session.",
            details: nil
          )
        )
        return
      }

      self.latestHostEnvelope = envelope
      for client in self.clients.values
        where client.phase == .websocket && !client.isClosing
      {
        self.sendText(envelope, to: client)
      }
      self.complete(result, with: nil)
    }
  }

  private func disconnectClient(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard let clientID = Self.disconnectClientID(from: arguments) else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS",
          message: "A valid nearby client connection ID is required.",
          details: nil
        )
      )
      return
    }

    queue.async { [weak self] in
      guard let self = self, self.configuration != nil else {
        self?.complete(
          result,
          with: FlutterError(
            code: "HOST_NOT_RUNNING",
            message: "The nearby host is not running.",
            details: nil
          )
        )
        return
      }
      if let client = self.clients[clientID] {
        self.close(client, code: 4003)
      }
      self.complete(result, with: nil)
    }
  }

  static func disconnectClientID(from arguments: Any?) -> UUID? {
    guard
      let arguments = arguments as? [String: Any],
      let value = arguments["connectionId"] as? String
    else {
      return nil
    }
    return UUID(uuidString: value)
  }

  private func revokeDevice(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard let deviceToken = Self.revokeDeviceToken(from: arguments) else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS",
          message: "A valid room-scoped device token is required.",
          details: nil
        )
      )
      return
    }

    queue.async { [weak self] in
      guard let self = self, self.configuration != nil else {
        self?.complete(
          result,
          with: FlutterError(
            code: "HOST_NOT_RUNNING",
            message: "The nearby host is not running.",
            details: nil
          )
        )
        return
      }
      self.blockedDeviceTokens.insert(deviceToken)
      self.roleOverridesByDeviceToken.removeValue(forKey: deviceToken)
      let matchingClients = self.clients.values.filter {
        Self.shouldCloseClient(
          deviceToken: $0.deviceToken,
          revokedToken: deviceToken
        )
      }
      for client in matchingClients {
        self.close(client, code: 4003)
      }
      self.complete(result, with: nil)
    }
  }

  static func revokeDeviceToken(from arguments: Any?) -> String? {
    guard
      let arguments = arguments as? [String: Any],
      let token = arguments["deviceToken"] as? String,
      validDeviceToken(token)
    else {
      return nil
    }
    return token
  }

  static func shouldCloseClient(
    deviceToken: String?,
    revokedToken: String
  ) -> Bool {
    deviceToken == revokedToken
  }

  private func setPeerRole(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard let update = Self.peerRoleUpdate(from: arguments) else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS",
          message: "A valid room-scoped device token and peer role are required.",
          details: nil
        )
      )
      return
    }

    queue.async { [weak self] in
      guard let self = self, self.configuration != nil else {
        self?.complete(
          result,
          with: FlutterError(
            code: "HOST_NOT_RUNNING",
            message: "The nearby host is not running.",
            details: nil
          )
        )
        return
      }
      guard
        self.roleOverridesByDeviceToken[update.deviceToken] != nil
          || self.roleOverridesByDeviceToken.count < Self.maximumRetainedDevices
      else {
        self.complete(
          result,
          with: FlutterError(
            code: "RETAINED_DEVICE_LIMIT",
            message: "This session has retained the maximum number of devices.",
            details: nil
          )
        )
        return
      }
      self.roleOverridesByDeviceToken[update.deviceToken] = update.role
      for client in self.clients.values
        where client.phase == .websocket
          && !client.isClosing
          && client.deviceToken == update.deviceToken
      {
        client.role = update.role
        self.emit([
          "type": "client_connected",
          "clientId": client.id.uuidString,
          "role": update.role,
          "deviceToken": update.deviceToken,
        ])
      }
      self.complete(result, with: nil)
    }
  }

  static func peerRoleUpdate(from arguments: Any?) -> PeerRoleUpdate? {
    guard
      let arguments = arguments as? [String: Any],
      let deviceToken = arguments["deviceToken"] as? String,
      validDeviceToken(deviceToken),
      let role = arguments["role"] as? String,
      role == "participant" || role == "controller" || role == "display"
    else {
      return nil
    }
    return PeerRoleUpdate(deviceToken: deviceToken, role: role)
  }

  static func effectivePeerRole(
    requestedRole: String,
    deviceToken: String,
    overrides: [String: String]
  ) -> String {
    guard requestedRole != "host" else { return requestedRole }
    return overrides[deviceToken] ?? requestedRole
  }

  private func stopHost(result: @escaping FlutterResult) {
    queue.async { [weak self] in
      self?.stopNetwork(retainConfiguration: false)
      self?.complete(result, with: nil)
    }
  }

  private func beginHosting(
    configuration: Configuration,
    completion: @escaping (Result<[String: Any], Error>) -> Void
  ) {
    queue.async { [weak self] in
      guard let self = self else { return }
      self.stopNetwork(retainConfiguration: false)
      self.configuration = configuration
      self.isSuspended = false
      self.isRestartingAfterForeground = false
      self.pendingStart = completion
      self.startListener(on: nil)
    }
  }

  // MARK: - Foreground lifecycle

  @objc private func applicationDidEnterBackground() {
    queue.async { [weak self] in
      guard let self = self, self.configuration != nil else { return }
      let wasStarting = self.pendingStart != nil
      self.isSuspended = true
      self.preferredPort = self.listener?.port
      self.stopNetwork(retainConfiguration: !wasStarting)
      self.setIdleTimerDisabled(false)
      self.emit(["type": "backgrounded"])
    }
  }

  @objc private func applicationWillEnterForeground() {
    queue.async { [weak self] in
      guard
        let self = self,
        self.configuration != nil,
        self.isSuspended
      else {
        return
      }
      self.isSuspended = false
      self.isRestartingAfterForeground = true
      self.startListener(on: self.preferredPort)
    }
  }

  @objc private func applicationWillTerminate() {
    queue.async { [weak self] in
      self?.stopNetwork(retainConfiguration: false)
    }
  }

  // MARK: - Listener

  private func startListener(on port: NWEndpoint.Port?) {
    guard let configuration = configuration else { return }
    guard configuration.expiresAt > Date() else {
      roleOverridesByDeviceToken.removeAll()
      failListener(
        NearbyHostError("The nearby-session invitation has expired.")
      )
      return
    }

    do {
      let parameters = NWParameters.tcp
      parameters.allowLocalEndpointReuse = true
      parameters.includePeerToPeer = true
      let listener = try NWListener(using: parameters, on: port ?? .any)
      let txtRecord = NetService.data(
        fromTXTRecord: [
          "v": Data("1".utf8),
          "path": Data("/".utf8),
        ]
      )
      let serviceName = "ChronoSync-\(configuration.sessionID.prefix(8))"
      listener.service = NWListener.Service(
        name: serviceName,
        type: Self.serviceType,
        domain: nil,
        txtRecord: txtRecord
      )
      self.listener = listener

      listener.stateUpdateHandler = { [weak self, weak listener] state in
        guard let self = self, let listener = listener, self.listener === listener else {
          return
        }
        switch state {
        case .ready:
          self.listenerBecameReady(listener, serviceName: serviceName)
        case .failed(let error):
          self.failListener(error)
        case .waiting(let error):
          self.emit([
            "type": "listener_waiting",
            "message": error.localizedDescription,
          ])
        case .cancelled:
          break
        default:
          break
        }
      }
      listener.newConnectionHandler = { [weak self] connection in
        self?.accept(connection)
      }
      listener.start(queue: queue)
      queue.asyncAfter(deadline: .now() + 30) { [weak self, weak listener] in
        guard
          let self = self,
          let listener = listener,
          self.listener === listener,
          self.pendingStart != nil
        else {
          return
        }
        self.failListener(
          NearbyHostError(
            "ChronoSync could not start nearby hosting. Check Local Network permission and Wi-Fi."
          )
        )
      }
    } catch {
      failListener(error)
    }
  }

  private func listenerBecameReady(_ listener: NWListener, serviceName: String) {
    guard let port = listener.port else {
      failListener(NearbyHostError("The nearby listener did not select a port."))
      return
    }
    guard let address = localIPv4Address() else {
      failListener(
        NearbyHostError(
          "Connect this iPhone to Wi-Fi before starting a nearby session."
        )
      )
      return
    }

    let endpoint = "http://\(address):\(port.rawValue)/"
    preferredPort = port
    startHeartbeatMonitor()
    setIdleTimerDisabled(true)
    emit([
      "type": isRestartingAfterForeground ? "foregrounded" : "listener_ready",
      "endpoint": endpoint,
    ])
    isRestartingAfterForeground = false

    finishStart(
      .success([
        "endpoint": endpoint,
        "serviceName": serviceName,
        "port": Int(port.rawValue),
      ])
    )
  }

  private func failListener(_ error: Error) {
    listener?.cancel()
    listener = nil
    setIdleTimerDisabled(false)
    emit([
      "type": "listener_failed",
      "message": error.localizedDescription,
    ])
    isRestartingAfterForeground = false
    finishStart(.failure(error))
  }

  private func stopNetwork(retainConfiguration: Bool) {
    finishStart(
      .failure(NearbyHostError("Nearby hosting was stopped before it became ready."))
    )
    listener?.stateUpdateHandler = nil
    listener?.newConnectionHandler = nil
    listener?.cancel()
    listener = nil
    heartbeatTimer?.setEventHandler {}
    heartbeatTimer?.cancel()
    heartbeatTimer = nil
    for client in Array(clients.values) {
      remove(client)
    }
    pendingStart = nil
    setIdleTimerDisabled(false)
    if !retainConfiguration {
      configuration = nil
      preferredPort = nil
      latestHostEnvelope = nil
      blockedDeviceTokens.removeAll()
      roleOverridesByDeviceToken.removeAll()
      isSuspended = false
      isRestartingAfterForeground = false
    }
  }

  // MARK: - HTTP and WebSocket

  private func accept(_ connection: NWConnection) {
    guard
      configuration != nil,
      !isSuspended,
      Self.hasAvailableClientCapacity(
        clientCount: clients.count,
        maximumClients: Self.maximumClients
      )
    else {
      connection.cancel()
      return
    }

    let client = Client(connection: connection)
    clients[client.id] = client
    connection.stateUpdateHandler = { [weak self, weak client] state in
      guard let self = self, let client = client else { return }
      switch state {
      case .ready:
        self.receive(from: client)
      case .failed, .cancelled:
        self.remove(client)
      default:
        break
      }
    }
    connection.start(queue: queue)
  }

  private func receive(from client: Client) {
    client.connection.receive(
      minimumIncompleteLength: 1,
      maximumLength: 64 * 1024
    ) { [weak self, weak client] content, _, isComplete, error in
      guard let self = self, let client = client else { return }
      if let content = content, !content.isEmpty {
        client.buffer.append(content)
        switch client.phase {
        case .http:
          self.processHTTPRequest(from: client)
        case .websocket:
          self.processFrames(from: client)
        }
      }
      if error != nil || isComplete {
        self.remove(client)
        return
      }
      if self.clients[client.id] != nil {
        self.receive(from: client)
      }
    }
  }

  private func processHTTPRequest(from client: Client) {
    if client.buffer.count > Self.maximumHeaderBytes {
      sendHTTP(
        status: "431 Request Header Fields Too Large",
        contentType: "text/plain; charset=utf-8",
        body: Data("Request headers are too large.".utf8),
        to: client
      )
      return
    }

    let separator = Data([13, 10, 13, 10])
    guard let headerRange = client.buffer.range(of: separator) else { return }
    let headerData = client.buffer.subdata(in: 0..<headerRange.lowerBound)
    client.buffer.removeSubrange(0..<headerRange.upperBound)
    guard
      let headerText = String(data: headerData, encoding: .utf8),
      let request = parseHTTPRequest(headerText)
    else {
      sendHTTP(
        status: "400 Bad Request",
        contentType: "text/plain; charset=utf-8",
        body: Data("Malformed request.".utf8),
        to: client
      )
      return
    }

    guard request.method == "GET" else {
      sendHTTP(
        status: "405 Method Not Allowed",
        contentType: "text/plain; charset=utf-8",
        body: Data("Only GET is supported.".utf8),
        extraHeaders: ["Allow": "GET"],
        to: client
      )
      return
    }

    let path = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
    switch path {
    case "/", "/index.html":
      let packagedClientAvailable =
        Self.packagedNearbyClientIndex != nil && Self.packagedNearbyClientScript != nil
      sendHTTP(
        status: "200 OK",
        contentType: "text/html; charset=utf-8",
        body: Self.packagedNearbyClientIndex ?? Data(Self.joinPage.utf8),
        extraHeaders: [
          "Cache-Control": "no-store",
          "Content-Security-Policy":
            packagedClientAvailable
            ? "default-src 'none'; style-src 'unsafe-inline'; script-src 'self'; connect-src ws: wss:; img-src 'self'; base-uri 'none'; frame-ancestors 'none'"
            : "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src ws: wss:; img-src 'self'; base-uri 'none'; frame-ancestors 'none'",
          "Referrer-Policy": "no-referrer",
          "X-Content-Type-Options": "nosniff",
        ],
        to: client
      )
    case "/client.js":
      guard let script = Self.packagedNearbyClientScript else {
        sendHTTP(
          status: "404 Not Found",
          contentType: "text/plain; charset=utf-8",
          body: Data("Nearby client asset is unavailable.".utf8),
          to: client
        )
        return
      }
      sendHTTP(
        status: "200 OK",
        contentType: "application/javascript; charset=utf-8",
        body: script,
        extraHeaders: [
          "Cache-Control": "no-store",
          "Referrer-Policy": "no-referrer",
          "X-Content-Type-Options": "nosniff",
        ],
        to: client
      )
    case "/health":
      sendHTTP(
        status: "200 OK",
        contentType: "application/json",
        body: Data(#"{"status":"ready","protocolVersion":1}"#.utf8),
        extraHeaders: ["Cache-Control": "no-store"],
        to: client
      )
    case "/ws":
      upgradeToWebSocket(request: request, client: client)
    default:
      sendHTTP(
        status: "404 Not Found",
        contentType: "text/plain; charset=utf-8",
        body: Data("Not found.".utf8),
        to: client
      )
    }
  }

  private func upgradeToWebSocket(request: HTTPRequest, client: Client) {
    guard
      request.headers["upgrade"]?.lowercased() == "websocket",
      request.headers["connection"]?.lowercased().contains("upgrade") == true,
      request.headers["sec-websocket-version"] == "13",
      let key = nonemptyString(request.headers["sec-websocket-key"]),
      Data(base64Encoded: key)?.count == 16
    else {
      sendHTTP(
        status: "400 Bad Request",
        contentType: "text/plain; charset=utf-8",
        body: Data("Invalid WebSocket handshake.".utf8),
        to: client
      )
      return
    }
    guard
      let configuration = configuration,
      configuration.expiresAt > Date()
    else {
      roleOverridesByDeviceToken.removeAll()
      sendHTTP(
        status: "403 Forbidden",
        contentType: "text/plain; charset=utf-8",
        body: Data("This invitation has expired.".utf8),
        to: client
      )
      return
    }

    let protocols =
      request.headers["sec-websocket-protocol"]?
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? []
    guard protocols.contains(Self.protocolName) else {
      sendHTTP(
        status: "426 Upgrade Required",
        contentType: "text/plain; charset=utf-8",
        body: Data("ChronoSync protocol v1 is required.".utf8),
        extraHeaders: ["Sec-WebSocket-Version": "13"],
        to: client
      )
      return
    }

    let role =
      protocols
      .first { $0.hasPrefix("role.") }
      .map { String($0.dropFirst("role.".count)) }
    let capability =
      protocols
      .first { $0.hasPrefix("cap.") }
      .map { String($0.dropFirst("cap.".count)) }
    let deviceToken = Self.deviceToken(from: protocols)
    let expectedCapability: String?
    switch role {
    case "participant":
      expectedCapability = configuration.participantCapability
    case "display":
      expectedCapability = configuration.displayCapability
    default:
      expectedCapability = nil
    }
    guard
      let authorizedRole = role,
      let providedCapability = capability,
      let expectedCapability = expectedCapability,
      let authorizedDeviceToken = deviceToken,
      constantTimeEqual(providedCapability, expectedCapability)
    else {
      sendHTTP(
        status: "403 Forbidden",
        contentType: "text/plain; charset=utf-8",
        body: Data("The invitation capability is invalid.".utf8),
        to: client
      )
      return
    }

    let accept = Self.websocketAccept(for: key)
    let response = [
      "HTTP/1.1 101 Switching Protocols",
      "Upgrade: websocket",
      "Connection: Upgrade",
      "Sec-WebSocket-Accept: \(accept)",
      "Sec-WebSocket-Protocol: \(Self.protocolName)",
      "",
      "",
    ].joined(separator: "\r\n")

    client.deviceToken = authorizedDeviceToken
    client.connection.send(
      content: Data(response.utf8),
      completion: .contentProcessed { [weak self, weak client] error in
        guard let self = self, let client = client else { return }
        if error != nil {
          self.remove(client)
          return
        }
        guard !client.isClosing else { return }
        if self.blockedDeviceTokens.contains(authorizedDeviceToken) {
          self.close(client, code: 4003)
          return
        }
        let effectiveRole = Self.effectivePeerRole(
          requestedRole: authorizedRole,
          deviceToken: authorizedDeviceToken,
          overrides: self.roleOverridesByDeviceToken
        )
        client.phase = .websocket
        client.role = effectiveRole
        self.emit([
          "type": "client_connected",
          "clientId": client.id.uuidString,
          "role": effectiveRole,
          "deviceToken": authorizedDeviceToken,
        ])
        if let envelope = self.latestHostEnvelope {
          self.sendText(envelope, to: client)
        }
        if !client.buffer.isEmpty {
          self.processFrames(from: client)
        }
      }
    )
  }

  private func processFrames(from client: Client) {
    while true {
      let bytes = [UInt8](client.buffer)
      guard bytes.count >= 2 else { return }
      let first = bytes[0]
      let second = bytes[1]
      let isFinal = (first & 0x80) != 0
      let reservedBits = first & 0x70
      let opcode = first & 0x0f
      let isMasked = (second & 0x80) != 0
      var payloadLength = UInt64(second & 0x7f)
      var cursor = 2

      guard reservedBits == 0, isMasked else {
        close(client, code: 1002)
        return
      }
      if payloadLength == 126 {
        guard bytes.count >= cursor + 2 else { return }
        payloadLength = UInt64(bytes[cursor]) << 8 | UInt64(bytes[cursor + 1])
        cursor += 2
      } else if payloadLength == 127 {
        guard bytes.count >= cursor + 8 else { return }
        payloadLength = 0
        for index in cursor..<(cursor + 8) {
          payloadLength = (payloadLength << 8) | UInt64(bytes[index])
        }
        cursor += 8
      }
      guard payloadLength <= UInt64(Self.maximumWebSocketMessageBytes) else {
        close(client, code: 1009)
        return
      }
      guard bytes.count >= cursor + 4 else { return }
      let mask = Array(bytes[cursor..<(cursor + 4)])
      cursor += 4
      guard payloadLength <= UInt64(Int.max) else {
        close(client, code: 1009)
        return
      }
      let payloadCount = Int(payloadLength)
      guard bytes.count >= cursor + payloadCount else { return }
      var payload = Data(capacity: payloadCount)
      for index in 0..<payloadCount {
        payload.append(bytes[cursor + index] ^ mask[index % 4])
      }
      client.buffer.removeSubrange(0..<(cursor + payloadCount))

      if opcode >= 0x8 && (!isFinal || payloadCount > 125) {
        close(client, code: 1002)
        return
      }
      switch opcode {
      case 0x0:
        guard client.fragmentedOpcode != nil else {
          close(client, code: 1002)
          return
        }
        client.fragmentedPayload.append(payload)
        guard Self.webSocketMessageSizeAllowed(
          client.fragmentedPayload.count
        ) else {
          close(client, code: 1009)
          return
        }
        if isFinal {
          let messageOpcode = client.fragmentedOpcode
          let message = client.fragmentedPayload
          client.fragmentedOpcode = nil
          client.fragmentedPayload = Data()
          handleMessage(opcode: messageOpcode ?? 0, payload: message, client: client)
        }
      case 0x1:
        guard client.fragmentedOpcode == nil else {
          close(client, code: 1002)
          return
        }
        if isFinal {
          handleMessage(opcode: opcode, payload: payload, client: client)
        } else {
          client.fragmentedOpcode = opcode
          client.fragmentedPayload = payload
        }
      case 0x2:
        close(client, code: 1003)
        return
      case 0x8:
        close(client, code: 1000)
        return
      case 0x9:
        sendFrame(opcode: 0xA, payload: payload, to: client)
      case 0xA:
        break
      default:
        close(client, code: 1002)
        return
      }
    }
  }

  private func handleMessage(opcode: UInt8, payload: Data, client: Client) {
    guard !client.isClosing else { return }
    guard
      opcode == 0x1,
      let message = String(data: payload, encoding: .utf8)
    else {
      close(client, code: 1007)
      return
    }
    if Self.isHeartbeatPing(message) {
      client.lastHeartbeatAt = Date()
      sendText(#"{"type":"pong"}"#, to: client)
      return
    }
    guard
      Self.clientCanSendEnvelopeKind(
        envelopeKind(message),
        role: client.role
      )
    else {
      close(client, code: 1008)
      return
    }
    guard
      let configuration = configuration,
      validEnvelope(message, sessionID: configuration.sessionID)
    else {
      close(client, code: 1007)
      return
    }
    emit([
      "type": "message",
      "envelope": message,
      "clientId": client.id.uuidString,
      "role": client.role ?? "participant",
      "deviceToken": client.deviceToken ?? "",
    ])
  }

  private func sendText(_ value: String, to client: Client) {
    sendFrame(opcode: 0x1, payload: Data(value.utf8), to: client)
  }

  private func sendFrame(
    opcode: UInt8,
    payload: Data,
    to client: Client,
    removeAfterSend: Bool = false
  ) {
    guard Self.webSocketMessageSizeAllowed(payload.count) else { return }
    var frame = Data([0x80 | opcode])
    if payload.count < 126 {
      frame.append(UInt8(payload.count))
    } else if payload.count <= Int(UInt16.max) {
      frame.append(126)
      frame.append(UInt8((payload.count >> 8) & 0xff))
      frame.append(UInt8(payload.count & 0xff))
    } else {
      frame.append(127)
      let count = UInt64(payload.count)
      for shift in stride(from: 56, through: 0, by: -8) {
        frame.append(UInt8((count >> UInt64(shift)) & 0xff))
      }
    }
    frame.append(payload)
    client.connection.send(
      content: frame,
      completion: .contentProcessed { [weak self, weak client] error in
        if (error != nil || removeAfterSend), let client = client {
          self?.remove(client)
        }
      }
    )
  }

  private func close(_ client: Client, code: UInt16) {
    guard !client.isClosing else { return }
    client.isClosing = true
    let payload = Data([UInt8(code >> 8), UInt8(code & 0xff)])
    sendFrame(
      opcode: 0x8,
      payload: payload,
      to: client,
      removeAfterSend: true
    )
  }

  private func remove(_ client: Client) {
    guard clients.removeValue(forKey: client.id) != nil else { return }
    client.connection.stateUpdateHandler = nil
    client.connection.cancel()
    if let event = Self.clientDisconnectedEvent(
      clientID: client.id,
      role: client.role,
      deviceToken: client.deviceToken
    ) {
      emit(event)
    }
  }

  static func clientDisconnectedEvent(
    clientID: UUID,
    role: String?,
    deviceToken: String?
  ) -> [String: Any]? {
    guard
      let role = role,
      role == "participant" || role == "controller" || role == "display",
      let deviceToken = deviceToken,
      validDeviceToken(deviceToken)
    else {
      return nil
    }
    return [
      "type": "client_disconnected",
      "clientId": clientID.uuidString,
      "role": role,
      "deviceToken": deviceToken,
    ]
  }

  private func startHeartbeatMonitor() {
    heartbeatTimer?.setEventHandler {}
    heartbeatTimer?.cancel()

    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(
      deadline: .now() + Self.heartbeatSweepInterval,
      repeating: Self.heartbeatSweepInterval
    )
    timer.setEventHandler { [weak self] in
      guard let self = self else { return }
      let now = Date()
      let handshakeSweep = Self.httpHandshakeSweep(
        clients: self.clients.values.map {
          HTTPHandshakeSweepClient(
            id: $0.id,
            acceptedAt: $0.acceptedAt,
            isAwaitingHandshake: $0.phase == .http,
            isClosing: $0.isClosing
          )
        },
        now: now,
        maximumClients: Self.maximumClients
      )
      for clientID in handshakeSweep.expiredClientIDs {
        if let client = self.clients[clientID] {
          self.remove(client)
        }
      }
      let silentClients = self.clients.values.filter {
        $0.phase == .websocket
          && !$0.isClosing
          && Self.heartbeatExpired(lastSeen: $0.lastHeartbeatAt, now: now)
      }
      for client in silentClients {
        self.close(client, code: 4000)
      }
    }
    heartbeatTimer = timer
    timer.resume()
  }

  static func isHeartbeatPing(_ message: String) -> Bool {
    guard
      let data = message.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any]
    else {
      return false
    }
    return dictionary["type"] as? String == "ping"
  }

  static func heartbeatExpired(lastSeen: Date, now: Date) -> Bool {
    now.timeIntervalSince(lastSeen) > heartbeatTimeout
  }

  static func httpHandshakeExpired(acceptedAt: Date, now: Date) -> Bool {
    now.timeIntervalSince(acceptedAt) > httpHandshakeTimeout
  }

  static func httpHandshakeSweep(
    clients: [HTTPHandshakeSweepClient],
    now: Date,
    maximumClients: Int
  ) -> HTTPHandshakeSweepResult {
    let expiredClientIDs = clients.compactMap { client -> UUID? in
      guard
        client.isAwaitingHandshake,
        !client.isClosing,
        httpHandshakeExpired(acceptedAt: client.acceptedAt, now: now)
      else {
        return nil
      }
      return client.id
    }
    let retainedClientCount = clients.count - expiredClientIDs.count
    return HTTPHandshakeSweepResult(
      expiredClientIDs: expiredClientIDs,
      retainedClientCount: retainedClientCount,
      hasAvailableCapacity: hasAvailableClientCapacity(
        clientCount: retainedClientCount,
        maximumClients: maximumClients
      )
    )
  }

  static func hasAvailableClientCapacity(
    clientCount: Int,
    maximumClients: Int
  ) -> Bool {
    clientCount < maximumClients
  }

  static func admittedDeviceToken(
    from protocols: [String],
    blockedTokens: Set<String>
  ) -> String? {
    guard
      let token = deviceToken(from: protocols),
      !blockedTokens.contains(token)
    else {
      return nil
    }
    return token
  }

  private static func deviceToken(from protocols: [String]) -> String? {
    guard
      let protocolValue = protocols.first(where: { $0.hasPrefix("device.") })
    else {
      return nil
    }
    let token = String(protocolValue.dropFirst("device.".count))
    guard validDeviceToken(token) else { return nil }
    return token
  }

  private static func validDeviceToken(_ token: String) -> Bool {
    guard token.utf8.count == 43 else { return false }
    let allowed = CharacterSet(
      charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
    )
    guard token.unicodeScalars.allSatisfy(allowed.contains) else {
      return false
    }
    return true
  }

  private func sendHTTP(
    status: String,
    contentType: String,
    body: Data,
    extraHeaders: [String: String] = [:],
    to client: Client
  ) {
    var lines = [
      "HTTP/1.1 \(status)",
      "Content-Type: \(contentType)",
      "Content-Length: \(body.count)",
      "Connection: close",
    ]
    lines.append(contentsOf: extraHeaders.map { "\($0.key): \($0.value)" })
    lines.append("")
    lines.append("")
    var response = Data(lines.joined(separator: "\r\n").utf8)
    response.append(body)
    client.connection.send(
      content: response,
      completion: .contentProcessed { [weak self, weak client] _ in
        guard let self = self, let client = client else { return }
        self.remove(client)
      }
    )
  }

  // MARK: - Validation and utilities

  private static let packagedNearbyClientScript = bundledFlutterAsset(
    "assets/nearby_client/client.js"
  )

  private static let packagedNearbyClientIndex: Data? = {
    guard packagedNearbyClientScript != nil else { return nil }
    return bundledFlutterAsset("assets/nearby_client/index.html")
  }()

  private static func bundledFlutterAsset(_ asset: String) -> Data? {
    let key = FlutterDartProject.lookupKey(forAsset: asset)
    if let path = Bundle.main.path(forResource: key, ofType: nil),
      let data = FileManager.default.contents(atPath: path)
    {
      return data
    }

    let appFramework = Bundle.main.bundleURL
      .appendingPathComponent("Frameworks", isDirectory: true)
      .appendingPathComponent("App.framework", isDirectory: true)
    for root in [Bundle.main.bundleURL, appFramework] {
      let url = root.appendingPathComponent(key, isDirectory: false)
      if FileManager.default.fileExists(atPath: url.path),
        let data = try? Data(contentsOf: url, options: .mappedIfSafe)
      {
        return data
      }
    }
    return nil
  }

  private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
  }

  private func parseHTTPRequest(_ text: String) -> HTTPRequest? {
    let lines = text.components(separatedBy: "\r\n")
    guard !lines.isEmpty else { return nil }
    let requestLine = lines[0].split(separator: " ", omittingEmptySubsequences: true)
    guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else {
      return nil
    }
    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      guard let colon = line.firstIndex(of: ":") else { return nil }
      let name = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
      let value = line[line.index(after: colon)...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else { return nil }
      headers[name] = value
    }
    return HTTPRequest(
      method: String(requestLine[0]),
      path: String(requestLine[1]),
      headers: headers
    )
  }

  private func validEnvelope(_ encoded: String, sessionID: String) -> Bool {
    guard
      Self.webSocketMessageSizeAllowed(encoded.utf8.count),
      let data = encoded.data(using: .utf8),
      let value = try? JSONSerialization.jsonObject(with: data),
      let object = value as? [String: Any],
      (object["protocolVersion"] as? NSNumber)?.intValue == 1,
      nonemptyString(object["sessionId"]) == sessionID,
      nonemptyString(object["messageId"]) != nil,
      nonemptyString(object["senderDeviceId"]) != nil,
      let revision = object["baseRevision"] as? NSNumber,
      revision.intValue >= 0,
      nonemptyString(object["sentAt"]) != nil,
      let kind = nonemptyString(object["kind"]),
      ["join", "command", "activity", "snapshot", "heartbeat", "error"].contains(kind),
      nonemptyString(object["encryptedPayload"]) != nil
    else {
      return false
    }
    return true
  }

  private func envelopeKind(_ encoded: String) -> String? {
    guard
      let data = encoded.data(using: .utf8),
      let value = try? JSONSerialization.jsonObject(with: data),
      let object = value as? [String: Any]
    else {
      return nil
    }
    return object["kind"] as? String
  }

  static func websocketAccept(for key: String) -> String {
    let source = Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8)
    return Data(Insecure.SHA1.hash(data: source)).base64EncodedString()
  }

  static func webSocketMessageSizeAllowed(_ byteCount: Int) -> Bool {
    byteCount >= 0 && byteCount <= maximumWebSocketMessageBytes
  }

  static func roleCanSendCommands(_ role: String?) -> Bool {
    role == "participant" || role == "controller"
  }

  static func hostCanBroadcastEnvelopeKind(_ kind: String?) -> Bool {
    kind == "snapshot"
  }

  static func clientCanSendEnvelopeKind(
    _ kind: String?,
    role: String?
  ) -> Bool {
    roleCanSendCommands(role) && kind == "command"
  }

  static func fallbackJoinPageScrubsFragment() -> Bool {
    guard
      let capture = joinPage.range(
        of: "const fragment = location.hash.slice(1);"
      ),
      let scrub = joinPage.range(
        of: "history.replaceState(null, '', `${location.pathname}${location.search}`);"
      ),
      let parse = joinPage.range(
        of: "const params = new URLSearchParams(fragment);"
      )
    else {
      return false
    }
    return capture.lowerBound < scrub.lowerBound
      && scrub.lowerBound < parse.lowerBound
  }

  static func fallbackJoinPageUsesNeutralAudienceLanguage() -> Bool {
    joinPage.contains("<h1>Join the live sequence.</h1>")
      && joinPage.contains("Connect when everyone is ready.")
  }

  static func fallbackJoinPageUsesAdaptiveDarkDecoPalette() -> Bool {
    let requiredTokens = [
      #"name="color-scheme" content="light dark""#,
      "--canvas: #F4F5FA;",
      "--surface: #FFFFFF;",
      "--text-primary: #11131C;",
      "--text-secondary: #4B526D;",
      "--primary: #1E3A8A;",
      "@media (prefers-color-scheme: dark)",
      "--canvas: #050608;",
      "--surface: #0B0C0E;",
      "--surface-muted: #1A1D24;",
      "--text-primary: #E8E8E8;",
      "--text-secondary: #BABED8;",
      "--primary: #666AF5;",
      "--primary-pressed: #7A7DFF;",
      "--warning: #FFCB6B;",
    ]
    return requiredTokens.allSatisfy { joinPage.contains($0) }
  }

  private func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
    let left = [UInt8](lhs.utf8)
    let right = [UInt8](rhs.utf8)
    guard left.count == right.count else { return false }
    var difference: UInt8 = 0
    for index in left.indices {
      difference |= left[index] ^ right[index]
    }
    return difference == 0
  }

  private func localIPv4Address() -> String? {
    var pointer: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
    defer { freeifaddrs(pointer) }

    var preferredAddress: String?
    var fallbackAddress: String?
    var current: UnsafeMutablePointer<ifaddrs>? = first
    while let interface = current {
      defer { current = interface.pointee.ifa_next }
      guard let socketAddress = interface.pointee.ifa_addr else { continue }
      guard socketAddress.pointee.sa_family == UInt8(AF_INET) else { continue }
      let flags = Int32(interface.pointee.ifa_flags)
      guard
        (flags & IFF_UP) != 0,
        (flags & IFF_RUNNING) != 0,
        (flags & IFF_LOOPBACK) == 0
      else {
        continue
      }

      let name = String(cString: interface.pointee.ifa_name)
      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      let length = socklen_t(socketAddress.pointee.sa_len)
      guard
        getnameinfo(
          socketAddress,
          length,
          &host,
          socklen_t(host.count),
          nil,
          0,
          NI_NUMERICHOST
        ) == 0
      else {
        continue
      }
      let address = String(cString: host)
      if name == "en0" {
        preferredAddress = address
        break
      }
      if name.hasPrefix("en") || name.hasPrefix("bridge") {
        fallbackAddress = fallbackAddress ?? address
      }
    }
    return preferredAddress ?? fallbackAddress
  }

  private func parseDate(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) {
      return date
    }
    return ISO8601DateFormatter().date(from: value)
  }

  private func normalizedCapability(_ value: String) -> String {
    value.trimmingCharacters(in: CharacterSet(charactersIn: "="))
  }

  private func nonemptyString(_ value: Any?) -> String? {
    guard let value = value as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func setIdleTimerDisabled(_ disabled: Bool) {
    DispatchQueue.main.async {
      UIApplication.shared.isIdleTimerDisabled = disabled
    }
  }

  private func emit(_ event: [String: Any]) {
    guard let sink = eventSink else { return }
    DispatchQueue.main.async {
      sink(event)
    }
  }

  private func complete(_ result: @escaping FlutterResult, with value: Any?) {
    DispatchQueue.main.async {
      result(value)
    }
  }

  private func finishStart(_ outcome: Result<[String: Any], Error>) {
    guard let completion = pendingStart else { return }
    pendingStart = nil
    DispatchQueue.main.async {
      completion(outcome)
    }
  }

  // Keep a minimal inline page as a safe fallback if Flutter assets are absent
  // from a malformed development build.
  private static let joinPage = #"""
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
      <meta name="theme-color" content="#F4F5FA" media="(prefers-color-scheme: light)">
      <meta name="theme-color" content="#050608" media="(prefers-color-scheme: dark)">
      <meta name="color-scheme" content="light dark">
      <title>Join ChronoSync</title>
      <style>
        :root {
          color-scheme: light dark;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          --canvas: #F4F5FA;
          --surface: #FFFFFF;
          --surface-muted: #E8EAF2;
          --text-primary: #11131C;
          --text-secondary: #4B526D;
          --outline: #7D849E;
          --primary: #1E3A8A;
          --primary-pressed: #152A67;
          --on-primary: #FFFFFF;
          --success: #4A5D23;
          --warning: #765300;
          --danger: #842331;
          --glow: rgba(255, 203, 107, .22);
          --shadow: rgba(17, 19, 28, .20);
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --canvas: #050608;
            --surface: #0B0C0E;
            --surface-muted: #1A1D24;
            --text-primary: #E8E8E8;
            --text-secondary: #BABED8;
            --outline: #5A6077;
            --primary: #666AF5;
            --primary-pressed: #7A7DFF;
            --on-primary: #050608;
            --success: #9FB36B;
            --warning: #FFCB6B;
            --danger: #FF9CAC;
            --glow: rgba(102, 106, 245, .20);
            --shadow: rgba(0, 0, 0, .64);
          }
        }
        * { box-sizing: border-box; }
        body { margin: 0; min-height: 100vh; background: radial-gradient(circle at 88% 4%, var(--glow), transparent 24rem), var(--canvas); color: var(--text-primary); display: grid; place-items: center; padding: 24px; }
        main { width: min(100%, 480px); background: var(--surface); border: 1px solid var(--outline); border-radius: 24px; padding: 28px; box-shadow: 0 18px 50px var(--shadow); }
        .mark { width: 48px; height: 48px; border-radius: 16px; background: var(--primary); color: var(--on-primary); display: grid; place-items: center; font-size: 24px; }
        h1 { margin: 20px 0 8px; font-size: 30px; letter-spacing: -.5px; }
        p { line-height: 1.5; color: var(--text-secondary); }
        .status { margin: 24px 0; border: 1px solid var(--outline); border-radius: 16px; padding: 18px; background: var(--surface-muted); }
        .row { display: flex; align-items: center; gap: 10px; }
        .dot { width: 10px; height: 10px; border-radius: 50%; background: var(--warning); }
        .dot.live { background: var(--success); }
        .dot.error { background: var(--danger); }
        button { border: 0; border-radius: 14px; min-height: 50px; width: 100%; padding: 0 20px; background: var(--primary); color: var(--on-primary); font: inherit; font-weight: 700; cursor: pointer; }
        button:active:not(:disabled) { background: var(--primary-pressed); }
        button:focus-visible { outline: 3px solid var(--primary); outline-offset: 3px; }
        button:disabled { opacity: .5; cursor: default; }
        small { display: block; margin-top: 18px; color: var(--text-secondary); line-height: 1.45; }
      </style>
    </head>
    <body>
      <main>
        <div class="mark" aria-hidden="true">◷</div>
        <h1>Join the live sequence.</h1>
        <p id="intro">Stay on the same Wi-Fi network as the host iPhone.</p>
        <div class="status" aria-live="polite">
          <div class="row"><span class="dot" id="dot"></span><strong id="status">Invitation ready</strong></div>
          <p id="detail">Connect when everyone is ready.</p>
        </div>
        <button id="connect">Connect</button>
        <small>Your invite secret stays in this browser and is not included in the web request. Keep this page open to remain connected.</small>
      </main>
      <script>
        (() => {
          const status = document.querySelector('#status');
          const detail = document.querySelector('#detail');
          const dot = document.querySelector('#dot');
          const button = document.querySelector('#connect');
          let invite;

          const show = (title, message, state = '') => {
            status.textContent = title;
            detail.textContent = message;
            dot.className = `dot ${state}`;
          };
          const decode = value => {
            const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
            const padded = normalized + '='.repeat((4 - normalized.length % 4) % 4);
            return JSON.parse(new TextDecoder().decode(
              Uint8Array.from(atob(padded), character => character.charCodeAt(0))
            ));
          };
          const randomToken = () => {
            const bytes = crypto.getRandomValues(new Uint8Array(32));
            return btoa(String.fromCharCode(...bytes))
              .replace(/\+/g, '-')
              .replace(/\//g, '_')
              .replace(/=+$/, '');
          };

          try {
            const fragment = location.hash.slice(1);
            history.replaceState(null, '', `${location.pathname}${location.search}`);
            const params = new URLSearchParams(fragment);
            const encoded = params.get('invite');
            if (!encoded) throw new Error('This link has no invitation.');
            invite = decode(encoded);
            if (invite.protocolVersion !== 1) throw new Error('This invitation needs a newer ChronoSync version.');
            if (!['participant', 'display'].includes(invite.requestedRole)) throw new Error('This invitation role is not supported.');
            if (Date.parse(invite.expiresAt) <= Date.now()) throw new Error('This invitation has expired.');
            document.querySelector('#intro').textContent =
              `Join as ${invite.requestedRole === 'display' ? 'a display' : 'a participant'} on the host’s nearby network.`;
          } catch (error) {
            show('Can’t use this invitation', error.message, 'error');
            button.disabled = true;
          }

          button.addEventListener('click', () => {
            button.disabled = true;
            show('Connecting…', 'Looking for the host iPhone.');
            const tokenKey = `chronosync.nearby.device_token.${invite.sessionId}`;
            let deviceToken = localStorage.getItem(tokenKey);
            if (!deviceToken) {
              deviceToken = randomToken();
              localStorage.setItem(tokenKey, deviceToken);
            }
            const scheme = location.protocol === 'https:' ? 'wss:' : 'ws:';
            const socket = new WebSocket(
              `${scheme}//${location.host}/ws`,
              [
                'chronosync.v1',
                `role.${invite.requestedRole}`,
                `cap.${invite.capability.replace(/=+$/, '')}`,
                `device.${deviceToken}`,
              ]
            );
            socket.addEventListener('open', () => {
              show('Connected', 'Live updates will arrive from the host.', 'live');
            });
            socket.addEventListener('message', event => {
              try {
                const envelope = JSON.parse(event.data);
                const label = envelope.kind === 'snapshot' ? 'Live session synchronized' : 'Live update received';
                show(label, 'You are connected to the host iPhone.', 'live');
              } catch (_) {
                show('Connected', 'A live update was received.', 'live');
              }
            });
            socket.addEventListener('close', event => {
              if (event.code === 4003) {
                show('Removed from this session', 'Ask the host for help if this was unexpected.', 'error');
                button.disabled = true;
                button.textContent = 'Removed';
                return;
              }
              show('Connection paused', 'Keep this page open and reconnect when the host returns.', 'error');
              button.disabled = false;
              button.textContent = 'Reconnect';
            });
            socket.addEventListener('error', () => {
              show('Can’t reach the host', 'Check that both devices are on the same Wi-Fi network.', 'error');
            });
          });
        })();
      </script>
    </body>
    </html>
    """#
}

private struct NearbyHostError: LocalizedError {
  init(_ description: String) {
    self.description = description
  }

  let description: String
  var errorDescription: String? { description }
}
