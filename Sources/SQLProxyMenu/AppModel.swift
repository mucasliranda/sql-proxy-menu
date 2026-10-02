import AppKit
import Foundation
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var config: AppConfig {
        didSet { if config != oldValue { ConfigStore.save(config) } }
    }
    @Published private(set) var status: [UUID: ProxyStatus] = [:]
    @Published private(set) var logs: [UUID: [String]] = [:]
    @Published private(set) var account = ""
    /// nil = ainda não verificado.
    @Published private(set) var credentialValid: Bool?
    @Published private(set) var reauthInProgress = false
    @Published private(set) var proxyPath: String?
    @Published private(set) var proxyVersion = ""
    @Published private(set) var gcloudPath: String?
    @Published var editingID: UUID?
    @Published var addFormToken = UUID()
    @Published var logsSelection: UUID?

    private var processes: [UUID: Process] = [:]
    private var startedAt: [UUID: Date] = [:]
    private var stopRequested: Set<UUID> = []
    private var pendingRestart: Set<UUID> = []
    private var lastError: [UUID: String] = [:]
    private var notifiedExpired = false
    private var timer: Timer?
    private var bootstrapped = false

    private static let maxLogLines = 2000
    private static let credentialMarkers = [
        "invalid_grant",
        "invalid_rapt",
        "reauth related error",
        "could not find default credentials",
        "oauth2: cannot fetch token",
        "token has been expired or revoked",
    ]

    init() {
        config = ConfigStore.load()
    }

    // MARK: - Consultas

    func status(_ id: UUID) -> ProxyStatus { status[id] ?? .stopped }
    func instance(_ id: UUID) -> ProxyInstance? { config.instances.first { $0.id == id } }
    func pid(_ id: UUID) -> Int32? { processes[id]?.processIdentifier }
    func startedAt(_ id: UUID) -> Date? { startedAt[id] }

    var activeCount: Int { config.instances.filter { status($0.id).isActive }.count }

    var credentialExpired: Bool {
        credentialValid == false || status.values.contains(.credentialExpired)
    }

    func connectionString(_ inst: ProxyInstance) -> String {
        let user = account.isEmpty ? "SEU_EMAIL" : account
        let encoded = user.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? user
        let db = inst.database.isEmpty ? "postgres" : inst.database
        return "postgresql://\(encoded)@127.0.0.1:\(inst.port)/\(db)"
    }

    /// Próximas portas livres a partir da porta inicial, ignorando as já cadastradas.
    func suggestedPorts(_ count: Int) -> [Int] {
        var used = Set(config.instances.map(\.port))
        var result: [Int] = []
        var port = max(1024, config.settings.startPort)
        while result.count < count && port < 65536 {
            if !used.contains(port) && Ports.isFree(port) {
                result.append(port)
                used.insert(port)
            }
            port += 1
        }
        return result
    }

    // MARK: - Ciclo de vida

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        refreshTools()
        await cleanupOrphans()
        for inst in config.instances where inst.autoStart {
            start(inst.id)
        }
        await refreshCredential()

        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            Task { @MainActor in await AppModel.shared.refreshCredential() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await AppModel.shared.refreshCredential() }
        }
    }

    func shutdown() {
        let procs = Array(processes.values)
        stopRequested.formUnion(processes.keys)
        procs.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(2)
        while procs.contains(where: \.isRunning) && Date() < deadline {
            usleep(50_000)
        }
        PIDStore.save([])
    }

    private func cleanupOrphans() async {
        let pids = PIDStore.load()
        guard !pids.isEmpty else { return }
        var killed = false
        for pid in pids where kill(pid, 0) == 0 {
            let r = await Tools.run("/bin/ps", ["-p", String(pid), "-o", "command="])
            if r.out.contains("cloud-sql-proxy") {
                kill(pid, SIGTERM)
                killed = true
            }
        }
        PIDStore.save([])
        if killed { try? await Task.sleep(nanoseconds: 800_000_000) }
    }

    func refreshTools() {
        proxyPath = Tools.find("cloud-sql-proxy", override: config.settings.proxyPathOverride)
        gcloudPath = Tools.find("gcloud")
        proxyVersion = ""
        if let path = proxyPath {
            Task {
                let r = await Tools.run(path, ["--version"])
                proxyVersion = r.out.trimmed.components(separatedBy: "version ").last ?? ""
            }
        }
    }

    // MARK: - Credencial

    func refreshCredential() async {
        guard let gcloud = gcloudPath else { return }
        let acc = await Tools.run(gcloud, ["config", "get-value", "account"])
        let accValue = acc.out.trimmed
        account = accValue == "(unset)" ? "" : accValue

        let token = await Tools.run(gcloud, ["auth", "application-default", "print-access-token"])
        let valid = token.status == 0
        credentialValid = valid
        if valid {
            notifiedExpired = false
            // Proxies que pararam de gerar token voltam a funcionar depois de reiniciados.
            for inst in config.instances where status(inst.id) == .credentialExpired {
                restart(inst.id)
            }
        } else {
            notifyExpired()
        }
    }

    func reauth() {
        guard !reauthInProgress, let gcloud = gcloudPath else { return }
        reauthInProgress = true
        Task {
            let r = await Tools.run(gcloud, ["auth", "application-default", "login"])
            reauthInProgress = false
            if r.status == 0 {
                await refreshCredential()
                // O proxy carrega a credencial ao iniciar, então todos os ativos precisam reiniciar.
                for inst in config.instances where status(inst.id).isActive {
                    restart(inst.id)
                }
            } else {
                let msg = r.err.trimmed.components(separatedBy: "\n").last ?? "Erro desconhecido"
                Notifier.send(title: "Reautenticação não concluída", body: msg)
            }
        }
    }

    private func notifyExpired() {
        guard !notifiedExpired else { return }
        notifiedExpired = true
        guard config.settings.notifyOnCredentialExpired else { return }
        let affected = config.instances.filter { status($0.id).isActive }.map(\.name)
        let body = affected.isEmpty
            ? "Entre de novo para conseguir ligar os proxies."
            : "\(affected.count) proxy(s) não conseguem gerar tokens (\(affected.joined(separator: ", ")))."
        Notifier.send(title: "Credencial do Google expirou", body: body, category: Notifier.credentialCategory)
    }

    // MARK: - Proxies

    func toggle(_ id: UUID) {
        status(id).isActive ? stop(id) : start(id)
    }

    func start(_ id: UUID) {
        guard let inst = instance(id), processes[id] == nil else { return }
        guard let path = proxyPath else {
            status[id] = .error("cloud-sql-proxy não encontrado. Instale com: brew install cloud-sql-proxy")
            return
        }
        guard Ports.isFree(inst.port) else {
            status[id] = .error("Porta \(inst.port) já está em uso por outro processo")
            return
        }

        var args = ["--address", "127.0.0.1", "--port", String(inst.port)]
        if config.settings.autoIAMAuthn { args.append("--auto-iam-authn") }
        if inst.privateIP { args.append("--private-ip") }
        args.append(inst.connectionName)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.environment = Tools.environment
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let lines = String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .map(String.init)
            DispatchQueue.main.async {
                AppModel.shared.handle(lines, for: id)
            }
        }
        process.terminationHandler = { proc in
            let code = proc.terminationStatus
            DispatchQueue.main.async {
                AppModel.shared.didExit(id, code: code)
            }
        }

        do {
            try process.run()
        } catch {
            status[id] = .error("Falha ao iniciar: \(error.localizedDescription)")
            return
        }
        processes[id] = process
        startedAt[id] = Date()
        stopRequested.remove(id)
        lastError[id] = nil
        status[id] = .starting
        appendLog(id, "$ cloud-sql-proxy " + args.joined(separator: " "))
        savePIDs()
    }

    func stop(_ id: UUID) {
        guard let process = processes[id] else {
            status[id] = .stopped
            return
        }
        stopRequested.insert(id)
        process.terminate()
    }

    func restart(_ id: UUID) {
        guard processes[id] != nil else {
            start(id)
            return
        }
        guard !pendingRestart.contains(id) else { return }
        pendingRestart.insert(id)
        stop(id)
    }

    func stopAll() {
        for id in processes.keys { stop(id) }
    }

    private func handle(_ lines: [String], for id: UUID) {
        for line in lines {
            appendLog(id, line)
            let lower = line.lowercased()
            if lower.contains("ready for new connections") {
                if status(id) == .starting { status[id] = .running }
            } else if Self.credentialMarkers.contains(where: { lower.contains($0) }) {
                status[id] = .credentialExpired
                credentialValid = false
                notifyExpired()
            } else if lower.contains("error") {
                lastError[id] = line
            }
        }
    }

    private func didExit(_ id: UUID, code: Int32) {
        processes[id] = nil
        startedAt[id] = nil
        savePIDs()

        if pendingRestart.remove(id) != nil {
            stopRequested.remove(id)
            status[id] = .stopped
            appendLog(id, "— reiniciando proxy")
            start(id)
            return
        }
        if stopRequested.remove(id) != nil {
            status[id] = .stopped
            appendLog(id, "— proxy encerrado")
            return
        }
        guard instance(id) != nil else { return }
        appendLog(id, "— proxy encerrou sozinho (código \(code))")
        if status(id) == .credentialExpired { return }

        let message = lastError[id].map(Self.shortError) ?? "Encerrou inesperadamente (código \(code))"
        status[id] = .error(message)
        if config.settings.notifyOnCrash, let name = instance(id)?.name {
            Notifier.send(title: "\(name) parou", body: message)
        }
    }

    private static func shortError(_ line: String) -> String {
        let noDate = line.replacingOccurrences(
            of: #"^\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2} "#, with: "", options: .regularExpression
        )
        return noDate.count > 160 ? String(noDate.prefix(160)) + "…" : noDate
    }

    private func appendLog(_ id: UUID, _ line: String) {
        var lines = logs[id] ?? []
        lines.append(line)
        if lines.count > Self.maxLogLines {
            lines.removeFirst(lines.count - Self.maxLogLines)
        }
        logs[id] = lines
        if let name = instance(id)?.name {
            LogFiles.append(line, name: name)
        }
    }

    func clearLogs(_ id: UUID) {
        logs[id] = []
    }

    private func savePIDs() {
        PIDStore.save(processes.values.map(\.processIdentifier))
    }

    // MARK: - Cadastro

    func add(_ instances: [ProxyInstance]) {
        config.instances.append(contentsOf: instances)
    }

    func update(_ inst: ProxyInstance) {
        guard let index = config.instances.firstIndex(where: { $0.id == inst.id }) else { return }
        let old = config.instances[index]
        config.instances[index] = inst
        let needsRestart = old.port != inst.port
            || old.connectionName != inst.connectionName
            || old.privateIP != inst.privateIP
        if needsRestart && status(inst.id).isActive {
            restart(inst.id)
        }
    }

    func remove(_ id: UUID) {
        if processes[id] != nil { stop(id) }
        config.instances.removeAll { $0.id == id }
        status[id] = nil
        logs[id] = nil
        if logsSelection == id { logsSelection = config.instances.first?.id }
    }

    func setAutoStart(_ id: UUID, _ value: Bool) {
        guard let index = config.instances.firstIndex(where: { $0.id == id }) else { return }
        config.instances[index].autoStart = value
    }

    func prepareEditor(for id: UUID?) {
        editingID = id
        addFormToken = UUID()
    }

    // MARK: - GCP

    func listProjects() async -> [String] {
        guard let gcloud = gcloudPath else { return [] }
        let r = await Tools.run(gcloud, ["projects", "list", "--format=value(projectId)", "--sort-by=projectId"])
        guard r.status == 0 else { return [] }
        return r.out.split(whereSeparator: \.isNewline).map(String.init)
    }

    func discover(project: String) async throws -> [DiscoveredInstance] {
        guard let gcloud = gcloudPath else {
            throw ToolError(message: "gcloud não encontrado. Instale o Google Cloud SDK.")
        }
        let r = await Tools.run(gcloud, ["sql", "instances", "list", "--project", project, "--format=json"])
        guard r.status == 0 else {
            let msg = r.err.trimmed.isEmpty ? "Falha ao consultar o GCP (código \(r.status))" : r.err.trimmed
            throw ToolError(message: msg)
        }
        let all = (try? JSONDecoder().decode([DiscoveredInstance].self, from: Data(r.out.utf8))) ?? []
        return all
            .filter { ($0.databaseVersion ?? "").hasPrefix("POSTGRES") }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Abrir ao iniciar sessão

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    /// Retorna uma mensagem de erro, se houver.
    func setLaunchAtLogin(_ enabled: Bool) -> String? {
        defer { objectWillChange.send() }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
