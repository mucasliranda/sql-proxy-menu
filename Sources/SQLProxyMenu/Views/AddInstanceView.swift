import AppKit
import SwiftUI

/// Recria o formulário cada vez que a janela é aberta (para adicionar ou editar).
struct AddInstanceWindow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        AddInstanceView().id(model.addFormToken)
    }
}

struct AddInstanceView: View {
    @EnvironmentObject var model: AppModel

    private enum Tab: Hashable { case gcp, manual }

    private struct Candidate: Identifiable {
        var id: String { connectionName }
        let name: String
        let connectionName: String
        let region: String
        let version: String
        let alreadyAdded: Bool
        var selected: Bool
        var port: String
        var autoStart = false
    }

    @State private var tab: Tab = .gcp
    @State private var editing: ProxyInstance?

    // Buscar no GCP
    @State private var project = ""
    @State private var projects: [String] = []
    @State private var loading = false
    @State private var searched = false
    @State private var searchError: String?
    @State private var candidates: [Candidate] = []

    // Manual
    @State private var name = ""
    @State private var connectionName = ""
    @State private var port = ""
    @State private var database = ""
    @State private var privateIP = false

    @State private var autoStart = false
    @State private var validation: String?

    var body: some View {
        VStack(spacing: 0) {
            if editing == nil {
                Picker("", selection: $tab) {
                    Text("Buscar no GCP").tag(Tab.gcp)
                    Text("Manual").tag(Tab.manual)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                .padding(.top, 16)
            }

            Group {
                if tab == .gcp && editing == nil {
                    gcpForm
                } else {
                    manualForm
                }
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)

            if let validation {
                Text(validation)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancelar") { close() }
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle) { confirm() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConfirm)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 680, height: 540)
        .navigationTitle(editing == nil ? "Adicionar instância" : "Editar \(editing?.name ?? "")")
        .onAppear(perform: setup)
    }

    // MARK: - Buscar no GCP

    private var gcpForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Projeto GCP").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        TextField("id-do-projeto", text: $project)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(search)
                        Menu {
                            ForEach(projects, id: \.self) { p in
                                Button(p) {
                                    project = p
                                    search()
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 28)
                        .disabled(projects.isEmpty)
                        .help(projects.isEmpty ? "Carregando projetos…" : "Escolher projeto")
                    }
                }
                Button(action: search) {
                    Label("Buscar instâncias", systemImage: "magnifyingglass")
                }
                .disabled(project.trimmed.isEmpty || loading)
            }

            if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Consultando o GCP…").foregroundStyle(.secondary)
                }
            } else if let searchError {
                Text(searchError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else if searched && candidates.isEmpty {
                Text("Nenhuma instância Postgres encontrada neste projeto.")
                    .foregroundStyle(.secondary)
            }

            if !candidates.isEmpty {
                candidateTable
            }

            Spacer(minLength: 0)

            Text("Marque as instâncias que quer adicionar e, se quiser, quais ligam sozinhas ao abrir o app. A lista vem de gcloud sql instances list e só mostra instâncias Postgres. A porta sugerida é a próxima livre a partir de \(String(model.config.settings.startPort)).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var candidateTable: some View {
        VStack(spacing: 0) {
            CandidateRow {
                Text("")
            } name: {
                Text("INSTÂNCIA")
            } region: {
                Text("REGIÃO")
            } version: {
                Text("VERSÃO")
            } port: {
                Text("PORTA")
            } auto: {
                Text("AO ABRIR").help("Ligar automaticamente ao abrir o app")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.08))

            ScrollView {
                VStack(spacing: 0) {
                    ForEach($candidates) { $c in
                        Divider()
                        CandidateRow {
                            Toggle("", isOn: $c.selected)
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                .disabled(c.alreadyAdded)
                                .accessibilityLabel("Selecionar \(c.name)")
                        } name: {
                            HStack(spacing: 4) {
                                Text(c.name).fontWeight(.semibold)
                                if c.alreadyAdded {
                                    Text("(já adicionada)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .lineLimit(1)
                        } region: {
                            Text(c.region).foregroundStyle(.secondary)
                        } version: {
                            Text(c.version).foregroundStyle(.secondary)
                        } port: {
                            if c.alreadyAdded {
                                Text("—").foregroundStyle(.secondary)
                            } else {
                                TextField("", text: $c.port)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 70)
                                    .accessibilityLabel("Porta local de \(c.name)")
                            }
                        } auto: {
                            Toggle("", isOn: Binding(
                                get: { c.autoStart },
                                set: { value in
                                    c.autoStart = value
                                    if value { c.selected = true }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .disabled(c.alreadyAdded)
                            .help("Ligar \(c.name) automaticamente ao abrir o app")
                            .accessibilityLabel("Ligar \(c.name) automaticamente ao abrir o app")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .opacity(c.alreadyAdded ? 0.6 : 1)
                    }
                }
            }
            .frame(maxHeight: 250)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Manual

    private var manualForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Field(label: "Nome de exibição") {
                TextField("mls-dev", text: $name).textFieldStyle(.roundedBorder)
            }
            Field(label: "Connection name", hint: "Fica no console do Cloud SQL, em Visão geral → Nome da conexão.") {
                TextField("projeto:regiao:instancia", text: $connectionName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onChange(of: connectionName) { value in
                        let parts = value.split(separator: ":")
                        if name.trimmed.isEmpty, parts.count == 3 { name = String(parts[2]) }
                    }
            }
            HStack(alignment: .top, spacing: 12) {
                Field(label: "Porta local") {
                    TextField("", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
                .frame(width: 120)
                Field(label: "Banco padrão (opcional, usado na string copiada)") {
                    TextField("postgres", text: $database).textFieldStyle(.roundedBorder)
                }
            }
            Toggle("Usar IP privado (precisa de VPN)", isOn: $privateIP)
                .toggleStyle(.checkbox)
            Toggle("Ligar automaticamente ao abrir o app", isOn: $autoStart)
                .toggleStyle(.checkbox)
        }
    }

    // MARK: - Ações

    private var selectedCount: Int {
        candidates.filter { $0.selected && !$0.alreadyAdded }.count
    }

    private var isGcpMode: Bool { tab == .gcp && editing == nil }

    private var confirmTitle: String {
        if editing != nil { return "Salvar" }
        if isGcpMode {
            return selectedCount == 1 ? "Adicionar 1 instância" : "Adicionar \(selectedCount) instâncias"
        }
        return "Adicionar"
    }

    private var canConfirm: Bool {
        isGcpMode ? selectedCount > 0 : !connectionName.trimmed.isEmpty
    }

    private func setup() {
        if let id = model.editingID, let inst = model.instance(id) {
            editing = inst
            tab = .manual
            name = inst.name
            connectionName = inst.connectionName
            port = String(inst.port)
            database = inst.database
            privateIP = inst.privateIP
            autoStart = inst.autoStart
        } else {
            port = String(model.suggestedPorts(1).first ?? model.config.settings.startPort)
            project = model.config.settings.lastProject
            Task { projects = await model.listProjects() }
        }
    }

    private func search() {
        let p = project.trimmed
        guard !p.isEmpty, !loading else { return }
        loading = true
        searched = false
        searchError = nil
        candidates = []
        Task {
            do {
                let found = try await model.discover(project: p)
                let existing = Set(model.config.instances.map(\.connectionName))
                var ports = model.suggestedPorts(found.filter { !existing.contains($0.connectionName) }.count)
                candidates = found.map { d in
                    let added = existing.contains(d.connectionName)
                    let suggested = added || ports.isEmpty ? "" : String(ports.removeFirst())
                    return Candidate(
                        name: d.name,
                        connectionName: d.connectionName,
                        region: d.region ?? "",
                        version: d.prettyVersion,
                        alreadyAdded: added,
                        selected: false,
                        port: suggested
                    )
                }
                model.config.settings.lastProject = p
            } catch {
                searchError = error.localizedDescription
            }
            loading = false
            searched = true
        }
    }

    private func confirm() {
        validation = nil
        if isGcpMode {
            var used = Set(model.config.instances.map(\.port))
            var new: [ProxyInstance] = []
            for c in candidates where c.selected && !c.alreadyAdded {
                guard let p = Int(c.port.trimmed), (1...65535).contains(p) else {
                    validation = "Porta inválida para \(c.name)."
                    return
                }
                guard !used.contains(p) else {
                    validation = "A porta \(String(p)) já está em uso por outra instância."
                    return
                }
                used.insert(p)
                new.append(ProxyInstance(name: c.name, connectionName: c.connectionName, port: p, autoStart: c.autoStart))
            }
            model.add(new)
        } else {
            let cn = connectionName.trimmed
            let displayName = name.trimmed
            guard !displayName.isEmpty else {
                validation = "Informe um nome de exibição."
                return
            }
            guard cn.split(separator: ":").count == 3 else {
                validation = "O connection name deve ter o formato projeto:regiao:instancia."
                return
            }
            guard let p = Int(port.trimmed), (1...65535).contains(p) else {
                validation = "Porta inválida."
                return
            }
            if model.config.instances.contains(where: { $0.port == p && $0.id != editing?.id }) {
                validation = "A porta \(String(p)) já está em uso por outra instância."
                return
            }
            var inst = editing ?? ProxyInstance(name: displayName, connectionName: cn, port: p)
            inst.name = displayName
            inst.connectionName = cn
            inst.port = p
            inst.database = database.trimmed
            inst.privateIP = privateIP
            inst.autoStart = autoStart
            if editing == nil {
                model.add([inst])
            } else {
                model.update(inst)
            }
        }
        close()
    }

    private func close() {
        model.editingID = nil
        NSApp.keyWindow?.close()
    }
}

private struct CandidateRow<Check: View, Name: View, Region: View, Version: View, Port: View, Auto: View>: View {
    @ViewBuilder var check: Check
    @ViewBuilder var name: Name
    @ViewBuilder var region: Region
    @ViewBuilder var version: Version
    @ViewBuilder var port: Port
    @ViewBuilder var auto: Auto

    var body: some View {
        HStack(spacing: 8) {
            check.frame(width: 22, alignment: .leading)
            name.frame(maxWidth: .infinity, alignment: .leading)
            region.frame(width: 140, alignment: .leading)
            version.frame(width: 90, alignment: .leading)
            port.frame(width: 76, alignment: .leading)
            auto.frame(width: 64, alignment: .center)
        }
    }
}

private struct Field<Content: View>: View {
    let label: String
    var hint: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content
            if let hint {
                Text(hint).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
