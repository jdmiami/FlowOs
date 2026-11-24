import Foundation
import LiteRTLM

@MainActor final class LocalBrain {
    private var engine: Engine?
    private var path: String?
    func unload() { engine = nil; path = nil }
    func ask(_ prompt: String, model: URL) async throws -> String {
        if path != model.path || engine == nil {
            unload()
            let config = try EngineConfig(modelPath: model.path, backend: .gpu, maxNumTokens: 2048, cacheDir: NSTemporaryDirectory())
            let newEngine = Engine(engineConfig: config)
            try await newEngine.initialize()
            engine = newEngine
            path = model.path
        }
        guard let engine else { throw CocoaError(.fileReadUnknown) }
        let conversation = try await engine.createConversation()
        let result = try await conversation.sendMessage(Message(prompt))
        return result.toString
    }
}
