import Foundation

/// Deterministic PRNG (xoshiro128**). Determinism matters: the server replays client input,
/// bots must behave identically across a replay, and spray patterns must match on both ends.
public struct DeterministicRandom: RandomNumberGenerator, Sendable {
    private var s0: UInt32, s1: UInt32, s2: UInt32, s3: UInt32

    public init(seed: UInt64) {
        // SplitMix64 to spread the seed over the state.
        var z = seed &+ 0x9E3779B97F4A7C15
        func next() -> UInt64 {
            z = z &+ 0x9E3779B97F4A7C15
            var x = z
            x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
            x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
            return x ^ (x >> 31)
        }
        let a = next(), b = next()
        s0 = UInt32(truncatingIfNeeded: a)
        s1 = UInt32(truncatingIfNeeded: a >> 32)
        s2 = UInt32(truncatingIfNeeded: b)
        s3 = UInt32(truncatingIfNeeded: b >> 32)
        if s0 | s1 | s2 | s3 == 0 { s0 = 1 }
    }

    private mutating func nextUInt32() -> UInt32 {
        let result = rotl(s1 &* 5, 7) &* 9
        let t = s1 << 9
        s2 ^= s0; s3 ^= s1; s1 ^= s2; s0 ^= s3; s2 ^= t
        s3 = rotl(s3, 11)
        return result
    }

    private func rotl(_ x: UInt32, _ k: UInt32) -> UInt32 { (x << k) | (x >> (32 - k)) }

    public mutating func next() -> UInt64 {
        UInt64(nextUInt32()) << 32 | UInt64(nextUInt32())
    }

    /// Uniform in [0, 1).
    public mutating func unit() -> Float {
        Float(nextUInt32() >> 8) * (1.0 / Float(1 << 24))
    }

    /// Uniform in [-1, 1).
    public mutating func signedUnit() -> Float { unit() * 2 - 1 }

    public mutating func float(in range: ClosedRange<Float>) -> Float {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    public mutating func int(in range: ClosedRange<Int>) -> Int {
        guard range.upperBound > range.lowerBound else { return range.lowerBound }
        let span = UInt32(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(nextUInt32() % span)
    }

    public mutating func chance(_ p: Float) -> Bool { unit() < p }

    /// Uniform point inside the unit disk — used for bullet spread cones.
    public mutating func insideUnitDisk() -> (Float, Float) {
        let r = unit().squareRoot()
        let theta = unit() * 2 * .pi
        return (r * cos(theta), r * sin(theta))
    }

    public mutating func pick<T>(_ items: [T]) -> T? {
        items.isEmpty ? nil : items[int(in: 0...(items.count - 1))]
    }

    public mutating func shuffled<T>(_ items: [T]) -> [T] {
        var a = items
        guard a.count > 1 else { return a }
        for i in stride(from: a.count - 1, to: 0, by: -1) {
            a.swapAt(i, int(in: 0...i))
        }
        return a
    }
}
