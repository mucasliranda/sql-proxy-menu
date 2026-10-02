import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    @State private var startPort = ""
    @State private var launchAtLogin = false
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Conta Google") {
                LabeledContent("Conta") {
                    Text(model.account.isEmpty ? "—" : model.account).textSelection(.enabled)
                }
                LabeledContent("Credencial (ADC)") {
                    HStack(spacing: 8) {
                        credentialText
                        Button("Verificar") { Task { await model.refreshCredential() } }
                        Button(model.reauthInProgress ? "Aguardando navegador…" : "Reautenticar") {
                            model.reauth()
                        }
                        .disabled(model.reauthInProgress || model.gcloudPath == nil)
                    }
                }
                if model.gcloudPath == nil {
                    Text("gcloud não encontrado. Instale com: brew install --cask google-cloud-sdk")
                        .foregroundStyle(.red)
                }
            }

            Section("cloud-sql-proxy") {
                LabeledContent("Binário") {
                    Text(binaryText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(model.proxyPath == nil ? .red : .secondary)
                        .textSelection(.enabled)
                }
                TextField("Caminho personalizado", text: $model.config.settings.proxyPathOverride, prompt: Text("detectar automaticamente"))
                    .onSubmit { model.refreshTools() }
                Toggle("Autenticação IAM automática (--auto-iam-authn)", isOn: $model.config.settings.autoIAMAuthn)
                TextField("Porta inicial para novas instâncias", text: $startPort)
                    .onChange(of: startPort) { value in
                        if let p = Int(value.trimmed), (1024...65535).contains(p) {
                            model.config.settings.startPort = p
                        }
                    }
            }

            Section("Instâncias") {
                if model.config.instances.isEmpty {
                    Text("Nenhuma instância cadastrada.").foregroundStyle(.secondary)
                }
                ForEach(model.config.instances) { inst in
                    HStack {
                        Text(inst.name)
                        Text(":" + String(inst.port))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle("Ligar ao abrir", isOn: Binding(
                            get: { inst.autoStart },
                            set: { model.setAutoStart(inst.id, $0) }
                        ))
                        .toggleStyle(.checkbox)
                        Button("Editar") {
                            model.prepareEditor(for: inst.id)
                            openWindow(id: WindowID.add)
                            bringToFront()
                        }
                        Button("Remover", role: .destructive) { model.remove(inst.id) }
                    }
                }
            }

            Section("Geral") {
                Toggle("Abrir ao iniciar sessão no Mac", isOn: Binding(
                    get: { launchAtLogin },
                    set: { value in
                        loginError = model.setLaunchAtLogin(value)
                        launchAtLogin = model.launchAtLogin
                    }
                ))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Notificar quando um proxy cair", isOn: $model.config.settings.notifyOnCrash)
                Toggle("Notificar quando a credencial expirar", isOn: $model.config.settings.notifyOnCredentialExpired)
                Text("Ao sair do app, todos os proxies são encerrados.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 640)
        .onAppear {
            startPort = String(model.config.settings.startPort)
            launchAtLogin = model.launchAtLogin
        }
    }

    private var binaryText: String {
        guard let path = model.proxyPath else { return "não encontrado" }
        return model.proxyVersion.isEmpty ? path : "\(path) · v\(model.proxyVersion)"
    }

    @ViewBuilder
    private var credentialText: some View {
        switch model.credentialValid {
        case nil:
            Text("verificando…").foregroundStyle(.secondary)
        case .some(true) where !model.credentialExpired:
            Label("válida", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        default:
            Label("expirada", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}
