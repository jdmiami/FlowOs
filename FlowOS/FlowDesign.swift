import SwiftUI
import UIKit

enum FlowMotion {
    static let snap = Animation.spring(duration: 0.32, bounce: 0.38)
    static let elastic = Animation.spring(duration: 0.68, bounce: 0.48)
    static let hero = Animation.spring(duration: 1.34, bounce: 0.52)
}

struct LiquidSurface: ViewModifier {
    var radius: CGFloat = 28
    var interactive = false
    var tint: Color = .white.opacity(0.16)
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color.white, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(Palette.ink.opacity(0.10)))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: RoundedRectangle(cornerRadius: radius))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.78), lineWidth: 1))
        }
    }
}
extension View {
    func liquidSurface(radius: CGFloat = 28, interactive: Bool = false, tint: Color = .white.opacity(0.16)) -> some View {
        modifier(LiquidSurface(radius: radius, interactive: interactive, tint: tint))
    }
}
struct FlowCard: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduced
    func body(content: Content) -> some View {
        content.padding(17).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 26)
                    .fill(.white.opacity(reduced ? 1 : 0.62))
                    .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.85), lineWidth: 1) }
                    .shadow(color: Palette.ink.opacity(0.045), radius: 14, x: 0, y: 6)
            }
    }
}
struct FlowPress: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduced
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduced ? 0.92 : 1)
            .brightness(configuration.isPressed ? -0.035 : 0)
            .animation(reduced ? .easeOut(duration: 0.12) : FlowMotion.elastic, value: configuration.isPressed)
    }
}
struct FlowPrimary: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .frame(minHeight: 48).frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .foregroundStyle(Palette.ink)
            .liquidSurface(radius: 24, interactive: true, tint: Palette.lavender.opacity(0.55))
            .opacity(enabled ? 1 : 0.48)
            .scaleEffect(configuration.isPressed && !reduced ? 0.92 : 1)
            .animation(reduced ? .easeOut(duration: 0.12) : FlowMotion.elastic, value: configuration.isPressed)
    }
}
struct FlowBackdrop: View {
    let tab: Int
    let busy: Bool
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.accessibilityReduceTransparency) private var solid
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Environment(\.renderBudget) private var budget
    @Environment(\.flowTheme) private var theme
    private var colors: [Color] {
        switch tab {
        case 1: return [Color(flowHex:theme.primary),Color(flowHex:theme.secondary)]
        case 2: return [Color(flowHex:theme.accent),Color(flowHex:theme.primary)]
        case 3: return [Color(flowHex:theme.secondary),Color(flowHex:theme.accent)]
        case 4: return [Color(flowHex:theme.primary),Color(flowHex:theme.accent)]
        default: return [Color(flowHex:theme.primary),Color(flowHex:theme.secondary)]
        }
    }
    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduced || busy || lowPower || solid || !budget.ambient)) { timeline in
                let t = reduced || busy || lowPower || !budget.ambient ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60)
                ZStack {
                    Color(red: 0.98, green: 0.975, blue: 0.99)
                    if !solid {
                        Ellipse().fill(colors[0].opacity(0.48)).frame(width: geo.size.width * 1.15, height: 390)
                            .blur(radius: 70).offset(x: -90 + 24 * sin(t * 0.31), y: -geo.size.height * 0.36)
                        Ellipse().fill(colors[1].opacity(0.42)).frame(width: geo.size.width * 1.2, height: 410)
                            .blur(radius: 74).offset(x: 100 + 30 * cos(t * 0.25), y: geo.size.height * 0.30)
                        Ellipse().fill(Color(flowHex:theme.accent).opacity(0.28)).frame(width: 270, height: 320)
                            .blur(radius: 65).offset(x: -100, y: 90 + 18 * sin(t * 0.4))
                    }
                }.frame(width: geo.size.width, height: geo.size.height).clipped()
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
    }
}
struct FluidBlob: Shape {
    var phase: Double
    var amplitude: Double
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(phase, amplitude) }
        set { phase = newValue.first; amplitude = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = Double(min(rect.width, rect.height)) * 0.40
        var p = Path()
        for i in 0...96 {
            let a = Double(i) / 96 * 2 * Double.pi
            let wave = 1 + amplitude * (0.63 * sin(a * 3 + phase) + 0.37 * cos(a * 5 - phase * 0.7))
            let pt = CGPoint(x: center.x + CGFloat(r * wave * cos(a)), y: center.y + CGFloat(r * wave * sin(a)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}
struct LiquidOrb: View {
    var busy = false
    var onOpen: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var drag = CGSize.zero
    @State private var pulse = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var feedback = 0
    var body: some View {
        TimelineView(.animation(minimumInterval: busy ? 1.0 / 15 : 1.0 / 30, paused: reduced || lowPower || !budget.ambient)) { timeline in
            let t = reduced || lowPower || !budget.ambient ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 120)
            let phase = t * (busy ? 2.4 : 0.8)
            let amp = reduced ? 0.04 : (busy ? 0.13 : 0.085) + min(0.12, Double(abs(drag.width) + abs(drag.height)) / 700)
            ZStack {
                Circle().fill(Palette.lavender.opacity(0.32)).frame(width: 175, height: 175).blur(radius: 28).offset(y: 22)
                FluidBlob(phase: phase, amplitude: amp)
                    .fill(RadialGradient(colors: [.white, Color(red: 0.86, green: 0.81, blue: 0.98), Color(flowHex:theme.primary), Color(flowHex:theme.secondary), Color(flowHex:theme.accent)], center: UnitPoint(x: 0.29 + Double(drag.width) / 500, y: 0.24 + Double(drag.height) / 500), startRadius: 5, endRadius: 142))
                    .overlay { FluidBlob(phase: phase, amplitude: amp).strokeBorderCompat(.white.opacity(0.82)) }
                FluidBlob(phase: phase + 1.6, amplitude: amp * 0.8)
                    .fill(LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.03), Palette.lavender.opacity(0.30)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .scaleEffect(0.76).rotationEffect(.degrees(24))
                Ellipse().trim(from: 0.05, to: 0.57).stroke(.white.opacity(0.78), style: StrokeStyle(lineWidth: 2.2, lineCap: .round)).frame(width: 158, height: 100).rotationEffect(.degrees(-27 + 7 * sin(t * 0.9)))
                Image(systemName: busy ? "waveform" : "sparkle").font(.system(size: 30, weight: .light)).foregroundStyle(Palette.ink.opacity(0.78))
            }.frame(width: 240, height: 240)
                .scaleEffect(pulse && !reduced ? 1.12 : 1)
                .offset(x: drag.width * 0.37, y: drag.height * 0.37)
        }
        .frame(height: 244)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 8).onChanged { value in
            guard !reduced else { return }
            drag = CGSize(width: max(-90, min(90, value.translation.width)), height: max(-65, min(65, value.translation.height)))
        }.onEnded { _ in withAnimation(reduced ? .easeOut(duration: 0.15) : FlowMotion.hero) { drag = .zero }; feedback += 1 })
        .onTapGesture { feedback += 1; onOpen() }
        .accessibilityElement(children: .ignore).accessibilityLabel(busy ? "AI working, open chat" : "Open AI chat").accessibilityAddTraits(.isButton).accessibilityAction { onOpen() }
        .sensoryFeedback(.selection, trigger: feedback)
        .onChange(of: busy) { _, value in
            withAnimation(reduced ? .easeOut(duration: 0.15) : FlowMotion.hero) { pulse = value }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
    }
}
private extension Shape {
    func strokeBorderCompat(_ color: Color) -> some View { stroke(color, lineWidth: 1.3) }
}

struct FlowDock: View {
    @Binding var selection: Int
    let items: [(String, String)]
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                Button {
                    withAnimation(reduced ? .easeOut(duration: 0.15) : FlowMotion.elastic) { selection = index }; FlowFeedback.shared.play()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: items[index].1)
                            .font(.system(size: 21, weight: selection == index ? .semibold : .regular))
                            .symbolEffect(.bounce, value: selection == index && !reduced)
                        Text(items[index].0).font(.caption2.weight(selection == index ? .bold : .medium)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity).frame(minHeight: 54)
                    .background {
                        if selection == index {
                            Capsule().fill(Palette.lavender.opacity(0.52)).matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .scaleEffect(selection == index && !reduced ? 1.06 : 1)
                }.buttonStyle(FlowPress()).accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }.padding(5).liquidSurface(radius: 38, interactive: true)
            .padding(.horizontal, 16).padding(.bottom, 7)
            .sensoryFeedback(.selection, trigger: selection)
    }
}

struct FlowSectionTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(.largeTitle, design: .serif, weight: .regular)).tracking(-0.9)
            Text(subtitle).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.73))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct FlowModePicker: View {
    @Binding var selection: String
    let options: [(String, String)]
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                Button {
                    withAnimation(reduced ? .easeOut(duration: 0.12) : FlowMotion.elastic) { selection = options[i].0 }
                } label: {
                    Text(options[i].1).font(.caption.weight(.semibold)).lineLimit(1)
                        .frame(maxWidth: .infinity).frame(minHeight: 44)
                        .background {
                            if selection == options[i].0 {
                                Capsule().fill(.white.opacity(0.88)).matchedGeometryEffect(id: "mode", in: namespace)
                            }
                        }
                }.buttonStyle(FlowPress()).accessibilityAddTraits(selection == options[i].0 ? .isSelected : [])
            }
        }.padding(4).liquidSurface(radius: 28).sensoryFeedback(.selection, trigger: selection)
    }
}

struct FlowGlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 14) { content() }
        } else { content() }
    }
}
