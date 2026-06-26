import Foundation
import JavaScriptCore

/// Node-like JavaScript runtime via JavaScriptCore.
/// Provides console, fs (over project files), require (local .js modules + builtins),
/// process, timers and a synchronous fetch. Runs fast once JIT is enabled in SideStore.
final class JSRuntime {
    private let context = JSContext()!
    private var logs: [String] = []

    // File bridge to the project (read/write virtual files).
    private let readFile: (String) -> String?
    private let writeFile: (String, String) -> Void
    private let listFiles: () -> [String]
    private let projectName: String

    /// `files`/`write`/`list` operate on the project's virtual filesystem.
    init(projectName: String = "project",
         readFile: @escaping (String) -> String? = { _ in nil },
         writeFile: @escaping (String, String) -> Void = { _, _ in },
         listFiles: @escaping () -> [String] = { [] }) {
        self.projectName = projectName
        self.readFile = readFile
        self.writeFile = writeFile
        self.listFiles = listFiles
        setupConsole()
        setupProcess()
        setupTimers()
        setupFetch()
        setupFS()
        setupRequire()
    }

    func run(_ source: String, timeout: TimeInterval = 8) -> (output: String, error: Bool) {
        logs.removeAll()
        var caughtError: String?
        context.exceptionHandler = { _, exception in
            let line = exception?.objectForKeyedSubscript("line")?.toString() ?? "?"
            caughtError = (exception?.toString() ?? "Unknown JS error") + " (строка \(line))"
        }

        let value = context.evaluateScript(source)
        // Drain microtasks/timers queued during execution.
        drainTimers(until: Date().addingTimeInterval(min(timeout, 3)))

        if let err = caughtError {
            let pre = logs.isEmpty ? "" : logs.joined(separator: "\n") + "\n"
            return (pre + "❌ Ошибка: " + err, true)
        }
        var out = logs.joined(separator: "\n")
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
        if v.isObject, let json = v.context.objectForKeyedSubscript("JSON")
            .invokeMethod("stringify", withArguments: [v, NSNull(), 2]),
           !json.isUndefined, let s = json.toString(), s != "undefined" { return s }
        return v.toString() ?? "undefined"
    }

    // MARK: - process / globals
    private func setupProcess() {
        let process = JSValue(newObjectIn: context)!
        process.setObject(["node": "OpenVolt-JS", "v8": "JavaScriptCore"], forKeyedSubscript: "versions" as NSString)
        process.setObject("ios", forKeyedSubscript: "platform" as NSString)
        process.setObject([String](), forKeyedSubscript: "argv" as NSString)
        let cwd: @convention(block) () -> String = { [weak self] in "/\(self?.projectName ?? "project")" }
        process.setObject(cwd, forKeyedSubscript: "cwd" as NSString)
        let stdoutObj = JSValue(newObjectIn: context)!
        let write: @convention(block) (String) -> Void = { [weak self] s in self?.logs.append(s) }
        stdoutObj.setObject(write, forKeyedSubscript: "write" as NSString)
        process.setObject(stdoutObj, forKeyedSubscript: "stdout" as NSString)
        context.setObject(process, forKeyedSubscript: "process" as NSString)
        context.setObject(context.globalObject, forKeyedSubscript: "global" as NSString)
    }

    // MARK: - timers (collected then drained)
    private struct Timer { let fn: JSValue; let fire: Date }
    private var timers: [Timer] = []
    private func setupTimers() {
        let setTimeout: @convention(block) (JSValue, Double) -> Void = { [weak self] fn, ms in
            self?.timers.append(Timer(fn: fn, fire: Date().addingTimeInterval(ms/1000)))
        }
        let setInterval: @convention(block) (JSValue, Double) -> Void = { [weak self] fn, _ in
            // run once to avoid infinite loops in a sync environment
            self?.timers.append(Timer(fn: fn, fire: Date()))
        }
        let noop: @convention(block) (JSValue) -> Void = { _ in }
        context.setObject(setTimeout, forKeyedSubscript: "setTimeout" as NSString)
        context.setObject(setInterval, forKeyedSubscript: "setInterval" as NSString)
        context.setObject(noop, forKeyedSubscript: "clearTimeout" as NSString)
        context.setObject(noop, forKeyedSubscript: "clearInterval" as NSString)
    }
    private func drainTimers(until: Date) {
        var iterations = 0
        while !timers.isEmpty && Date() < until && iterations < 1000 {
            timers.sort { $0.fire < $1.fire }
            let t = timers.removeFirst()
            t.fn.call(withArguments: [])
            iterations += 1
        }
    }

    // MARK: - fetch (synchronous network)
    private func setupFetch() {
        // fetchSync(url) -> { status, text } ; and async fetch returning resolved-ish object
        let fetchSync: @convention(block) (String, JSValue?) -> JSValue = { [weak self] urlStr, opts in
            guard let self else { return JSValue(nullIn: self?.context) }
            guard let url = URL(string: urlStr) else {
                return JSValue(object: ["ok": false, "status": 0, "text": "bad url"], in: self.context)
            }
            var req = URLRequest(url: url); req.timeoutInterval = 15
            if let opts, opts.isObject {
                if let m = opts.objectForKeyedSubscript("method")?.toString(), m != "undefined" { req.httpMethod = m }
                if let b = opts.objectForKeyedSubscript("body")?.toString(), b != "undefined" { req.httpBody = b.data(using: .utf8) }
                if let h = opts.objectForKeyedSubscript("headers"), h.isObject,
                   let dict = h.toDictionary() as? [String: Any] {
                    for (k, v) in dict { req.setValue("\(v)", forHTTPHeaderField: k) }
                }
            }
            let sem = DispatchSemaphore(value: 0)
            var status = 0; var body = ""
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                sem.signal()
            }.resume()
            _ = sem.wait(timeout: .now() + 16)
            return JSValue(object: ["ok": (200...299).contains(status), "status": status, "text": body],
                           in: self.context)
        }
        context.setObject(fetchSync, forKeyedSubscript: "fetchSync" as NSString)
        // Promise-like fetch wrapper using fetchSync
        context.evaluateScript("""
        globalThis.fetch = function(url, opts) {
          const r = fetchSync(url, opts || {});
          return Promise.resolve({
            ok: r.ok, status: r.status,
            text: () => Promise.resolve(r.text),
            json: () => Promise.resolve(JSON.parse(r.text || 'null'))
          });
        };
        """)
    }

    // MARK: - fs (over project files)
    private func setupFS() {
        let fs = JSValue(newObjectIn: context)!
        let read: @convention(block) (String) -> String? = { [weak self] p in self?.readFile(p) }
        let write: @convention(block) (String, String) -> Void = { [weak self] p, c in self?.writeFile(p, c) }
        let exists: @convention(block) (String) -> Bool = { [weak self] p in self?.readFile(p) != nil }
        let readdir: @convention(block) () -> [String] = { [weak self] in self?.listFiles() ?? [] }
        fs.setObject(read, forKeyedSubscript: "readFileSync" as NSString)
        fs.setObject(write, forKeyedSubscript: "writeFileSync" as NSString)
        fs.setObject(exists, forKeyedSubscript: "existsSync" as NSString)
        fs.setObject(readdir, forKeyedSubscript: "readdirSync" as NSString)
        context.setObject(fs, forKeyedSubscript: "__fs" as NSString)
    }

    // MARK: - require (local .js modules + builtins)
    private var moduleCache: [String: JSValue] = [:]
    private func setupRequire() {
        let require: @convention(block) (String) -> JSValue? = { [weak self] name in
            guard let self else { return nil }
            switch name {
            case "fs": return self.context.objectForKeyedSubscript("__fs")
            case "util":
                return self.context.evaluateScript("({ inspect: (x) => JSON.stringify(x, null, 2) })")
            case "path":
                return self.context.evaluateScript("""
                ({ join: (...a) => a.join('/').replace(/\\/+/g,'/'),
                   basename: (p) => p.split('/').pop(),
                   extname: (p) => { const b = p.split('/').pop(); const i = b.lastIndexOf('.'); return i<0?'':b.slice(i); } })
                """)
            case "assert":
                return self.context.evaluateScript("""
                (function(){ var f=function(c,m){ if(!c) throw new Error(m||'assert failed'); };
                 f.equal=function(a,b,m){ if(a!=b) throw new Error(m||(a+' != '+b)); }; return f; })()
                """)
            default:
                // Local module: resolve <name>.js / <name> in project files.
                return self.requireLocal(name)
            }
        }
        context.setObject(require, forKeyedSubscript: "require" as NSString)
    }

    private func requireLocal(_ name: String) -> JSValue {
        var candidates = [name]
        if !name.hasSuffix(".js") { candidates.append(name + ".js") }
        // strip leading ./
        candidates = candidates.map { $0.hasPrefix("./") ? String($0.dropFirst(2)) : $0 }
        for path in candidates {
            if let cached = moduleCache[path] { return cached }
            if let src = readFile(path) {
                // CommonJS wrapper
                let wrapper = "(function(){ var module={exports:{}}; var exports=module.exports;\n\(src)\n; return module.exports; })()"
                let result = context.evaluateScript(wrapper) ?? JSValue(undefinedIn: context)
                moduleCache[path] = result
                return result
            }
        }
        logs.append("⚠️ require('\(name)'): модуль не найден (поддерживаются локальные .js, fs, path, util, assert)")
        return JSValue(undefinedIn: context)
    }
}
