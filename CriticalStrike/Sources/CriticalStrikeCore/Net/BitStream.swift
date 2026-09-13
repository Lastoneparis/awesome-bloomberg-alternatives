import Foundation

/// Bit-level writer. Mobile networks are metered and lossy, so every snapshot is packed
/// by hand: quantized positions, 9-bit angles, and bit flags instead of JSON.
public struct BitWriter {
    public private(set) var bytes: [UInt8] = []
    private var current: UInt8 = 0
    private var bitIndex: Int = 0

    public init(capacity: Int = 512) { bytes.reserveCapacity(capacity) }

    public mutating func writeBit(_ value: Bool) {
        if value { current |= (1 << UInt8(bitIndex)) }
        bitIndex += 1
        if bitIndex == 8 {
            bytes.append(current)
            current = 0
            bitIndex = 0
        }
    }

    public mutating func write(_ value: UInt32, bits: Int) {
        precondition(bits > 0 && bits <= 32, "bit count out of range")
        for i in 0..<bits {
            writeBit((value >> UInt32(i)) & 1 == 1)
        }
    }

    public mutating func write(_ value: Int, bits: Int) {
        write(UInt32(truncatingIfNeeded: value), bits: bits)
    }

    public mutating func write(_ value: UInt8) { write(UInt32(value), bits: 8) }
    public mutating func write(_ value: UInt16) { write(UInt32(value), bits: 16) }
    public mutating func write(_ value: Bool) { writeBit(value) }

    public mutating func write(float value: Float) {
        write(value.bitPattern, bits: 32)
    }

    /// Quantized float in a known range — the workhorse for positions and velocities.
    public mutating func write(quantized value: Float, min lo: Float, max hi: Float, bits: Int) {
        let clamped = MathUtil.clamp(value, lo, hi)
        let scale = Float((1 << UInt32(bits)) - 1)
        let normalized = (clamped - lo) / max(hi - lo, 1e-6)
        write(UInt32((normalized * scale).rounded()), bits: bits)
    }

    /// Angles get 12 bits: 0.09° of resolution, which is below aim-assist noise.
    public mutating func write(angle: Float) {
        write(quantized: MathUtil.wrapAngle(angle), min: -.pi, max: .pi, bits: 12)
    }

    public mutating func write(position: Vec3, bounds: AABB) {
        write(quantized: position.x, min: bounds.min.x, max: bounds.max.x, bits: 16)
        write(quantized: position.y, min: bounds.min.y, max: bounds.max.y, bits: 14)
        write(quantized: position.z, min: bounds.min.z, max: bounds.max.z, bits: 16)
    }

    public mutating func write(string: String, maxLength: Int = 31) {
        let utf8 = Array(string.utf8.prefix(maxLength))
        write(UInt32(utf8.count), bits: 5)
        for byte in utf8 { write(byte) }
    }

    public mutating func align() {
        if bitIndex > 0 {
            bytes.append(current)
            current = 0
            bitIndex = 0
        }
    }

    public mutating func finish() -> Data {
        align()
        return Data(bytes)
    }

    public var bitCount: Int { bytes.count * 8 + bitIndex }
}

public struct BitReader {
    private let bytes: [UInt8]
    private var byteIndex = 0
    private var bitIndex = 0
    public private(set) var failed = false

    public init(data: Data) { bytes = [UInt8](data) }
    public init(bytes: [UInt8]) { self.bytes = bytes }

    public mutating func readBit() -> Bool {
        guard byteIndex < bytes.count else {
            failed = true
            return false
        }
        let bit = (bytes[byteIndex] >> UInt8(bitIndex)) & 1 == 1
        bitIndex += 1
        if bitIndex == 8 { bitIndex = 0; byteIndex += 1 }
        return bit
    }

    public mutating func read(bits: Int) -> UInt32 {
        var value: UInt32 = 0
        for i in 0..<bits where readBit() {
            value |= (1 << UInt32(i))
        }
        return value
    }

    public mutating func readUInt8() -> UInt8 { UInt8(truncatingIfNeeded: read(bits: 8)) }
    public mutating func readUInt16() -> UInt16 { UInt16(truncatingIfNeeded: read(bits: 16)) }
    public mutating func readUInt32() -> UInt32 { read(bits: 32) }
    public mutating func readBool() -> Bool { readBit() }
    public mutating func readInt(bits: Int) -> Int { Int(read(bits: bits)) }

    public mutating func readFloat() -> Float { Float(bitPattern: read(bits: 32)) }

    public mutating func readQuantized(min lo: Float, max hi: Float, bits: Int) -> Float {
        let scale = Float((1 << UInt32(bits)) - 1)
        let raw = Float(read(bits: bits))
        return lo + (raw / scale) * (hi - lo)
    }

    public mutating func readAngle() -> Float {
        readQuantized(min: -.pi, max: .pi, bits: 12)
    }

    public mutating func readPosition(bounds: AABB) -> Vec3 {
        Vec3(readQuantized(min: bounds.min.x, max: bounds.max.x, bits: 16),
             readQuantized(min: bounds.min.y, max: bounds.max.y, bits: 14),
             readQuantized(min: bounds.min.z, max: bounds.max.z, bits: 16))
    }

    public mutating func readString() -> String {
        let count = Int(read(bits: 5))
        var utf8: [UInt8] = []
        utf8.reserveCapacity(count)
        for _ in 0..<count { utf8.append(readUInt8()) }
        return String(decoding: utf8, as: UTF8.self)
    }

    public var isAtEnd: Bool { byteIndex >= bytes.count }
}
