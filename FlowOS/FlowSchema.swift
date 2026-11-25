import Foundation

// Optional fields retain compatibility with V0.1–0.4 saved JSON.
struct FlowTheme: Codable, Equatable {
    var name: String
    var primary: String
    var secondary: String
    var accent: String
    static let aurora = FlowTheme(name: "Aurora", primary: "#C2BAED", secondary: "#B8E3DE", accent: "#FAD1CC")
    static let presets = [
        aurora,
        FlowTheme(name: "Pearl", primary: "#E3E1EF", secondary: "#DDECE8", accent: "#F1E5DA"),
        FlowTheme(name: "Sakura", primary: "#E6C9EF", secondary: "#F5DFE8", accent: "#F6C4D4"),
        FlowTheme(name: "Ocean", primary: "#BBD6F5", secondary: "#BCE7DC", accent: "#D7C8F0"),
        FlowTheme(name: "Sorbet", primary: "#E6CCF0", secondary: "#FAE9BB", accent: "#F7CCB7")
    ]
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 40 &&
        [primary, secondary, accent].allSatisfy { hex in
            hex.count == 7 && hex.first == "#" && hex.dropFirst().utf8.allSatisfy {
                (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
            }
        }
    }
}

struct FlowComponent: Codable, Equatable {
    var kind: String
    var field: String?
    var field2: String?
    var title: String?
    static let kinds = ["count", "sum", "bar", "calculator", "slider", "toggle", "date", "board"]
    func valid(fields: [String]) -> Bool {
        guard Self.kinds.contains(kind), (title?.count ?? 0) <= 60 else { return false }
        switch kind {
        case "count": return field == nil && field2 == nil
        case "calculator":
            guard let field, let field2 else { return false }
            return field != field2 && fields.contains(field) && fields.contains(field2)
        case "bar":
            guard let field else { return false }
            return fields.contains(field) && (field2.map { fields.contains($0) && $0 != field } ?? true)
        default:
            guard let field else { return false }
            return fields.contains(field) && field2 == nil
        }
    }
}
enum FlowMath {
    static func number(_ raw: String?) -> Double? {
        guard let raw, let n = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              n.isFinite, abs(n) <= 1e12 else { return nil }
        return n
    }
    static func sum(_ rows: [[String: String]], field: String) -> Double {
        rows.compactMap { number($0[field]) }.reduce(0,+)
    }
    static func product(_ rows: [[String: String]], first: String, second: String) -> Double {
        rows.reduce(0) { total, row in total + (number(row[first]) ?? 0) * (number(row[second]) ?? 0) }
    }
    static func groups(_ rows: [[String: String]], category: String, measure: String?) -> [(String, Double)] {
        var totals: [String: Double] = [:]
        for row in rows {
            let label = String((row[category] ?? "Other").prefix(60))
            totals[label, default: 0] += measure.map { number(row[$0]) ?? 0 } ?? 1
        }
        return totals.sorted { a,b in a.value == b.value ? a.key < b.key : a.value > b.value }.prefix(12).map { ($0.key,$0.value) }
    }
}
