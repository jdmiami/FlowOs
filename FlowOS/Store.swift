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
    private let brain = LocalBrain()
    private let folder = URL.applicationSupportDirectory.appending(path: "FlowOS", directoryHint: .isDirectory)
    init() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        apps = load("apps") ?? []; workflows = load("workflows") ?? []; chat = load("chat") ?? []
        notes = UserDefaults.standard.string(forKey: "notes") ?? ""
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
    func send(_ input: String, mode: String = "chat") async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        chat.append(ChatLine(user: true, text: text))
        guard let model else { chat.append(ChatLine(user: false, text: "Import a compatible LiteRT-LM model in Settings first. No cloud fallback is used.")); return }
        busy = true; defer { busy = false }
        do {
            let prompt: String
            if mode == "app" { prompt = "Return only JSON with action app, title string, fields array of unique short strings. Design a simple record tracking app for: \(text)" }
            else if mode == "workflow" { prompt = "Return only JSON with action workflow, title string, steps array of short human-readable steps. Design a workflow for: \(text)" }
            else { prompt = "You are a private local assistant. Do not claim to execute actions. Answer this conversation concisely:\n" + chat.suffix(6).map { ($0.user ? "User: " : "Assistant: ") + String($0.text.prefix(800)) }.joined(separator: "\n") }
            let result = try await brain.ask(prompt, model: model)
            if mode == "chat" { chat.append(ChatLine(user: false, text: result)) }
            else if let start = result.firstIndex(of: "{"), let end = result.lastIndex(of: "}"), start <= end, let plan = try? JSONDecoder().decode(Plan.self, from: Data(result[start...end].utf8)), (mode == "app" ? Validation.miniApp(plan) != nil : Validation.workflow(plan) != nil) {
                pending = plan
                chat.append(ChatLine(user: false, text: "Draft ready for review: \(plan.title ?? "Untitled")"))
            } else { chat.append(ChatLine(user: false, text: "The model did not return a valid definition. Try a simpler request.")) }
        } catch { chat.append(ChatLine(user: false, text: "Local inference failed: \(error.localizedDescription)")) }
    }
    func approve() {
        guard let pending else { return }
        if let app = Validation.miniApp(pending) { apps.append(app) }
        else if let workflow = Validation.workflow(pending) { workflows.append(workflow) }
        self.pending = nil
    }
}
