import Foundation

/// Localiza e executa as ferramentas de linha de comando (gcloud, cloud-sql-proxy).
/// Apps abertos pelo Finder não herdam o PATH do shell, então procuramos nos caminhos conhecidos.
enum Tools {
    static let searchDirs: [String] = {
        let home = Paths.home.path
        return [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/google-cloud-sdk/bin",
            "/opt/homebrew/share/google-cloud-sdk/bin",
            "/usr/local/share/google-cloud-sdk/bin",
            "/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/bin",
        ]
    }()

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let base = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (searchDirs + [base]).joined(separator: ":")
        return env
    }

    static func find(_ name: String, override: String = "") -> String? {
        let fm = FileManager.default
        let custom = (override as NSString).expandingTildeInPath
        if !override.trimmed.isEmpty {
            return fm.isExecutableFile(atPath: custom) ? custom : nil
        }
        for dir in searchDirs {
            let path = "\(dir)/\(name)"
            if fm.isExecutableFile(atPath: path) { return path }
        }
        // Último recurso: pergunta ao shell de login do usuário.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v \(name)"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(decoding: data, as: UTF8.self).trimmed
        return out.hasPrefix("/") && fm.isExecutableFile(atPath: out) ? out : nil
    }

    struct Result {
        let status: Int32
        let out: String
        let err: String
    }

    static func run(_ executable: String, _ args: [String]) async -> Result {
        await Task.detached { runSync(executable, args) }.value
    }

    private static func runSync(_ executable: String, _ args: [String]) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        p.environment = environment
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            return Result(status: -1, out: "", err: error.localizedDescription)
        }
        // Lê stderr em paralelo para não travar se o buffer encher.
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        return Result(
            status: p.terminationStatus,
            out: String(decoding: outData, as: UTF8.self),
            err: String(decoding: errData, as: UTF8.self)
        )
    }
}

enum Ports {
    /// true se ninguém está escutando em 127.0.0.1:port.
    static func isFree(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
