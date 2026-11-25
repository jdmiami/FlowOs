import UIKit
import SwiftUI
import UniformTypeIdentifiers

struct AgentProgressView: View {
    @EnvironmentObject var store: Store
    @State private var expanded = true
    var body: some View {
        if store.busy || !store.activity.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if store.busy { ProgressView().controlSize(.small) }
                    Text(store.stage).font(.subheadline.weight(.semibold))
                    Spacer()
                    if store.busy { Button("Stop", role: .cancel) { store.stop() }.font(.caption) }
                }
                DisclosureGroup("Agent activity", isExpanded: $expanded) {
                    ForEach(Array(store.activity.enumerated()), id: \.offset) { _, item in
                        Label(item, systemImage: "circle.fill").font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                    }
                }.font(.caption)
                if store.busy {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(store.live.isEmpty ? "Waiting for model output…" : "\(store.live.utf8.count) bytes generated").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if !store.live.isEmpty {
                        Text(store.live).font(store.activeMode == "chat" ? .body : .system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.glass()
        }
    }
}
struct ArtifactLibrary: View {
    @EnvironmentObject var store: Store
    var kind: String? = nil
    @State private var selected: Artifact?
    var filtered: [Artifact] { store.artifacts.filter { kind == nil || $0.kind == kind } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Artifacts").font(.title2.bold()); Spacer(); Text("\(filtered.count)").font(.caption) }
            if filtered.isEmpty { Text("Generated apps, workflows and drafts appear here.").font(.caption).foregroundStyle(.secondary) }
            ForEach(filtered) { artifact in
                Button { selected = artifact } label: {
                    HStack(spacing: 12) {
                        Image(systemName: artifact.kind == "app" ? "square.stack" : "point.3.connected.trianglepath.dotted").font(.title2)
                        VStack(alignment: .leading) {
                            Text(artifact.title).font(.headline)
                            Text(artifact.state).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }.glass()
                }.buttonStyle(.plain)
            }
        }.sheet(item: $selected) { artifact in ArtifactDetail(id: artifact.id).environmentObject(store) }
    }
}
struct ArtifactDetail: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var tab = "Preview"
    @State private var draft: [String: String] = [:]
    @State private var rows: [[String: String]] = []
    @State private var checked: Set<Int> = []
    @State private var revision = ""
    @State private var export = false
    @State private var exportStatus = ""
    var artifact: Artifact? { store.artifacts.first { $0.id == id } }
    var body: some View {
        NavigationStack {
            if let artifact {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(artifact.title).font(.system(.largeTitle, design: .serif))
                        Text(artifact.state).font(.caption)
                        Picker("Workspace", selection: $tab) { ForEach(["Preview", "Code", "Details"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                        if tab == "Preview" {
                            if let plan = artifact.plan {
                                if artifact.kind == "app", let fields = plan.fields {
                                    Text("Interactive sandbox").font(.headline)
                                    Text("Sample records are temporary until you install the app.").font(.caption)
                                    VStack(alignment: .leading, spacing: 12) {
                                        ForEach(fields, id: \.self) { field in
                                            TextField(field, text: Binding(get: { draft[field, default: ""] }, set: { draft[field] = $0 })).textFieldStyle(.roundedBorder)
                                        }
                                        Button("Add sample record") { rows.append(draft); draft = [:] }.buttonStyle(.borderedProminent).disabled(draft.values.allSatisfy(\.isEmpty))
                                    }.glass()
                                    ForEach(rows.indices, id: \.self) { i in VStack(alignment: .leading) { ForEach(fields, id: \.self) { field in Text("\(field): \(rows[i][field, default: ""])") } }.glass() }
                                } else {
                                    Text("Workflow preview · manual checklist").font(.headline)
                                    ForEach(Array((plan.steps ?? []).enumerated()), id: \.offset) { i, step in
                                        Button { if checked.contains(i) { checked.remove(i) } else { checked.insert(i) } } label: { Label(step, systemImage: checked.contains(i) ? "checkmark.circle.fill" : "circle") }.buttonStyle(.plain).glass()
                                    }
                                }
                            } else { Text("This draft is incomplete or invalid. Inspect the code and retry creation.").glass() }
                        } else if tab == "Code" {
                            Text("Generated app definition · JSON").font(.headline)
                            Text(artifact.source).font(.system(.caption, design: .monospaced)).textSelection(.enabled).glass()
                            Button("Copy source") { UIPasteboard.general.string = artifact.source }.buttonStyle(.bordered)
                            Button("Export source") { export = true }.buttonStyle(.bordered)
                            Text(exportStatus).font(.caption)
                        } else {
                            Text("Original request").font(.headline); Text(artifact.request).glass()
                            Text(artifact.created.formatted()).font(.caption)
                        }
                        if artifact.plan != nil && artifact.installedID == nil {
                            Button("Install in my library") { store.install(id) }.buttonStyle(.borderedProminent)
                        }
                        VStack(alignment: .leading) {
                            TextField("Describe a change or retry", text: $revision, axis: .vertical)
                            Button("Generate new revision") {
                                store.start(artifact.request + "\nRevision: " + revision, mode: artifact.kind)
                                dismiss()
                            }.disabled(store.busy || revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }.glass()
                    }.padding(20)
                }.navigationTitle("Artifact").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                    .fileExporter(isPresented: $export, document: SourceDocument(text: artifact.source), contentType: .plainText, defaultFilename: "FlowOS-\(artifact.id.uuidString).txt") { result in
                        switch result { case .success: exportStatus = "Exported"; case .failure(let error): exportStatus = error.localizedDescription }
                    }
            } else { Text("Artifact unavailable") }
        }
    }
}
struct SourceDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
