import SwiftUI
import Charts

struct GeneratedFields: View {
    let fields: [String]
    let components: [FlowComponent]
    @Binding var draft: [String: String]
    private func kind(_ field: String) -> String {
        components.first { $0.field == field && ["slider","toggle","date"].contains($0.kind) }?.kind ?? "text"
    }
    var body: some View {
        ForEach(fields,id:\.self) { field in
            switch kind(field) {
            case "slider":
                VStack(alignment:.leading) {
                    HStack { Text(field); Spacer(); Text(draft[field] ?? "0").monospacedDigit() }
                    Slider(value: Binding(get:{ min(100,max(0,FlowMath.number(draft[field]) ?? 0)) },set:{ draft[field] = String(Int($0)) }),in:0...100,step:1)
                }
            case "toggle":
                Toggle(field,isOn: Binding(get:{ draft[field] == "true" },set:{ draft[field] = $0 ? "true" : "false" }))
            case "date":
                DatePicker(field,selection: Binding(get:{ ISO8601DateFormatter().date(from:draft[field] ?? "") ?? .now },set:{ draft[field] = ISO8601DateFormatter().string(from:$0) }),displayedComponents:.date)
            default:
                TextField(field,text: Binding(get:{ draft[field,default:""] },set:{ draft[field] = $0 })).textFieldStyle(.roundedBorder)
            }
        }
    }
}
struct GeneratedDashboard: View {
    let rows: [[String:String]]
    let components: [FlowComponent]
    @Environment(\.flowTheme) private var theme
    private func metric(_ title: String, _ value: Double) -> some View {
        VStack(alignment:.leading,spacing:6) {
            Text(title).font(.caption.weight(.medium))
            Text(value.formatted(.number.precision(.fractionLength(0...2)))).font(.system(.largeTitle,design:.rounded,weight:.semibold)).monospacedDigit().contentTransition(.numericText())
        }.glass()
    }
    var body: some View {
        ForEach(components.indices,id:\.self) { i in
            let c = components[i]
            switch c.kind {
            case "count": metric(c.title ?? "Records",Double(rows.count))
            case "sum":
                if let field = c.field { metric(c.title ?? "Total \(field)",FlowMath.sum(rows,field:field)) }
            case "calculator":
                if let a = c.field, let b = c.field2 { metric(c.title ?? "\(a) × \(b)",FlowMath.product(rows,first:a,second:b)) }
            case "bar":
                if let field = c.field {
                    let groups = FlowMath.groups(rows,category:field,measure:c.field2)
                    VStack(alignment:.leading) {
                        Text(c.title ?? field).font(.headline)
                        if groups.isEmpty { Text("Add records to populate chart.").font(.caption) }
                        else {
                            Chart(Array(groups.enumerated()),id:\.offset) { item in
                                BarMark(x:.value("Category",item.element.0),y:.value("Value",item.element.1)).foregroundStyle(Color(flowHex:theme.primary))
                            }.frame(height:175)
                        }
                    }.glass()
                }
            case "board":
                if let field = c.field {
                    let groups = FlowMath.groups(rows,category:field,measure:nil)
                    VStack(alignment:.leading) {
                        Text(c.title ?? "Board · \(field)").font(.headline)
                        ScrollView(.horizontal) {
                            HStack(alignment:.top) {
                                ForEach(groups,id:\.0) { group in
                                    VStack(alignment:.leading,spacing:8) {
                                        Text(group.0).font(.subheadline.bold())
                                        Text("\(Int(group.1)) records").font(.caption)
                                        ForEach(Array(rows.filter { String(($0[field] ?? "Other").prefix(60)) == group.0 }.prefix(12).enumerated()),id:\.offset) { item in
                                            Text(item.element.keys.sorted().filter { $0 != field }.compactMap { item.element[$0] }.joined(separator:" · ")).font(.caption).padding(8).background(.white,in:RoundedRectangle(cornerRadius:12))
                                        }
                                    }.frame(width:145,alignment:.leading).padding(10).background(Color(flowHex:theme.secondary).opacity(0.32),in:RoundedRectangle(cornerRadius:18))
                                }
                            }
                        }.scrollIndicators(.hidden)
                    }.glass()
                }
            default: EmptyView()
            }
        }
    }
}
struct ThemeStudio: View {
    @EnvironmentObject var store: Store
    @State private var prompt = ""
    @AppStorage("flow.effects") private var effects = true
    @AppStorage("flow.haptics") private var haptics = true
    @AppStorage("flow.sound") private var sound = false
    @AppStorage("flow.liveActivity") private var liveActivity = false
    var body: some View {
        Section("Living appearance") {
            Text("Current theme: \(store.theme.name)")
            ScrollView(.horizontal) {
                HStack {
                    ForEach(FlowTheme.presets,id:\.name) { theme in
                        Button { store.applyTheme(theme); FlowFeedback.shared.play() } label: {
                            VStack {
                                HStack(spacing:0) {
                                    ForEach([theme.primary,theme.secondary,theme.accent],id:\.self) { hex in Color(flowHex:hex).frame(width:29,height:40) }
                                }.clipShape(RoundedRectangle(cornerRadius:12))
                                Text(theme.name).font(.caption)
                            }
                        }.buttonStyle(FlowPress())
                    }
                }
            }
            TextField("Describe a new pastel theme",text:$prompt,axis:.vertical)
            Button("Generate theme with local AI") { store.start(prompt,mode:"theme") }.disabled(store.busy || prompt.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            Text("Generated themes appear in Labs → Artifacts. Preview and apply them there.").font(.caption)
            Toggle("Rich Metal effects",isOn:$effects)
            Toggle("Custom haptics",isOn:$haptics)
            Toggle("Interface sounds",isOn:$sound)
            Toggle("Live Activity status",isOn:$liveActivity).disabled(store.busy)
            Text("Live Activities show generic task status, not your prompts. Requires the widget-enabled build and system permission.").font(.caption)
        }
    }
}
