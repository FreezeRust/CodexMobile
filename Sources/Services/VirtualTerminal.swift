import Foundation

/// A safe, sandbox-friendly virtual terminal that operates on a project's files.
/// iOS forbids running real shell commands, so this emulates common file commands.
@MainActor
struct VirtualTerminal {
    unowned let store: AppStore
    let projectID: UUID

    /// Runs a command line and returns its textual output. `error` is set on failure.
    func run(_ line: String) -> (output: String, error: Bool) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return ("", false) }

        // split first token as command, keep the rest as raw args
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let cmd = String(parts[0])
        let rest = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

        switch cmd {
        case "help":   return (helpText, false)
        case "ls":     return (lsCommand(rest), false)
        case "tree":   return (treeCommand(), false)
        case "pwd":    return ("/\(projectName)", false)
        case "cat":    return catCommand(rest)
        case "mkdir":  return mkdirCommand(rest)
        case "touch":  return touchCommand(rest)
        case "rm":     return rmCommand(rest)
        case "mv":     return mvCommand(rest)
        case "echo":   return echoCommand(rest)
        case "clear":  return ("\u{0001}CLEAR", false)   // sentinel handled by UI
        default:
            return ("\(cmd): команда не найдена. Введите 'help' для списка.", true)
        }
    }

    // MARK: - Commands

    private var projectName: String { store.project(projectID)?.name ?? "project" }
    private var files: [GeneratedFile] { store.project(projectID)?.files ?? [] }

    private var helpText: String {
        """
        Доступные команды:
          ls [путь]        список файлов/папок
          tree             дерево проекта
          cat <файл>       показать содержимое
          cat > <файл>     ... <<EOF  (см. echo для записи)
          echo <текст> > <файл>   записать текст в файл
          echo <текст> >> <файл>  дописать в конец
          mkdir <путь>     создать папку
          touch <файл>     создать пустой файл
          mv <из> <в>      переименовать/переместить
          rm <путь>        удалить файл или папку
          pwd              текущий проект
          clear            очистить терминал
        """
    }

    private func lsCommand(_ arg: String) -> String {
        let prefix = arg.isEmpty ? "" : (arg.hasSuffix("/") ? arg : arg + "/")
        var names = Set<String>()
        for f in files {
            guard f.name.hasPrefix(prefix) else { continue }
            let rest = String(f.name.dropFirst(prefix.count))
            if rest.isEmpty { continue }
            if let slash = rest.firstIndex(of: "/") {
                names.insert(String(rest[..<slash]) + "/")
            } else {
                names.insert(rest + (f.isDirectory ? "/" : ""))
            }
        }
        if names.isEmpty { return arg.isEmpty ? "(пусто)" : "ls: \(arg): нет такого пути" }
        return names.sorted().joined(separator: "\n")
    }

    private func treeCommand() -> String {
        let sorted = files.map { $0.name + ($0.isDirectory ? "/" : "") }.sorted()
        if sorted.isEmpty { return "(пусто)" }
        return sorted.map { "  " + $0 }.joined(separator: "\n")
    }

    private func catCommand(_ arg: String) -> (String, Bool) {
        guard let f = files.first(where: { $0.name == arg && !$0.isDirectory }) else {
            return ("cat: \(arg): нет такого файла", true)
        }
        return (f.content.isEmpty ? "(пустой файл)" : f.content, false)
    }

    private func mkdirCommand(_ arg: String) -> (String, Bool) {
        guard !arg.isEmpty else { return ("mkdir: укажите путь", true) }
        store.addFolder(projectID: projectID, path: arg)
        return ("создана папка: \(arg)", false)
    }

    private func touchCommand(_ arg: String) -> (String, Bool) {
        guard !arg.isEmpty else { return ("touch: укажите имя файла", true) }
        if files.contains(where: { $0.name == arg }) { return ("файл уже существует: \(arg)", false) }
        store.addEmptyFile(projectID: projectID, name: arg)
        return ("создан файл: \(arg)", false)
    }

    private func rmCommand(_ arg: String) -> (String, Bool) {
        let path = arg.replacingOccurrences(of: "-rf ", with: "").replacingOccurrences(of: "-r ", with: "").trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return ("rm: укажите путь", true) }
        // folder?
        if files.contains(where: { ($0.isDirectory && $0.name == path) || $0.name.hasPrefix(path + "/") }) {
            store.deleteFolder(projectID: projectID, path: path)
            return ("удалено: \(path)", false)
        }
        if let f = files.first(where: { $0.name == path }) {
            store.deleteFile(f.id, projectID: projectID)
            return ("удалён файл: \(path)", false)
        }
        return ("rm: \(path): нет такого файла", true)
    }

    private func mvCommand(_ arg: String) -> (String, Bool) {
        let comps = arg.split(separator: " ").map(String.init)
        guard comps.count == 2 else { return ("mv: использование: mv <из> <в>", true) }
        guard let f = files.first(where: { $0.name == comps[0] }) else {
            return ("mv: \(comps[0]): нет такого файла", true)
        }
        store.renameFile(f.id, projectID: projectID, name: comps[1])
        return ("\(comps[0]) → \(comps[1])", false)
    }

    private func echoCommand(_ arg: String) -> (String, Bool) {
        // echo text >> file  /  echo text > file
        if let range = arg.range(of: ">>") {
            let text = unquote(String(arg[..<range.lowerBound]).trimmingCharacters(in: .whitespaces))
            let file = String(arg[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return writeFile(file, text: text, append: true)
        }
        if let range = arg.range(of: ">") {
            let text = unquote(String(arg[..<range.lowerBound]).trimmingCharacters(in: .whitespaces))
            let file = String(arg[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return writeFile(file, text: text, append: false)
        }
        return (unquote(arg), false)
    }

    private func writeFile(_ name: String, text: String, append: Bool) -> (String, Bool) {
        guard !name.isEmpty else { return ("echo: укажите файл", true) }
        if let f = files.first(where: { $0.name == name && !$0.isDirectory }) {
            let newContent = append ? (f.content + (f.content.isEmpty ? "" : "\n") + text) : text
            store.updateFile(f.id, projectID: projectID, content: newContent, note: "терминал")
        } else {
            store.attachFiles([GeneratedFile(name: name, language: ext(name), content: text)], projectID: projectID)
        }
        return ("записано в \(name)", false)
    }

    private func unquote(_ s: String) -> String {
        var t = s
        if (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")), t.count >= 2 {
            t = String(t.dropFirst().dropLast())
        }
        return t.replacingOccurrences(of: "\\n", with: "\n")
    }

    private func ext(_ name: String) -> String {
        (name as NSString).pathExtension.isEmpty ? "text" : (name as NSString).pathExtension
    }
}
