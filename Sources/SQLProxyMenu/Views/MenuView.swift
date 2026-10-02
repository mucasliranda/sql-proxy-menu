import AppKit
import SwiftUI

struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header

            if model.proxyPath == nil {
                Banner(
                    icon: "wrench.and.screwdriver",
                    title: "cloud-sql-proxy não encontrado",
                    message: "Instale com brew install cloud-sql-proxy ou informe o caminho nas Preferências."
                ) {
                    Button("Verificar de novo") { model.refreshTools() }
                }
            }

            if model.credentialExpired {
                Banner(
                    icon: "exclamationmark.triangle",
                    title: "Credencial expirada",
                    message: "Os proxies continuam ligados, mas novas conexões vão falhar até você entrar de novo."
                ) {
                    if model.reauthInProgress {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Aguardando login no navegador…").font(.caption)
                        }
                    } else {
                        Button("Reautenticar no Google") { model.reauth() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
            }

            MenuDivider()

            if model.config.instances.isEmpty {
                Text("Nenhuma instância cadastrada.\nUse “Adicionar instância…” para começar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                ForEach(model.config.instances) { inst in
                    InstanceRow(instance: inst)
                }
            }

            MenuDivider()

            MenuItem(title: "Adicionar instância…", shortcut: "⌘N") { open(WindowID.add) }
                .keyboardShortcut("n")
            MenuItem(title: "Parar todos", shortcut: "⇧⌘S") { model.stopAll() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.activeCount == 0)

            MenuDivider()

            MenuItem(title: "Ver logs…", shortcut: "⌘L") { open(WindowID.logs) }
                .keyboardShortcut("l")
            MenuItem(title: "Preferências…", shortcut: "⌘,") { open(WindowID.prefs) }
                .keyboardShortcut(",")
            MenuItem(title: "Sair do SQL Proxy Menu", shortcut: "⌘Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(6)
        .frame(width: 370)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("SQL Proxy Menu").font(.headline)
                Spacer()
                Text("\(model.activeCount) de \(model.config.instances.count) ativos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Image(systemName: credentialIcon)
                    .foregroundStyle(credentialColor)
                    .font(.caption2.weight(.bold))
                Text(accountLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var accountLine: String {
        if model.gcloudPath == nil { return "gcloud não encontrado" }
        let who = model.account.isEmpty ? "conta não detectada" : model.account
        let state: String
        switch model.credentialValid {
        case nil: state = "verificando…"
        case .some(true) where !model.credentialExpired: state = "credencial válida"
        default: state = "credencial expirada"
        }
        return "\(who) · \(state)"
    }

    private var credentialIcon: String {
        switch model.credentialValid {
        case nil: "clock"
        case .some(true) where !model.credentialExpired: "checkmark"
        default: "exclamationmark.triangle.fill"
        }
    }

    private var credentialColor: Color {
        switch model.credentialValid {
        case nil: .secondary
        case .some(true) where !model.credentialExpired: .green
        default: .orange
        }
    }

    private func open(_ id: String) {
        if id == WindowID.add { model.prepareEditor(for: nil) }
        openWindow(id: id)
        bringToFront()
    }
}

struct InstanceRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    let instance: ProxyInstance

    @State private var copied = false
    @State private var hover = false

    private var status: ProxyStatus { model.status(instance.id) }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(status.color)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(instance.name).fontWeight(.semibold)
                    Text(copied ? "conexão copiada" : status.label)
                        .font(.caption)
                        .foregroundStyle(copied ? Color.accentColor : status.textColor)
                }
                Text(instance.connectionName)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if case .error(let message) = status {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 4)

            Text(":" + String(instance.port))
                .font(.system(size: 11.5, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.15)))

            IconButton(
                systemName: "doc.on.doc",
                help: "Copiar string de conexão",
                detail: model.connectionString(instance)
            ) {
                copy(model.connectionString(instance))
            }
            IconButton(
                systemName: status.isActive ? "stop.fill" : "play.fill",
                tint: status.isActive ? .primary : .green,
                help: (status.isActive ? "Parar " : "Iniciar ") + instance.name
            ) {
                model.toggle(instance.id)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 7).fill(hover ? Color.secondary.opacity(0.08) : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .zIndex(hover ? 1 : 0)
        .contextMenu {
            Button("Editar…") {
                model.prepareEditor(for: instance.id)
                openWindow(id: WindowID.add)
                bringToFront()
            }
            Button("Ver logs") {
                model.logsSelection = instance.id
                openWindow(id: WindowID.logs)
                bringToFront()
            }
            Button("Copiar string de conexão") { copy(model.connectionString(instance)) }
            Button("Copiar connection name") { copy(instance.connectionName) }
            Divider()
            Button("Remover", role: .destructive) { model.remove(instance.id) }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}

struct MenuItem: View {
    let title: String
    let shortcut: String
    let action: () -> Void

    @State private var hover = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let highlighted = hover && isEnabled
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(shortcut)
                    .foregroundStyle(highlighted ? Color.white.opacity(0.85) : Color.secondary)
            }
            .foregroundStyle(highlighted ? Color.white : (isEnabled ? Color.primary : Color.secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(highlighted ? Color.accentColor : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Botão só com ícone. O tooltip é desenhado pelo próprio app porque o `.help`
/// nativo não aparece dentro do painel da barra de menu.
struct IconButton: View {
    let systemName: String
    var tint: Color = .primary
    let help: String
    var detail: String?
    let action: () -> Void

    @State private var hover = false
    @State private var showTip = false
    @State private var tipTask: DispatchWorkItem?

    var body: some View {
        Button {
            hideTip()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Color.secondary.opacity(0.18) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { inside in
            hover = inside
            if inside {
                let task = DispatchWorkItem { showTip = true }
                tipTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
            } else {
                hideTip()
            }
        }
        .overlay(alignment: .topTrailing) {
            if showTip {
                Tooltip(title: help, detail: detail)
                    .alignmentGuide(.top) { d in d[.bottom] + 4 }
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: showTip)
    }

    private func hideTip() {
        tipTask?.cancel()
        tipTask = nil
        showTip = false
    }
}

private struct Tooltip: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.disabled)
            }
        }
        .frame(width: detail == nil ? nil : 290, alignment: .leading)
        .fixedSize(horizontal: detail == nil, vertical: true)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 1)
        )
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
    }
}

struct Banner<Actions: View>: View {
    let icon: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            actions
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }
}

struct MenuDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 8).padding(.vertical, 4)
    }
}
