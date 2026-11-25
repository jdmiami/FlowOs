import Foundation
import LiteRTLM

@MainActor final class LocalBrain {
    private var engine: Engine?
    private var path: String?
    private var cache: URL?

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

    func ask(_ prompt: String, model: URL) async throws -> String {
        if path != model.path || engine == nil {
            unload()
            try await initialize(model: model)
        }
        guard let engine else { throw CocoaError(.fileReadUnknown) }
        let conversation = try await engine.createConversation()
        let result = try await conversation.sendMessage(Message(prompt))
        return result.toString
    }
}
