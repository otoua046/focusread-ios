import Foundation
import os

enum FocusReadBenchmarkSignposts {
    static let subsystem = "com.otoua046.app"
    static let category = "benchmark"

    private static let log = OSLog(subsystem: subsystem, category: category)

    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["FOCUSREAD_BENCHMARK_SIGNPOSTS"] == "1"
            || ProcessInfo.processInfo.arguments.contains("-FocusReadBenchmarks")
    }

    static func measure<T>(_ name: StaticString, operation: () throws -> T) rethrows -> T {
        guard isEnabled else {
            return try operation()
        }

        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: signpostID)
        defer {
            os_signpost(.end, log: log, name: name, signpostID: signpostID)
        }
        return try operation()
    }

    static func measure<T>(_ name: StaticString, operation: () async throws -> T) async rethrows -> T {
        guard isEnabled else {
            return try await operation()
        }

        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: signpostID)
        defer {
            os_signpost(.end, log: log, name: name, signpostID: signpostID)
        }
        return try await operation()
    }
}
