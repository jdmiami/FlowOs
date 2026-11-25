import Foundation

struct MiniApp: Codable, Identifiable {
    var id = UUID()
    var title: String
    var fields: [String]
    var rows: [[String: String]] = []
    var components: [FlowComponent]? = nil
}
struct Workflow: Codable, Identifiable {
    var id = UUID()
    var title: String
    var steps: [String]
}
struct ChatLine: Codable, Identifiable {
    var id = UUID()
    var user: Bool
    var text: String
}
struct Plan: Codable {
    var action: String
    var title: String?
    var fields: [String]?
    var steps: [String]?
    var value: String?
    var components: [FlowComponent]? = nil
    var theme: FlowTheme? = nil
}
enum Validation {
    static func miniApp(_ plan: Plan) -> MiniApp? {
        guard plan.action == "app", let title = plan.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 80, let fields = plan.fields, (1...12).contains(fields.count), Set(fields).count == fields.count, fields.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 60 }) else { return nil }
        guard (plan.components?.count ?? 0) <= 8, (plan.components ?? []).allSatisfy({ $0.valid(fields: fields) }) else { return nil }
        return MiniApp(title: title, fields: fields, components: plan.components)
    }
    static func workflow(_ plan: Plan) -> Workflow? {
        guard plan.action == "workflow", let title = plan.title, !title.isEmpty, title.count <= 80, let steps = plan.steps, (1...20).contains(steps.count), steps.allSatisfy({ !$0.isEmpty && $0.count <= 300 }) else { return nil }
        return Workflow(title: title, steps: steps)
    }
}

struct Artifact: Codable, Identifiable {
    var id = UUID()
    var created = Date()
    var title: String
    var request: String
    var kind: String
    var source: String
    var state: String
    var plan: Plan?
    var installedID: UUID?
}
extension Validation {
    static func theme(_ plan: Plan) -> FlowTheme? {
        guard plan.action == "theme", let theme = plan.theme, theme.isValid else { return nil }
        return theme
    }
    static func accepts(_ plan: Plan, mode: String) -> Bool {
        switch mode { case "app": return miniApp(plan) != nil; case "workflow": return workflow(plan) != nil; case "theme": return theme(plan) != nil; default: return false }
    }
    static func parse(_ text: String, mode: String) -> Plan? {
        // Scan balanced JSON objects, ignoring braces inside quoted strings.
        var start: String.Index?
        var depth = 0
        var quoted = false
        var escaped = false
        for i in text.indices {
            let c = text[i]
            if depth == 0 {
                if c == "{" { start = i; depth = 1; quoted = false; escaped = false }
                continue
            }
            if quoted {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { quoted = false }
            } else if c == "\"" { quoted = true }
            else if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0, let start,
                   let plan = try? JSONDecoder().decode(Plan.self, from: Data(text[start...i].utf8)),
                   accepts(plan, mode: mode) { return plan }
            }
        }
        return nil
    }
}
