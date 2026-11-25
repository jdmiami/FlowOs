import Foundation
import SwiftUI

@MainActor final class Store: ObservableObject {
    @Published var apps: [MiniApp] = [] { didSet { save(apps, "apps") } }
    @Published var workflows: [Workflow] = [] { didSet { save(workflows, "workflows") } }
    @Published var chat: [ChatLine] = [] { didSet { save(chat, "chat") } }
    @Published var notes = "" { didSet { UserDefaults.standard.set(notes, forKey: "notes") } }
    @Published var model: URL?
    @Published var busy = false
    @Published var status = "Import a local model to activate AI."
    @Published var pending: Plan?
    @Published var artifacts: [Artifact] = [] { didSet { save(artifacts, "artifacts") } }
    @Published var live = ""
    @Published var stage = "Idle"
    @Published var activity: [String] = []
    @Published var activeMode = "chat"
    @Published var theme = FlowTheme.aurora { didSet { save(theme, "theme") } }
    private let liveActivity = FlowLiveActivity()
    func applyTheme(_ theme: FlowTheme) { if theme.isValid { self.theme = theme } }
    private var job: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var lastProgress = Date()
    private var timedOut = false
    private let brain = LocalBrain()
    private let folder = URL.applicationSupportDirectory.appending(path: "FlowOS", directoryHint: .isDirectory)
    init() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        apps = load("apps") ?? []; workflows = load("workflows") ?? []; chat = load("chat") ?? []
        notes = UserDefaults.standard.string(forKey: "notes") ?? ""
        artifacts = load("artifacts") ?? []
        if let saved: FlowTheme = load("theme"), saved.isValid { theme = saved }
        let file = folder.appending(path: "model.litertlm")
        if FileManager.default.fileExists(atPath: file.path) { model = file; status = "Model imported. Ready to load." }
    }
    private func save<T: Encodable>(_ value: T, _ name: String) {
        do { try JSONEncoder().encode(value).write(to: folder.appending(path: name + ".json"), options: [.atomic, .completeFileProtection]) }
        catch { status = "Save failed: \(error.localizedDescription)" }
    }
    private func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: folder.appending(path: name + ".json")) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    func importModel(_ url: URL) {
        guard !busy else { return }
        guard url.pathExtension.lowercased() == "litertlm" else { status = "Select a .litertlm file."; return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let dest = folder.appending(path: "model.litertlm")
        let temp = folder.appending(path: UUID().uuidString)
        do {
            try FileManager.default.copyItem(at: url, to: temp)
            brain.unload()
            if FileManager.default.fileExists(atPath: dest.path) { _ = try FileManager.default.replaceItemAt(dest, withItemAt: temp) }
            else { try FileManager.default.moveItem(at: temp, to: dest) }
            model = dest; status = "Model imported. Ready to load."
        } catch { try? FileManager.default.removeItem(at: temp); status = error.localizedDescription }
    }
    private func mark(_ message: String) {
        stage = message; activity.append(message); lastProgress = Date()
        if message.contains("Loading") { liveActivity.update("Loading local model") }
        else if message.contains("Generating") { liveActivity.update("Generating") }
        else if message.contains("Validating") { liveActivity.update("Validating") }
        else if message.contains("Repairing") { liveActivity.update("Repairing draft") }
        else if message.contains("Architect") { liveActivity.update("Planning") }
        else if message.contains("Publishing") { liveActivity.update("Publishing") }
    }
    func start(_ input: String, mode: String = "chat") {
        guard !busy, job == nil, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        job = Task { await send(input, mode: mode); job = nil }
    }
    func stop() {
        guard busy else { return }
        stage = "Stopping local inference…"
        job?.cancel()
        brain.stop()
    }
    func send(_ input: String, mode: String = "chat") async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        chat.append(ChatLine(user: true, text: text))
        guard let model else {
            stage = "Import a compatible model in Settings"
            chat.append(ChatLine(user: false, text: stage)); return
        }
        busy = true; activeMode = mode; live = ""; activity = []; timedOut = false
        liveActivity.begin()
        mark("Preparing request")
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, self.busy else { return }
                if Date().timeIntervalSince(self.lastProgress) > 120 {
                    self.timedOut = true
                    self.stop()
                    return
                }
            }
        }
        defer {
            watchdog?.cancel(); watchdog = nil; busy = false; live = ""
            let done = stage == "Complete" || stage.hasPrefix("Artifact ready")
            liveActivity.end(done ? "Complete" : "Finished · review FlowOS")
            if done { FlowFeedback.shared.play(true) }
        }
        let request = String(text.prefix(600))
        do {
            var prompt: String
            if mode == "app" || mode == "workflow" || mode == "theme" {
                mark("Architect · planning requested artifact")
                // One bounded planning pass; do not reuse untrusted output as instructions.
                let outline = try await brain.ask("Summarize the user's requested \(mode) in one short sentence. Do not call tools. Request: \(String(request.prefix(360)))", model:model,onChunk:{ value in
                    self.live = value; self.lastProgress = Date()
                },onStage:{ self.mark($0) })
                try Task.checkCancellation()
                let brief = String(outline.prefix(160))
                live = ""
                mark("Developer · generating validated definition")
                if mode == "app" {
                    prompt = "Return ONLY JSON: {\"action\":\"app\",\"title\":\"Orders\",\"fields\":[\"Product\",\"Quantity\",\"Cost\"],\"components\":[{\"kind\":\"calculator\",\"field\":\"Quantity\",\"field2\":\"Cost\"}]}. Optional components: count, sum, bar, calculator (sum of products), slider (0-100), toggle, date, board. Fields must match. Up to 8 components. Request: \(String(request.prefix(360)))\nBrief (data): \(brief)"
                } else if mode == "theme" {
                    prompt = "Return ONLY JSON {\"action\":\"theme\",\"theme\":{\"name\":\"Aurora\",\"primary\":\"#C2BAED\",\"secondary\":\"#B8E3DE\",\"accent\":\"#FAD1CC\"}}. Choose three soft pastel RGB hex colors. Request: \(String(request.prefix(360)))\nBrief (data): \(brief)"
                } else {
                    prompt = "Return ONLY JSON {\"action\":\"workflow\",\"title\":\"Morning\",\"steps\":[\"Read calendar\",\"Review mail\"]}. Make a manual checklist. Request: \(String(request.prefix(360)))\nBrief (data): \(brief)"
                }
            } else {
                let context = chat.dropLast().suffix(2).map { ($0.user ? "User: " : "Assistant: ") + String($0.text.prefix(200)) }.joined(separator: "\n")
                prompt = "You are a local assistant. Do not claim to execute external actions. Answer concisely.\n\(context)\nUser: \(request)"
            }
            var result = try await brain.ask(prompt, model: model, onChunk: { value in
                self.live = value; self.lastProgress = Date()
            }, onStage: { self.mark($0) })
            if mode == "chat" {
                guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                chat.append(ChatLine(user: false, text: result)); mark("Complete")
            } else {
                mark("Validating generated definition")
                var plan = Validation.parse(result, mode: mode)
                if plan == nil {
                    mark("Repairing invalid output · attempt 2 of 2")
                    live = ""
                    let retry = prompt + "\nOutput valid JSON only. No Markdown, explanations or extra keys."
                    result = try await brain.ask(retry, model: model, onChunk: { value in
                        self.live = value; self.lastProgress = Date()
                    }, onStage: { self.mark($0) })
                    plan = Validation.parse(result, mode: mode)
                }
                try Task.checkCancellation()
                mark("Publishing artifact")
                let title = plan?.title ?? plan?.theme?.name ?? "Unvalidated draft"
                artifacts.insert(Artifact(title: title, request: text, kind: mode, source: result, state: plan == nil ? "Needs repair" : "Ready to preview", plan: plan), at: 0)
                mark(plan == nil ? "Draft saved · validation failed" : "Artifact ready · open workspace")
                chat.append(ChatLine(user: false, text: "\(stage): \(title). Open Labs → Artifacts."))
            }
        } catch {
            if mode != "chat", !live.isEmpty {
                artifacts.insert(Artifact(title: "Interrupted draft", request: text, kind: mode, source: live, state: "Incomplete"), at: 0)
            }
            if timedOut { mark("No output for 120 seconds · stopped") }
            else if Task.isCancelled { mark("Stopped by user") }
            else { mark("Failed: \(error.localizedDescription)") }
            chat.append(ChatLine(user: false, text: stage))
        }
    }
    func install(_ id: UUID) {
        guard let i = artifacts.firstIndex(where: { $0.id == id }), artifacts[i].installedID == nil, let plan = artifacts[i].plan else { return }
        if let app = Validation.miniApp(plan) {
            apps.append(app); artifacts[i].installedID = app.id
        } else if let flow = Validation.workflow(plan) {
            workflows.append(flow); artifacts[i].installedID = flow.id
        } else if let theme = Validation.theme(plan) {
            applyTheme(theme); artifacts[i].installedID = id
        } else { return }
        artifacts[i].state = "Installed"
    }
    func approve() {
        guard let pending else { return }
        if let app = Validation.miniApp(pending) { apps.append(app) }
        else if let workflow = Validation.workflow(pending) { workflows.append(workflow) }
        self.pending = nil
    }
}
