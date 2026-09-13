import Foundation
import Network
import CriticalStrikeCore

/// Online transport.
///
/// Uses `URLSessionWebSocketTask` because it is the only thing on iOS that reliably gets
/// through carrier NAT and captive portals without a custom relay, and it keeps working
/// when the app is briefly backgrounded. Snapshots are sent as binary frames; the
/// "unreliable" flag is advisory here (WebSocket is ordered and reliable), so the netcode
/// treats every snapshot as a full delta against an acknowledged baseline rather than
/// relying on packet ordering.
final class WebSocketTransport: NSObject, NetTransport {
    var isConnected: Bool { task?.state == .running && handshakeCompleted }
    var onData: ((PeerID, Data) -> Void)?
    var onPeerConnected: ((PeerID) -> Void)?
    var onPeerDisconnected: ((PeerID) -> Void)?

    /// Called when the socket drops so the session can decide whether to reconnect.
    var onDisconnected: ((Error?) -> Void)?

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var handshakeCompleted = false
    private var reconnectAttempt = 0
    private var pingTimer: Foundation.Timer?
    private let endpoint: URL
    private let authToken: String

    init(endpoint: URL, authToken: String) {
        self.endpoint = endpoint
        self.authToken = authToken
        super.init()
    }

    func connect() {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 15
        configuration.networkServiceType = .responsiveData
        // Games are latency-sensitive; let the OS know so it can prioritise the flow.
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue(String(NetHandshake.currentProtocolVersion),
                         forHTTPHeaderField: "X-CS-Protocol")

        task = session?.webSocketTask(with: request)
        task?.maximumMessageSize = 1 << 20
        task?.resume()
        receiveLoop()
        startKeepAlive()
    }

    func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        handshakeCompleted = false
    }

    // MARK: - NetTransport

    func send(_ data: Data, to peer: PeerID, reliable: Bool) {
        guard let task else { return }
        task.send(.data(data)) { [weak self] error in
            guard let error else { return }
            Log.warn("WebSocket send failed: \(error)", category: "net")
            self?.handleFailure(error)
        }
    }

    func broadcast(_ data: Data, reliable: Bool) {
        send(data, to: .host, reliable: reliable)
    }

    func disconnect(_ peer: PeerID) {
        disconnect()
    }

    // MARK: - Receiving

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(message):
                switch message {
                case let .data(data):
                    handshakeCompleted = true
                    onData?(.host, data)
                case let .string(text):
                    // The server only sends text for control messages (errors, notices).
                    Log.info("Server notice: \(text)", category: "net")
                @unknown default:
                    break
                }
                receiveLoop()
            case let .failure(error):
                handleFailure(error)
            }
        }
    }

    private func handleFailure(_ error: Error) {
        guard handshakeCompleted || reconnectAttempt < 3 else {
            onDisconnected?(error)
            return
        }
        handshakeCompleted = false
        onPeerDisconnected?(.host)
        onDisconnected?(error)
    }

    /// WebSocket keep-alive. Carriers will silently drop an idle socket in about 30s.
    private func startKeepAlive() {
        pingTimer?.invalidate()
        pingTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            self?.task?.sendPing { error in
                if let error {
                    Log.warn("Keep-alive ping failed: \(error)", category: "net")
                }
            }
        }
    }

    /// Exponential backoff, capped, with jitter so a server restart does not produce a
    /// thundering herd of reconnects.
    func nextReconnectDelay() -> TimeInterval {
        reconnectAttempt += 1
        let base = min(pow(2, Double(reconnectAttempt)), 30)
        return base + Double.random(in: 0...1)
    }

    func resetReconnect() { reconnectAttempt = 0 }
}

extension WebSocketTransport: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocolName: String?) {
        Log.info("WebSocket connected", category: "net")
        resetReconnect()
        onPeerConnected?(.host)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        Log.info("WebSocket closed: \(closeCode.rawValue)", category: "net")
        handshakeCompleted = false
        onPeerDisconnected?(.host)
        onDisconnected?(nil)
    }
}
