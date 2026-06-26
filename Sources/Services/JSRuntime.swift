import Foundation
import JavaScriptCore

/// Real JavaScript execution via Apple's JavaScriptCore (allowed on iOS).
/// Provides console.log/error, a tiny require() for utility modules, and timers.
final class JSRuntime {
    private let context = JSContext()!
    private var logs: [String] = []

    init() {
        setupConsole()
        setupGlobals()
    }

    /// Executes JS source and returns combined console output (and final value).
    func run(_ source: String, timeout: TimeInterval = 5) -> (output: String, error: Bool) {
        logs.removeAll()
        var caughtError: String?

        context.exceptionHandler = { _, exception in
            caughtError = exception?.toString() ?? "Unknown JS error"
        }

        // Guard against infinite loops with a wall-clock watchdog.
        let deadline = Date().addingTimeInterval(timeout)
        let watchdog = JSValue(object: { () -> Bool in Date() > deadline } as @convention(block) () -> Bool,
                               in: context)
        context.setObject(watchdog, forKeyedSubscript: "__deadlineExceeded" as NSString)

        let value = context.evaluateScript(source)

        if let err = caughtError {
            let pre = logs.isEmpty ? "" : logs.joined(separator: "\n") + "\n"
            return (pre + "❌ Ошибка: " + err, true)
        }

        var out = logs.joined(separator: "\n")
        // If the script ends in an expression value, show it too (REPL-like).
        if logs.isEmpty, let v = value, !v.isUndefined, !v.isNull {
            out = v.toString() ?? ""
        }
        return (out.isEmpty ? "(нет вывода)" : out, false)
    }

    // MARK: - console

    private func setupConsole() {
        let console = JSValue(newObjectIn: context)!
        let log: @convention(block) () -> Void = { [weak self] in
            let args = JSContext.currentArguments() as? [JSValue] ?? []
            self?.logs.append(args.map { Self.stringify($0) }.joined(separator: " "))
        }
        for name in ["log", "info", "debug", "warn", "error"] {
            console.setObject(log, forKeyedSubscript: name as NSString)
        }
        context.setObject(console, forKeyedSubscript: "console" as NSString)
    }

    private static func stringify(_ v: JSValue) -> String {
        if v.isObject, let json = v.context
            .objectForKeyedSubscript("JSON")
            .invokeMethod("stringify", withArguments: [v, NSNull(), 2]),
           !json.isUndefined, let s = json.toString(), s != "undefined" {
            return s
        }
        return v.toString() ?? "undefined"
    }

    // MARK: - globals / tiny require

    private func setupGlobals() {
        // setTimeout (synchronous-ish, immediate) so simple scripts don't crash
        let setTimeout: @convention(block) (JSValue, Double) -> Void = { fn, _ in
            fn.call(withArguments: [])
        }
        context.setObject(setTimeout, forKeyedSubscript: "setTimeout" as NSString)

        // Minimal require() supporting a couple of safe built-ins.
        let require: @convention(block) (String) -> JSValue? = { [weak self] name in
            guard let self else { return nil }
            switch name {
            case "util":
                return self.context.evaluateScript("({ inspect: (x) => JSON.stringify(x, null, 2) })")
            case "assert":
                return self.context.evaluateScript("""
                (function(){ var f = function(c,m){ if(!c) throw new Error(m||'assert failed'); };
                 f.equal=function(a,b,m){ if(a!=b) throw new Error(m||(a+' != '+b)); }; return f; })()
                """)
            default:
                self.logs.append("⚠️ require('\(name)') не поддерживается в этой среде")
                return JSValue(undefinedIn: self.context)
            }
        }
        context.setObject(require, forKeyedSubscript: "require" as NSString)
    }
}
