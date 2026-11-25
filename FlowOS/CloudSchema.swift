import Foundation

enum CloudProvider: String, CaseIterable, Identifiable, Codable {
    case openai, anthropic, gemini, nvidia, chatgptPlan
    var id: String { rawValue }
    var title: String { switch self { case .chatgptPlan:return "ChatGPT plan"; case .openai:return "OpenAI API"; case .anthropic:return "Anthropic"; case .gemini:return "Google Gemini"; case .nvidia:return "NVIDIA NIM" } }
    var modelsURL: String { switch self { case .openai,.chatgptPlan:return "https://api.openai.com/v1/models"; case .anthropic:return "https://api.anthropic.com/v1/models?limit=100"; case .gemini:return "https://generativelanguage.googleapis.com/v1beta/models?pageSize=100"; case .nvidia:return "https://integrate.api.nvidia.com/v1/models" } }
    var keysURL: String { switch self { case .chatgptPlan:return "https://chatgpt.com/"; case .openai:return "https://platform.openai.com/api-keys"; case .anthropic:return "https://console.anthropic.com/settings/keys"; case .gemini:return "https://aistudio.google.com/apikey"; case .nvidia:return "https://build.nvidia.com/" } }
}
enum CloudEffort: String, CaseIterable, Codable, Identifiable {
    case automatic, low, medium, high, xhigh, max
    var id: String { rawValue }
    var title: String { self == .automatic ? "Provider default" : self == .xhigh ? "Extra high" : rawValue.capitalized }
}
struct CloudModel: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var efforts: [CloudEffort] = [.automatic]
    var inputLimit: Int?
    var outputLimit: Int?
    var thinking: String? = nil
    static func infer(provider:CloudProvider,id:String,name:String?=nil) -> CloudModel {
        let s=id.lowercased()
        var m=CloudModel(id:id,name:name ?? id)
        switch provider {
        case .openai,.chatgptPlan:
            if s.hasPrefix("gpt-6.2-astra") || s.hasPrefix("gpt-6.2-sol") || s.hasPrefix("gpt-6.1-terra") || s.hasPrefix("gpt-6-luna") {
                m.efforts=[.automatic,.low,.medium,.high,.xhigh,.max]; m.thinking="openai"
            } else if s.hasPrefix("gpt-5") || s.hasPrefix("o3") || s.hasPrefix("o4") || s.hasPrefix("o1") {
                m.efforts=[.automatic,.low,.medium,.high]; m.thinking="openai"
            }
        case .anthropic:
            // Use discovered capability metadata for non-default levels.
            break
        case .gemini:
            if s.hasPrefix("gemini-2.5-flash") && !s.contains("lite") && !s.contains("audio") {
                m.efforts=[.automatic,.low,.medium,.high];m.thinking="budget"
            } else if s.hasPrefix("gemini-3") || s.hasPrefix("gemini-4") {
                m.efforts=s.contains("pro") ? [.automatic,.low,.high] : [.automatic,.low,.medium,.high];m.thinking="level"
            }
        case .nvidia:
            if ["openai/gpt-oss-20b","openai/gpt-oss-120b"].contains(s) { m.efforts=[.automatic,.low,.medium,.high];m.thinking="nim" }
        }
        return m
    }
}
struct CloudRoute: Codable, Equatable {
    var provider: CloudProvider
    var model: String
    var effort: CloudEffort = .automatic
    var maxOutput: Int = 2048
    var contextCharacters: Int = 12000
    var planProfileID: String? = nil
}
struct CloudUsage: Codable, Equatable {
    var input=0
    var output=0
    var reasoning=0
    var cached=0
    var total: Int { input+output }
}
struct CloudTurn: Codable {
    var role:String
    var text:String
}
enum CloudPayload {
    static func build(provider:CloudProvider,model:CloudModel,route:CloudRoute,turns:[CloudTurn],system:String) -> [String:Any] {
        let cap=max(1,min(route.maxOutput,model.outputLimit ?? 32768,32768))
        let effort=model.efforts.contains(route.effort) ? route.effort : .automatic
        let messages=turns.map { ["role":$0.role,"content":$0.text] }
        var body:[String:Any]
        switch provider {
        case .openai,.chatgptPlan:
            body=["model":model.id,"input":messages,"instructions":system,"stream":true,"store":false,"max_output_tokens":cap]
            if provider == .chatgptPlan { body.removeValue(forKey:"max_output_tokens") }
            if effort != .automatic && model.thinking=="openai" { body["reasoning"]=["effort":effort.rawValue] }
        case .anthropic:
            body=["model":model.id,"messages":messages,"system":system,"stream":true,"max_tokens":cap]
            if effort != .automatic && model.thinking=="adaptive" {
                body["thinking"]=["type":"adaptive"];body["output_config"]=["effort":effort.rawValue]
            }
        case .gemini:
            body=["contents":turns.map { ["role":$0.role=="assistant" ? "model":"user","parts":[["text":$0.text]]] },"systemInstruction":["parts":[["text":system]]]]
            var gen:[String:Any]=["maxOutputTokens":cap]
            if effort != .automatic {
                if model.thinking=="level" { gen["thinkingConfig"]=["thinkingLevel":effort.rawValue.uppercased()] }
                if model.thinking=="budget" {
                    let wanted=effort == .low ? 256 : effort == .medium ? 1024 : 4096
                    gen["thinkingConfig"]=["thinkingBudget":min(wanted,max(0,cap-128))]
                }
            }
            body["generationConfig"]=gen
        case .nvidia:
            body=["model":model.id,"messages":[["role":"system","content":system]]+messages,"stream":true,"max_tokens":cap]
            if effort != .automatic && model.thinking=="nim" { body["reasoning_effort"]=effort.rawValue }
        }
        return body
    }
    static func bounded(_ turns:[CloudTurn],limit:Int) -> [CloudTurn] {
        var remaining=max(1000,min(limit,120000)), kept:[CloudTurn]=[]
        for turn in turns.reversed() {
            guard remaining>0 else { break }
            let text=String(turn.text.suffix(remaining)); remaining -= text.count+24
            if !text.isEmpty { kept.append(.init(role:turn.role,text:text)) }
        }
        // Claude/Gemini conversations must start with user input.
        var result=Array(kept.reversed())
        while result.first?.role=="assistant" { result.removeFirst() }
        return result
    }
}
