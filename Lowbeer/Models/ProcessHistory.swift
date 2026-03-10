import Foundation

/// Fixed-size ring buffer of CPU % samples for sparkline rendering.
/// At 3-second intervals, 60 samples gives ~3 minutes of history.
struct ProcessHistory: Sendable {
    private var buffer: [Double]
    private var index: Int = 0
    private(set) var count: Int = 0
    let capacity: Int

    init(capacity: Int = 60) {
        self.capacity = capacity
        self.buffer = Array(repeating: 0, count: capacity)
    }

    mutating func append(_ value: Double) {
        buffer[index] = value
        index = (index + 1) % capacity
        if count < capacity { count += 1 }
    }

    /// Returns samples in chronological order (oldest first).
    var samples: [Double] {
        if count < capacity {
            return Array(buffer[0..<count])
        }
        return Array(buffer[index..<capacity]) + Array(buffer[0..<index])
    }

    var latest: Double {
        guard count > 0 else { return 0 }
        let i = index == 0 ? capacity - 1 : index - 1
        return buffer[i]
    }

    var peak: Double {
        guard count > 0 else { return 0 }
        return samples.max() ?? 0
    }

    var average: Double {
        guard count > 0 else { return 0 }
        return samples.reduce(0, +) / Double(count)
    }
}
