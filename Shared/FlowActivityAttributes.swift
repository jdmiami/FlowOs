import ActivityKit
import Foundation
struct FlowActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        var completed: Bool
    }
    var started: Date
}
