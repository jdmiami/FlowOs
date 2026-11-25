import Foundation
import LiteRTLM

@MainActor final class LocalBrain {
    private var engine: Engine?
    private var path: String?
    func unload() { engine = nil; path = nil }

    private func initialize(model: URL) async throws {
        // CPU avoids the GPU KV-cache buffer mismatch on affected models.
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowOS-CPU-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let config = try EngineConfig(modelPath: model.path, backend: .cpu, maxNumTokens: 1024, cacheDir: cache.path)
        let newEngine = Engine(engineConfig: config)
        try await newEngine.initialize()
        engine = newEngine
        path = model.path
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
