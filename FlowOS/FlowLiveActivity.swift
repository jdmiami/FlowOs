import ActivityKit
import Foundation

@MainActor final class FlowLiveActivity {
    private var activity: Activity<FlowActivityAttributes>?
    private var queue: Task<Void,Never>?
    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let prior = queue
        queue = Task { await prior?.value; await operation() }
    }
    func begin() {
        guard UserDefaults.standard.bool(forKey:"flow.liveActivity") else { return }
        enqueue {
            for old in Activity<FlowActivityAttributes>.activities {
                await old.end(nil,dismissalPolicy:.immediate)
            }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            self.activity = try? Activity.request(attributes:FlowActivityAttributes(started:.now),content:ActivityContent(state:.init(phase:"Preparing",completed:false),staleDate:Date().addingTimeInterval(150)),pushType:nil)
        }
    }
    func update(_ phase: String) {
        guard UserDefaults.standard.bool(forKey:"flow.liveActivity") else { return }
        enqueue { await self.activity?.update(ActivityContent(state:.init(phase:phase,completed:false),staleDate:Date().addingTimeInterval(150))) }
    }
    func end(_ phase: String) {
        enqueue {
            await self.activity?.end(ActivityContent(state:.init(phase:phase,completed:true),staleDate:nil),dismissalPolicy:.after(Date().addingTimeInterval(12)))
            self.activity = nil
        }
    }
}
