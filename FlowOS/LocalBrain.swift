import Foundation
import LiteRTLM

@MainActor final class LocalBrain {
    private var engine: Engine?
    private var path: String?
    private var cache: URL?
    private var active: Conversation?
    func stop() { try? active?.cancel() }

    func unload() {
        engine = nil
        path = nil
        if let cache { try? FileManager.default.removeItem(at: cache) }
        cache = nil
    }

    private func initialize(model: URL) async throws {
        // Isolate compiled GPU caches across model imports and runtime revisions.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowOS-Metal-v020-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cache = directory
        do {
            let config = try EngineConfig(modelPath: model.path, backend: .gpu,
                maxNumTokens: 1024, cacheDir: directory.path)
            let newEngine = Engine(engineConfig: config)
            try await newEngine.initialize()
            engine = newEngine
            path = model.path
        } catch {
            unload()
            let detail = error.localizedDescription
            if detail.contains("kPingPong") || detail.contains("kv_cache") {
                throw NSError(domain: "FlowOS.Metal", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Metal could not initialize this model's KV cache. Import a LiteRT-LM model validated for native iOS GPU inference (not a WebGPU-only export). CPU fallback is disabled. Runtime: 0.20.0. Details: " + detail
                ])
            }
            throw error
        }
    }

    func ask(_ prompt: String, model: URL, onChunk: (String) -> Void, onStage: (String) -> Void) async throws -> String {
        if path != model.path || engine == nil {
            onStage("Loading local GPU model")
            unload()
            try await initialize(model: model)
        }
        try Task.checkCancellation()
        guard let engine else { throw CocoaError(.fileReadUnknown) }
        let conversation = try await engine.createConversation()
        try Task.checkCancellation()
        active = conversation
        defer { active = nil }
        onStage("Generating on Metal")
        var result = ""
        for try await chunk in conversation.sendMessageStream(Message(prompt), maxOutputTokens: 600) {
            try Task.checkCancellation()
            let delta = chunk.toString
            if !delta.isEmpty {
                result += delta
                onChunk(result)
            }
        }
        try Task.checkCancellation()
        return result
    }
}
