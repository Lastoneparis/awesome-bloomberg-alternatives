import Foundation
import Network
import CriticalStrikeCore

/// Local multiplayer over Wi-Fi.
///
/// Uses Network.framework with Bonjour discovery so a group of players on the same network
/// can play with no server, no account and no internet — which is the single most reliable
/// way to get a good match on a school or office network. The host runs the authoritative
/// simulation exactly as a dedicated server would; the only difference is the transport.
final class LANTransport: NetTransport {
    static let serviceType = "_criticalstrike._udp"

    var isConnected: Bool { listener != nil || !connections.isEmpty }
    var onData: ((PeerID, Data) -> Void)?
    var onPeerConnected: ((PeerID) -> Void)?
    var onPeerDisconnected: ((PeerID) -> Void)?
    var onBrowseResults: (([NWBrowser.Result]) -> Void)?

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connections: [PeerID: NWConnection] = [:]
    private var nextPeerRaw: UInt32 = 1
    private let queue = DispatchQueue(label: "game.criticalstrike.lan", qos: .userInteractive)

    // MARK: - Hosting

    func host(name: String) throws {
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true
        // Small MTU keeps snapshots inside a single datagram on typical Wi-Fi.
        if let options = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            options.version = .any
        }

        let listener = try NWListener(using: parameters)
        listener.service = NWListener.Service(name: name, type: LANTransport.serviceType)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { state in
            Log.info("LAN listener: \(state)", category: "net")
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func accept(_ connection: NWConnection) {
        let peer = PeerID(nextPeerRaw)
        nextPeerRaw += 1
        connections[peer] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onPeerConnected?(peer)
            case .failed, .cancelled:
                self?.connections[peer] = nil
                self?.onPeerDisconnected?(peer)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: connection, peer: peer)
    }

    // MARK: - Joining

    func browse() {
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: LANTransport.serviceType, domain: nil),
                                using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.onBrowseResults?(Array(results))
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func join(_ result: NWBrowser.Result) {
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: result.endpoint, using: parameters)
        let peer = PeerID.host
        connections[peer] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onPeerConnected?(peer)
            case .failed, .cancelled:
                self?.connections[peer] = nil
                self?.onPeerDisconnected?(peer)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: connection, peer: peer)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }

    // MARK: - NetTransport

    func send(_ data: Data, to peer: PeerID, reliable: Bool) {
        guard let connection = connections[peer] else { return }
        // UDP with no retransmission: a lost snapshot is simply superseded by the next one,
        // which is exactly what a 20Hz snapshot stream wants.
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                Log.warn("LAN send failed: \(error)", category: "net")
            }
        })
    }

    func broadcast(_ data: Data, reliable: Bool) {
        for peer in connections.keys { send(data, to: peer, reliable: reliable) }
    }

    func disconnect(_ peer: PeerID) {
        connections[peer]?.cancel()
        connections[peer] = nil
    }

    func shutdown() {
        listener?.cancel()
        listener = nil
        stopBrowsing()
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
    }

    private func receive(on connection: NWConnection, peer: PeerID) {
        connection.receiveMessage { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                self?.onData?(peer, data)
            }
            if error == nil && !isComplete {
                self?.receive(on: connection, peer: peer)
            } else if error == nil {
                self?.receive(on: connection, peer: peer)
            } else {
                self?.connections[peer] = nil
                self?.onPeerDisconnected?(peer)
            }
        }
    }
}
