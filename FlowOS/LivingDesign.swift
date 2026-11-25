import SwiftUI
import UIKit
import CoreHaptics
import AVFoundation

extension Color {
    init(flowHex hex: String) {
        let n = UInt32(hex.dropFirst(), radix: 16) ?? 0xC2BAED
        self.init(red: Double((n >> 16) & 255)/255, green: Double((n >> 8) & 255)/255, blue: Double(n & 255)/255)
    }
}
private struct FlowThemeKey: EnvironmentKey { static let defaultValue = FlowTheme.aurora }
extension EnvironmentValues {
    var flowTheme: FlowTheme { get { self[FlowThemeKey.self] } set { self[FlowThemeKey.self] = newValue } }
}
struct RenderBudget: Equatable {
    var lowPower = false
    var thermal: ProcessInfo.ThermalState = .nominal
    var busy = false
    var reducedMotion = false
    var effectsEnabled = true
    var foreground = true
    var rich: Bool { foreground && effectsEnabled && !busy && !lowPower && !reducedMotion && thermal == .nominal }
    var ambient: Bool { foreground && effectsEnabled && !busy && !lowPower && !reducedMotion && thermal.rawValue < ProcessInfo.ThermalState.serious.rawValue }
    var label: String {
        if !foreground { return "Background" }
        if reducedMotion || !effectsEnabled { return "Minimal motion" }
        if lowPower || thermal.rawValue >= ProcessInfo.ThermalState.serious.rawValue { return "Power / thermal protection" }
        if busy { return "AI priority" }
        return rich ? "Full graphics" : "Balanced graphics"
    }
}
private struct RenderBudgetKey: EnvironmentKey { static let defaultValue = RenderBudget() }
extension EnvironmentValues {
    var renderBudget: RenderBudget { get { self[RenderBudgetKey.self] } set { self[RenderBudgetKey.self] = newValue } }
}
@MainActor final class FlowFeedback {
    static let shared = FlowFeedback()
    private var engine: CHHapticEngine?
    private var player: AVAudioPlayer?
    func play(_ strong: Bool = false) {
        if UserDefaults.standard.object(forKey: "flow.haptics") as? Bool ?? true {
            if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
                do {
                    if engine == nil { engine = try CHHapticEngine() }
                    try engine?.start()
                    let events = [
                        CHHapticEvent(eventType: .hapticTransient, parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: strong ? 0.8 : 0.35),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.28)
                        ], relativeTime: 0),
                        CHHapticEvent(eventType: .hapticTransient, parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.18),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.12)
                        ], relativeTime: 0.075)
                    ]
                    let pattern = try CHHapticPattern(events: events, parameters: [])
                    try engine?.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
                } catch {
                    engine = nil
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            } else { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        }
        if UserDefaults.standard.bool(forKey: "flow.sound") { tone(strong: strong) }
    }
    private func tone(strong: Bool) {
        // Local, short synthesized PCM chime. No network or audio assets.
        let rate = 22050, count = 3307
        var data = Data()
        func word(_ value: UInt32, _ bytes: Int) {
            for i in 0..<bytes { data.append(UInt8(truncatingIfNeeded: value >> (8*i))) }
        }
        data.append(Data("RIFF".utf8)); word(UInt32(36+count*2),4)
        data.append(Data("WAVEfmt ".utf8)); word(16,4); word(1,2); word(1,2)
        word(UInt32(rate),4); word(UInt32(rate*2),4); word(2,2); word(16,2)
        data.append(Data("data".utf8)); word(UInt32(count*2),4)
        for i in 0..<count {
            let t = Double(i)/Double(rate)
            let env = min(t/0.008,1)*exp(-t*29)
            let hz = strong ? 520.0 : 420.0
            let sample = Int16((sin(2*Double.pi*hz*t)+0.27*sin(2*Double.pi*hz*1.5*t))*env*2400)
            word(UInt32(UInt16(bitPattern: sample)),2)
        }
        player = try? AVAudioPlayer(data: data)
        player?.volume = 0.35
        player?.play()
    }
}
struct LivingMembrane: View {
    var busy: Bool
    var expanded: Bool
    var drag: CGSize
    @Environment(\.renderBudget) private var budget
    @Environment(\.flowTheme) private var theme
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/30, paused: !budget.rich)) { context in
            let t = budget.rich ? Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 90)) : 0
            let x = Float(drag.width / 90), y = Float(drag.height / 90)
            let merge = expanded ? Float(1) : min(Float(0.75), (abs(x)+abs(y))*0.65)
            Rectangle().fill(.white)
                .colorEffect(ShaderLibrary.flowMembrane(
                    .float2(240,240), .float(t), .float2(x,y), .float(busy ? 1 : 0),
                    .float(merge), .color(Color(flowHex: theme.primary)),
                    .color(Color(flowHex: theme.secondary)), .color(Color(flowHex: theme.accent))
                ))
        }.frame(width: 240,height: 240).allowsHitTesting(false)
    }
}
struct LivingPortal: View {
    let busy: Bool
    let stage: String
    let navigate: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.renderBudget) private var budget
    @Environment(\.flowTheme) private var theme
    @State private var expanded = false
    @State private var drag = CGSize.zero
    @Namespace private var glass
    private var actions: [(Int,String,String,CGFloat,CGFloat)] {
        [(1,"Chat","bubble.left", -104,-76),(2,"Labs","square.stack.3d.up",104,-76),(3,"Connect","phone", -104,76),(4,"Flow","point.3.connected.trianglepath.dotted",104,76)]
    }
    private var animation: Animation { reduced ? .easeOut(duration: 0.15) : FlowMotion.hero }
    private func toggle() {
        withAnimation(animation) { expanded.toggle() }
        FlowFeedback.shared.play(true)
    }
    var body: some View {
        FlowGlassGroup {
            ZStack {
                ZStack {
                    if budget.rich {
                        LivingMembrane(busy: busy, expanded: expanded, drag: drag)
                    } else {
                        LiquidOrb(busy: busy, onOpen: {}).allowsHitTesting(false)
                    }
                    if budget.rich {
                        Image(systemName: busy ? "waveform" : "sparkle").font(.system(size: 32,weight:.light))
                            .foregroundStyle(Palette.ink.opacity(0.8))
                    }
                }
                .scaleEffect(expanded && !reduced ? 0.64 : 1)
                .offset(x: drag.width*0.3,y: drag.height*0.3)
                .contentShape(Circle())
                .gesture(DragGesture(minimumDistance: 8).onChanged { value in
                    guard !reduced else { return }
                    drag = CGSize(width: max(-90,min(90,value.translation.width)),height: max(-90,min(90,value.translation.height)))
                }.onEnded { _ in
                    withAnimation(animation) { drag = .zero }
                    FlowFeedback.shared.play()
                })
                .onTapGesture { toggle() }
                .accessibilityElement(children: .ignore).accessibilityLabel(busy ? "AI working: \(stage)" : "Open AI portal")
                .accessibilityAddTraits(.isButton).accessibilityAction { toggle() }
                if expanded {
                    ForEach(actions.indices,id:\.self) { i in
                        let a = actions[i]
                        Button {
                            withAnimation(animation) { expanded = false }
                            FlowFeedback.shared.play()
                            navigate(a.0)
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName:a.2).font(.title2)
                                Text(a.1).font(.caption2.weight(.semibold))
                            }.frame(width:75,height:75).liquidSurface(radius:28,interactive:true,tint:Color(flowHex:theme.primary).opacity(0.25))
                        }.buttonStyle(FlowPress())
                            .offset(x:a.3,y:a.4)
                            .transition(reduced ? .opacity : .scale(scale:0.15).combined(with:.opacity))
                    }
                }
            }.frame(height:250)
        }
        .simultaneousGesture(MagnifyGesture().onEnded { value in
            if value.magnification < 0.85 && expanded { toggle() }
        })
        .contextMenu {
            Button("Open chat",systemImage:"bubble.left") { navigate(1) }
            Button("Open Labs",systemImage:"square.stack.3d.up") { navigate(2) }
            Button("Open workflows",systemImage:"point.3.connected.trianglepath.dotted") { navigate(4) }
        }
    }
}
