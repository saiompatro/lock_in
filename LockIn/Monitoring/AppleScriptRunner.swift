import Foundation

struct ScriptFailure: Error, Sendable {
    let code: Int
    let message: String

    /// errAEEventNotPermitted: the user denied Automation access.
    static let notPermitted = -1743
    /// errAEEventWouldRequireUserConsent: not yet decided.
    static let wouldRequireConsent = -1744

    var isPermissionProblem: Bool { code == Self.notPermitted || code == Self.wouldRequireConsent }
}

/// Compiles AppleScripts once and executes them on a private serial queue (never the main thread).
final class AppleScriptRunner: @unchecked Sendable {
    private let queue: DispatchQueue
    /// Confined to `queue`.
    private var compiled: [String: NSAppleScript] = [:]

    init(label: String) {
        queue = DispatchQueue(label: label, qos: .utility)
    }

    /// Executes `source` (compiled once per `key`) and maps the result descriptor on the queue.
    func run<T: Sendable>(
        key: String,
        source: String,
        transform: @escaping @Sendable (NSAppleEventDescriptor) -> T
    ) async -> Result<T, ScriptFailure> {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.execute(key: key, source: source, transform: transform))
            }
        }
    }

    /// Convenience: the result's string value ("" when empty).
    func runString(key: String, source: String) async -> Result<String, ScriptFailure> {
        await run(key: key, source: source) { $0.stringValue ?? "" }
    }

    private func execute<T>(
        key: String,
        source: String,
        transform: (NSAppleEventDescriptor) -> T
    ) -> Result<T, ScriptFailure> {
        let script: NSAppleScript
        if let cached = compiled[key] {
            script = cached
        } else {
            guard let fresh = NSAppleScript(source: source) else {
                return .failure(ScriptFailure(code: -1, message: "Could not create script"))
            }
            var compileError: NSDictionary?
            if !fresh.compileAndReturnError(&compileError) {
                return .failure(Self.failure(from: compileError))
            }
            compiled[key] = fresh
            script = fresh
        }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if errorInfo != nil {
            return .failure(Self.failure(from: errorInfo))
        }
        return .success(transform(descriptor))
    }

    private static func failure(from info: NSDictionary?) -> ScriptFailure {
        let code = (info?["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue ?? -1
        let message = (info?["NSAppleScriptErrorMessage"] as? String) ?? "AppleScript error"
        return ScriptFailure(code: code, message: message)
    }
}
