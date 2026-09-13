import Foundation

/// Opaque handle for one connected peer. The transport layer decides what it means
/// (a WebSocket task, an NWConnection, or a loopback slot in a local match).
public struct PeerID: Hashable, Sendable {
    public let raw: UInt32
    public init(_ raw: UInt32) { self.raw = raw }
    public static let host = PeerID(0)
}

/// Everything the core needs from a network transport. Implementations live in the app
/// layer (URLSessionWebSocketTask for online play, Network.framework for LAN, and a
/// zero-latency loopback for bot matches) so the core stays platform-free.
public protocol NetTransport: AnyObject {
    var isConnected: Bool { get }
    func send(_ data: Data, to peer: PeerID, reliable: Bool)
    func broadcast(_ data: Data, reliable: Bool)
    func disconnect(_ peer: PeerID)
    var onData: ((PeerID, Data) -> Void)? { get set }
    var onPeerConnected: ((PeerID) -> Void)? { get set }
    var onPeerDisconnected: ((PeerID) -> Void)? { get set }
}

/// In-process transport used by offline bot matches and by the unit tests. It can be
/// given an artificial latency and packet-loss rate, which is how the netcode gets tested
/// without a network.
public final class LoopbackTransport: NetTransport {
    public var isConnected: Bool = true
    public var onData: ((PeerID, Data) -> Void)?
    public var onPeerConnected: ((PeerID) -> Void)?
    public var onPeerDisconnected: ((PeerID) -> Void)?

    /// Simulated one-way latency in seconds.
    public var latency: Float = 0
    /// 0...1 chance a packet is dropped.
    public var packetLoss: Float = 0

    public weak var counterpart: LoopbackTransport?
    private var queue: [(deliverAt: Float, peer: PeerID, data: Data)] = []
    private var clock: Float = 0
    private var rng = DeterministicRandom(seed: 0xA55E_7C0D)

    public init() {}

    public func send(_ data: Data, to peer: PeerID, reliable: Bool) {
        guard let counterpart else { return }
        if !reliable && packetLoss > 0 && rng.chance(packetLoss) { return }
        counterpart.queue.append((clock + latency, peer, data))
    }

    public func broadcast(_ data: Data, reliable: Bool) {
        send(data, to: .host, reliable: reliable)
    }

    public func disconnect(_ peer: PeerID) {
        onPeerDisconnected?(peer)
    }

    /// Pumps queued packets. Call once per frame from whoever owns the transport.
    public func pump(dt: Float) {
        clock += dt
        var remaining: [(deliverAt: Float, peer: PeerID, data: Data)] = []
        for item in queue {
            if item.deliverAt <= clock {
                onData?(item.peer, item.data)
            } else {
                remaining.append(item)
            }
        }
        queue = remaining
    }

    public static func pair() -> (LoopbackTransport, LoopbackTransport) {
        let a = LoopbackTransport()
        let b = LoopbackTransport()
        a.counterpart = b
        b.counterpart = a
        return (a, b)
    }
}
