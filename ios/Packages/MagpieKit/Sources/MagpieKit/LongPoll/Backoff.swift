import Foundation

public struct Backoff: Sendable {
    private var ceiling: TimeInterval = 0.5
    private let random: @Sendable () -> Double

    /// The random source returns a value in 0...1.
    public init(random: @escaping @Sendable () -> Double = { Double.random(in: 0...1) }) {
        self.random = random
    }

    public mutating func next() -> TimeInterval {
        let sample = random()
        let delay = ceiling * (sample.isFinite ? min(1, max(0, sample)) : 0)
        ceiling = min(30, ceiling * 2)
        return delay
    }

    public mutating func reset() { ceiling = 0.5 }
}
