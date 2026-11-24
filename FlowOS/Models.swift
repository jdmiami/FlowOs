import Foundation

struct MiniApp: Codable, Identifiable {
    var id = UUID()
    var title: String
    var fields: [String]
    var rows: [[String: String]] = []
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
}
enum Validation {
    static func miniApp(_ plan: Plan) -> MiniApp? {
        guard plan.action == "app", let title = plan.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 80, let fields = plan.fields, (1...12).contains(fields.count), Set(fields).count == fields.count, fields.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 60 }) else { return nil }
        return MiniApp(title: title, fields: fields)
    }
    static func workflow(_ plan: Plan) -> Workflow? {
        guard plan.action == "workflow", let title = plan.title, !title.isEmpty, title.count <= 80, let steps = plan.steps, (1...20).contains(steps.count), steps.allSatisfy({ !$0.isEmpty && $0.count <= 300 }) else { return nil }
        return Workflow(title: title, steps: steps)
    }
}
