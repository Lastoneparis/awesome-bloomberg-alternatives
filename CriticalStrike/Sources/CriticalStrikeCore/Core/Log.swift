import Foundation

public enum LogLevel: Int, Comparable, Sendable {
    case verbose = 0, debug, info, warning, error
    public static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }

    var tag: String {
        switch self {
        case .verbose: return "VRB"
        case .debug: return "DBG"
        case .info: return "INF"
        case .warning: return "WRN"
        case .error: return "ERR"
        }
    }
}

/// Deliberately tiny: a shipping mobile game should not pay for string formatting
/// it will never print, so every call site goes through an autoclosure.
public enum Log {
    nonisolated(unsafe) public static var minimumLevel: LogLevel = {
        #if DEBUG
        return .debug
        #else
        return .warning
        #endif
    }()

    nonisolated(unsafe) public static var sink: ((LogLevel, String) -> Void)?

    public static func log(_ level: LogLevel, _ message: @autoclosure () -> String, category: String = "game") {
        guard level >= minimumLevel else { return }
        let line = "[\(level.tag)][\(category)] \(message())"
        if let sink { sink(level, line) } else { print(line) }
    }

    public static func verbose(_ m: @autoclosure () -> String, category: String = "game") {
        log(.verbose, m(), category: category)
    }
    public static func debug(_ m: @autoclosure () -> String, category: String = "game") {
        log(.debug, m(), category: category)
    }
    public static func info(_ m: @autoclosure () -> String, category: String = "game") {
        log(.info, m(), category: category)
    }
    public static func warn(_ m: @autoclosure () -> String, category: String = "game") {
        log(.warning, m(), category: category)
    }
    public static func error(_ m: @autoclosure () -> String, category: String = "game") {
        log(.error, m(), category: category)
    }
}
