import ActivityKit
import WidgetKit
import SwiftUI

@main struct FlowWidgets: WidgetBundle {
    var body: some Widget { FlowActivityWidget() }
}
struct FlowActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for:FlowActivityAttributes.self) { context in
            HStack(spacing:13) {
                Image(systemName:context.state.completed ? "checkmark.circle" : "waveform.circle").font(.largeTitle)
                VStack(alignment:.leading) {
                    Text("FlowOS").font(.headline)
                    Text(context.state.phase).font(.subheadline)
                }
                Spacer()
                if !context.state.completed { Text(context.attributes.started,style:.timer).monospacedDigit() }
            }.padding().activityBackgroundTint(Color(red:0.91,green:0.88,blue:0.97)).activitySystemActionForegroundColor(.black).foregroundStyle(.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName:"sparkle").font(.title2) }
                DynamicIslandExpandedRegion(.trailing) { if !context.state.completed { Text(context.attributes.started,style:.timer).monospacedDigit() } }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.phase).font(.headline) }
            } compactLeading: { Image(systemName:"sparkle") }
            compactTrailing: { Image(systemName:context.state.completed ? "checkmark" : "waveform") }
            minimal: { Image(systemName:context.state.completed ? "checkmark" : "sparkle") }
        }
    }
}
