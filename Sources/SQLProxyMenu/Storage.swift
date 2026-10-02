import Foundation

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let support = home.appendingPathComponent("Library/Application Support/SQLProxyMenu", isDirectory: true)
    static let config = support.appendingPathComponent("config.json")
    static let pids = support.appendingPathComponent("pids.json")
    static let logs = home.appendingPathComponent("Library/Logs/SQLProxyMenu", isDirectory: true)

    static func ensure(_ dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Caminho com ~ no lugar da home, para exibição.
    static func display(_ url: URL) -> String {
        url.path.replacingOccurrences(of: home.path, with: "~")
    }
}

enum ConfigStore {
    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: Paths.config) else { return AppConfig() }
        return (try? JSONDecoder().decode(AppConfig.self, from: data)) ?? AppConfig()
    }

    static func save(_ config: AppConfig) {
        Paths.ensure(Paths.support)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(config) {
            try? data.write(to: Paths.config, options: .atomic)
        }
    }
}

/// PIDs dos proxies iniciados pelo app, para encerrar órfãos se o app travar.
enum PIDStore {
    static func load() -> [Int32] {
        guard let data = try? Data(contentsOf: Paths.pids) else { return [] }
        return (try? JSONDecoder().decode([Int32].self, from: data)) ?? []
    }

    static func save(_ pids: [Int32]) {
        Paths.ensure(Paths.support)
        if let data = try? JSONEncoder().encode(pids) {
            try? data.write(to: Paths.pids, options: .atomic)
        }
    }
}

enum LogFiles {
    private static let maxSize = 5 * 1024 * 1024

    static func url(for name: String) -> URL {
        let safe = name.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
        return Paths.logs.appendingPathComponent("\(safe).log")
    }

    static func append(_ line: String, name: String) {
        Paths.ensure(Paths.logs)
        let url = url(for: name)
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path)[.size]) as? Int, size > maxSize {
            let old = url.appendingPathExtension("1")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data((line + "\n").utf8))
    }
}
