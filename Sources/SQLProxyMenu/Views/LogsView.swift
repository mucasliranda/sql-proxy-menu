import AppKit
import SwiftUI

struct LogsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(model.config.instances, selection: $model.logsSelection) { inst in
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.status(inst.id).color)
                        .frame(width: 8, height: 8)
                    Text(inst.name)
                }
                .tag(inst.id)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            if let id = model.logsSelection, let inst = model.instance(id) {
                LogDetail(instance: inst)
            } else {
                Text(model.config.instances.isEmpty ? "Nenhuma instância cadastrada" : "Selecione uma instância")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .onAppear {
            if model.logsSelection == nil {
                model.logsSelection = model.config.instances.first?.id
            }
        }
    }
}

private struct LogDetail: View {
    @EnvironmentObject var model: AppModel
    let instance: ProxyInstance

    private var lines: [String] { model.logs[instance.id] ?? [] }
    private var fileURL: URL { LogFiles.url(for: instance.name) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if lines.isEmpty {
                            Text("Sem saída ainda. Ligue o proxy para ver os logs aqui.")
                                .foregroundStyle(Color(white: 0.55))
                        }
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .foregroundStyle(color(for: line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(14)
                }
                .background(Color(red: 0.11, green: 0.114, blue: 0.13))
                .onChange(of: lines.count) { count in
                    if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
                .onAppear {
                    if !lines.isEmpty { proxy.scrollTo(lines.count - 1, anchor: .bottom) }
                }
            }

            Divider()

            HStack {
                Text(footer)
                Spacer()
                Text(Paths.display(fileURL)).textSelection(.enabled)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .navigationTitle("Logs — \(instance.name)")
        .toolbar {
            ToolbarItemGroup {
                Button("Copiar") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
                }
                Button("Limpar") { model.clearLogs(instance.id) }
                Button("Mostrar no Finder") {
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    } else {
                        Paths.ensure(Paths.logs)
                        NSWorkspace.shared.open(Paths.logs)
                    }
                }
            }
        }
    }

    private var footer: String {
        guard let pid = model.pid(instance.id) else { return model.status(instance.id).label.capitalized }
        let since = model.startedAt(instance.id).map {
            $0.formatted(date: .omitted, time: .shortened)
        } ?? "—"
        return "Ativo desde \(since) · PID \(String(pid))"
    }

    private func color(for line: String) -> Color {
        let lower = line.lowercased()
        if line.hasPrefix("$ ") || line.hasPrefix("— ") { return Color(white: 0.55) }
        if lower.contains("ready for new connections") { return Color(red: 0.5, green: 0.88, blue: 0.65) }
        if lower.contains("error") || lower.contains("invalid") || lower.contains("failed") {
            return Color(red: 1, green: 0.5, blue: 0.5)
        }
        return Color(white: 0.85)
    }
}
