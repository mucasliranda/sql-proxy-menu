import Foundation
import SwiftUI

struct ProxyInstance: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var connectionName: String
    var port: Int
    var database = ""
    var privateIP = false
    var autoStart = false
}

extension ProxyInstance {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        connectionName = try c.decode(String.self, forKey: .connectionName)
        port = try c.decode(Int.self, forKey: .port)
        database = try c.decodeIfPresent(String.self, forKey: .database) ?? ""
        privateIP = try c.decodeIfPresent(Bool.self, forKey: .privateIP) ?? false
        autoStart = try c.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
    }
}

struct AppSettings: Codable, Equatable {
    var startPort = 44515
    var autoIAMAuthn = true
    var proxyPathOverride = ""
    var notifyOnCrash = true
    var notifyOnCredentialExpired = true
    var lastProject = ""
}

extension AppSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        startPort = try c.decodeIfPresent(Int.self, forKey: .startPort) ?? d.startPort
        autoIAMAuthn = try c.decodeIfPresent(Bool.self, forKey: .autoIAMAuthn) ?? d.autoIAMAuthn
        proxyPathOverride = try c.decodeIfPresent(String.self, forKey: .proxyPathOverride) ?? d.proxyPathOverride
        notifyOnCrash = try c.decodeIfPresent(Bool.self, forKey: .notifyOnCrash) ?? d.notifyOnCrash
        notifyOnCredentialExpired = try c.decodeIfPresent(Bool.self, forKey: .notifyOnCredentialExpired) ?? d.notifyOnCredentialExpired
        lastProject = try c.decodeIfPresent(String.self, forKey: .lastProject) ?? d.lastProject
    }
}

struct AppConfig: Codable, Equatable {
    var instances: [ProxyInstance] = []
    var settings = AppSettings()
}

extension AppConfig {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        instances = try c.decodeIfPresent([ProxyInstance].self, forKey: .instances) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
    }
}

enum ProxyStatus: Equatable {
    case stopped
    case starting
    case running
    case credentialExpired
    case error(String)

    var isActive: Bool {
        switch self {
        case .starting, .running, .credentialExpired: true
        case .stopped, .error: false
        }
    }

    var label: String {
        switch self {
        case .stopped: "parado"
        case .starting: "iniciando…"
        case .running: "ativo"
        case .credentialExpired: "sem credencial"
        case .error: "erro"
        }
    }

    var color: Color {
        switch self {
        case .stopped: Color(nsColor: .tertiaryLabelColor)
        case .starting: .yellow
        case .running: .green
        case .credentialExpired: .orange
        case .error: .red
        }
    }

    var textColor: Color {
        switch self {
        case .running: .green
        case .credentialExpired: .orange
        case .error: .red
        case .stopped, .starting: .secondary
        }
    }
}

struct DiscoveredInstance: Decodable {
    let name: String
    let connectionName: String
    let region: String?
    let databaseVersion: String?

    var prettyVersion: String {
        guard let v = databaseVersion else { return "" }
        return v.replacingOccurrences(of: "POSTGRES_", with: "Postgres ").replacingOccurrences(of: "_", with: ".")
    }
}

struct ToolError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
