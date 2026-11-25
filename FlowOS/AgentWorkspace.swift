import UIKit
import SwiftUI
import UniformTypeIdentifiers

struct AgentProgressView: View {
    @EnvironmentObject var store: Store
    @State private var expanded = true
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        if store.busy || !store.activity.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: store.busy ? "waveform.circle.fill" : "checkmark.circle")
                        .font(.title2).foregroundStyle(Palette.ink)
                        .contentTransition(.symbolEffect(.replace))
                    Text(store.stage).font(.subheadline.weight(.semibold)).contentTransition(.opacity)
                    Spacer()
                    if store.busy { Button("Stop", role: .cancel) { store.stop() }.font(.caption) }
                }
                DisclosureGroup("Agent activity", isExpanded: $expanded) {
                    ForEach(Array(store.activity.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "smallcircle.filled.circle").font(.caption).foregroundStyle(Palette.ink.opacity(0.65))
                            Text(item).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.vertical, 4)
                    }
                }.font(.caption)
                if store.busy {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(store.live.isEmpty ? "Waiting for model output…" : "\(store.live.utf8.count) bytes generated").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if !store.live.isEmpty {
                        Text(store.live).font(store.activeMode == "chat" ? .body : .system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12).background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }.glass()
                .animation(reduced ? .easeOut(duration: 0.12) : FlowMotion.snap, value: store.stage)
        }
    }
}
struct ArtifactLibrary: View {
    @EnvironmentObject var store: Store
    var kind: String? = nil
    @State private var selected: Artifact?
    @State private var search = ""
    @State private var filter = "all"
    var filtered: [Artifact] { store.artifacts.filter { item in
        (kind == nil || item.kind == kind) && (filter == "all" || (filter == "ready" ? item.plan != nil && item.installedID == nil : item.installedID != nil)) && (search.isEmpty || item.title.localizedCaseInsensitiveContains(search))
    } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Artifacts").font(.title2.bold()); Spacer(); Text("\(filtered.count)").font(.caption) }
            if !store.artifacts.isEmpty {
                HStack { Image(systemName: "magnifyingglass"); TextField("Search artifacts", text: $search) }.padding(12).liquidSurface(radius: 22)
                FlowModePicker(selection: $filter, options: [("all", "All"), ("ready", "Ready"), ("installed", "Installed")])
            }
            if filtered.isEmpty { Text("No matching artifacts. Generated apps, workflows and drafts appear here.").font(.caption).foregroundStyle(.secondary) }
            ForEach(filtered) { artifact in
                Button { selected = artifact } label: {
                    HStack(spacing: 12) {
                        Image(systemName: artifact.kind == "app" ? "square.stack" : artifact.kind == "theme" ? "paintpalette" : "point.3.connected.trianglepath.dotted").font(.title2)
                            .frame(width: 50, height: 50).background((artifact.kind == "app" ? Palette.lavender : Palette.mint).opacity(0.48), in: RoundedRectangle(cornerRadius: 18))
                        VStack(alignment: .leading) {
                            Text(artifact.title).font(.headline)
                            Text(artifact.state).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }.glass()
                }.buttonStyle(FlowPress())
            }
        }.sheet(item: $selected) { artifact in ArtifactDetail(id: artifact.id).environmentObject(store).presentationDragIndicator(.visible).presentationCornerRadius(36) }
    }
}
struct ArtifactDetail: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @Environment(\.accessibilityReduceMotion) private var reduced
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
                        FlowModePicker(selection: $tab, options: [("Preview", "Preview"), ("Code", "Code"), ("Details", "Details")])
                        if tab == "Preview" {
                            if let plan = artifact.plan {
                                if artifact.kind == "app", let fields = plan.fields {
                                    Text("Interactive sandbox").font(.headline)
                                    Text("Sample records are temporary until you install the app.").font(.caption)
                                    GeneratedDashboard(rows:rows,components:plan.components ?? [])
                                    VStack(alignment: .leading, spacing: 12) {
                                        GeneratedFields(fields:fields,components:plan.components ?? [],draft:$draft)
                                        Button("Add sample record") { rows.append(draft); draft = [:] }.buttonStyle(FlowPrimary()).disabled(draft.values.allSatisfy(\.isEmpty))
                                    }.glass()
                                    ForEach(rows.indices, id: \.self) { i in VStack(alignment: .leading) { ForEach(fields, id: \.self) { field in Text("\(field): \(rows[i][field, default: ""])") } }.glass() }
                                } else if let theme = plan.theme, theme.isValid {
                                    VStack(alignment:.leading,spacing:10) {
                                        Text(theme.name).font(.title2)
                                        HStack(spacing:0) { ForEach([theme.primary,theme.secondary,theme.accent],id:\.self) { hex in Color(flowHex:hex).frame(height:85) } }.clipShape(RoundedRectangle(cornerRadius:20))
                                        Button("Apply theme") { store.applyTheme(theme); FlowFeedback.shared.play(true) }.buttonStyle(FlowPrimary())
                                    }.glass()
                                } else {
                                    Text("Workflow preview · manual checklist").font(.headline)
                                    ForEach(Array((plan.steps ?? []).enumerated()), id: \.offset) { i, step in
                                        Button { if checked.contains(i) { checked.remove(i) } else { checked.insert(i) } } label: { Label(step, systemImage: checked.contains(i) ? "checkmark.circle.fill" : "circle") }.buttonStyle(.plain).glass()
                                    }
                                }
                            } else { Text("This draft is incomplete or invalid. Inspect the code and retry creation.").glass() }
                        } else if tab == "Code" {
                            Text("Generated app definition · JSON").font(.headline)
                            ScrollView(.horizontal) { Text(artifact.source).font(.system(.caption, design: .monospaced)).textSelection(.enabled).foregroundStyle(Color.white.opacity(0.95)).fixedSize(horizontal: true, vertical: false) }.padding(16).background(Palette.ink, in: RoundedRectangle(cornerRadius: 23))
                            Button("Copy source") { UIPasteboard.general.string = artifact.source }.buttonStyle(.bordered)
                            Button("Export source") { export = true }.buttonStyle(.bordered)
                            Text(exportStatus).font(.caption)
                        } else {
                            Text("Original request").font(.headline); Text(artifact.request).glass()
                            Text(artifact.created.formatted()).font(.caption)
                        }
                        if artifact.plan != nil && artifact.installedID == nil {
                            Button(artifact.kind == "theme" ? "Save & apply theme" : "Install in my library") { store.install(id) }.buttonStyle(FlowPrimary())
                        }
                        VStack(alignment: .leading) {
                            TextField("Describe a change or retry", text: $revision, axis: .vertical)
                            Button("Generate new revision") {
                                store.start(artifact.request + "\nRevision: " + revision, mode: artifact.kind)
                                dismiss()
                            }.disabled(store.busy || revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }.glass()
                    }.padding(20)
                }.background { FlowBackdrop(tab: 2, busy: store.busy) }.navigationTitle("Artifact").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                    .fileExporter(isPresented: $export, document: SourceDocument(text: artifact.source), contentType: .plainText, defaultFilename: "FlowOS-\(artifact.id.uuidString).txt") { result in
                        switch result { case .success: exportStatus = "Exported"; case .failure(let error): exportStatus = error.localizedDescription }
                    }
            } else { Text("Artifact unavailable") }
        }
    }
}
struct SourceDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .html] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
