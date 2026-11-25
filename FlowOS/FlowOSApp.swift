import SwiftUI
import UniformTypeIdentifiers
import EventKit
import MessageUI
import UIKit
import WebKit

@main struct FlowOSApp: App {
    @StateObject private var store = Store()
    var body: some Scene { WindowGroup { RootView().environmentObject(store) } }
}

enum Palette {
    static let lavender = Color(red: 0.76, green: 0.73, blue: 0.93)
    static let peach = Color(red: 0.98, green: 0.82, blue: 0.80)
    static let mint = Color(red: 0.72, green: 0.89, blue: 0.87)
    static let ink = Color(red: 0.15, green: 0.16, blue: 0.23)
}
struct Glass: ViewModifier {
    func body(content: Content) -> some View { content.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.7), lineWidth: 1)) }
}
extension View { func glass() -> some View { modifier(Glass()) } }
struct LiquidOrb: View {
    @Environment(\.accessibilityReduceMotion) var reduced
    @State private var turn = false
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [.white, Palette.lavender, Palette.mint.opacity(0.6)], center: .topLeading, startRadius: 4, endRadius: 110)).frame(width: 150, height: 150).shadow(color: Palette.lavender.opacity(0.6), radius: 25, y: 12)
            Ellipse().stroke(.white.opacity(0.8), lineWidth: 2).frame(width: 170, height: 86).rotationEffect(.degrees(turn ? 35 : -35))
            Ellipse().fill(LinearGradient(colors: [.white.opacity(0.9), .clear], startPoint: .top, endPoint: .bottom)).frame(width: 92, height: 44).rotationEffect(.degrees(-35)).offset(x: -14, y: -38)
        }.frame(height: 185).accessibilityHidden(true).onAppear { if !reduced { withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { turn = true } } }
    }
}
struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var tab = 0
    @State private var settings = false
    let tabs = [("Home", "sparkle"), ("Chat", "bubble.left"), ("Labs", "square.stack.3d.up"), ("Connect", "phone"), ("Flow", "point.3.connected.trianglepath.dotted")]
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("flow.").font(.system(size: 34, weight: .semibold, design: .serif)); Spacer(); Button { settings = true } label: { Image(systemName: "slider.horizontal.3").font(.title2).padding(10) }.accessibilityLabel("Settings") }.padding(.horizontal, 24)
            Group {
                switch tab {
                case 0: home
                case 1: ChatView()
                case 2: LabsView()
                case 3: ConnectView()
                default: WorkflowsView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 0) { ForEach(tabs.indices, id: \.self) { i in Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { tab = i } } label: { VStack(spacing: 5) { Image(systemName: tabs[i].1).font(.system(size: 20)); Text(tabs[i].0).font(.caption2) }.frame(maxWidth: .infinity).padding(.vertical, 10).background(tab == i ? Palette.lavender.opacity(0.45) : .clear, in: Capsule()) }.accessibilityAddTraits(tab == i ? .isSelected : []) } }.padding(6).background(.regularMaterial, in: Capsule()).padding(.horizontal, 16).padding(.bottom, 6)
        }.foregroundStyle(Palette.ink).background { LinearGradient(colors: [Color.white, Palette.lavender.opacity(0.4), Palette.peach.opacity(0.3), Palette.mint.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea() }.preferredColorScheme(.light).sheet(isPresented: $settings) { SettingsView().environmentObject(store) }
        .sheet(isPresented: Binding(get: { store.pending != nil }, set: { if !$0 { store.pending = nil } })) { if let plan = store.pending { VStack(alignment: .leading, spacing: 20) { Text("Review creation").font(.largeTitle); Text(plan.title ?? "Untitled").font(.title2); ForEach(plan.fields ?? plan.steps ?? [], id: \.self) { Text($0) }; Spacer(); Button("Save to library") { store.approve() }.buttonStyle(.borderedProminent); Button("Cancel") { store.pending = nil } }.padding(28).presentationDetents([.medium, .large]) } }
    }
    var home: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) {
            LiquidOrb().frame(maxWidth: .infinity)
            Text("What would you\nlike to do today?").font(.system(size: 36, weight: .regular, design: .serif)).tracking(-1.5)
            Button { tab = 1 } label: { HStack { Image(systemName: "sparkle"); Text("Ask, create, or automate…"); Spacer(); Image(systemName: "arrow.up.right") }.glass() }.buttonStyle(.plain)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) { ForEach([2,3,4], id: \.self) { i in Button { tab = i } label: { VStack(alignment: .leading, spacing: 14) { Image(systemName: tabs[i].1).font(.title); Text(tabs[i].0).font(.headline); Text(i == 2 ? "Create your tools" : i == 3 ? "Calls and email" : "Build a routine").font(.caption) }.glass() }.buttonStyle(.plain) } }
            Text(store.status).font(.caption).foregroundStyle(.secondary)
        }.padding(24) }
    }
}
struct ChatView: View {
    @EnvironmentObject var store: Store
    @State private var text = ""
    @State private var mode = "chat"
    @State private var follow = true
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Intelligence").font(.title2.bold())
                Spacer()
                Toggle("Follow", isOn: $follow).toggleStyle(.switch).labelsHidden()
                    .accessibilityLabel("Follow streaming output")
            }.padding(.horizontal, 20)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if store.chat.isEmpty { Text("Your conversation stays on your phone.").glass() }
                        ForEach(store.chat) { line in
                            Text(line.text).textSelection(.enabled).glass()
                                .padding(line.user ? .leading : .trailing, 22)
                        }
                        AgentProgressView()
                        if !store.artifacts.isEmpty { ArtifactLibrary() }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(16)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: store.live) { _, _ in if follow { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: store.chat.count) { _, _ in if follow { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            VStack(spacing: 8) {
                Picker("Agent mode", selection: $mode) {
                    Text("Chat").tag("chat"); Text("Build app").tag("app"); Text("Workflow").tag("workflow")
                }.pickerStyle(.segmented).disabled(store.busy)
                HStack {
                    TextField(mode == "chat" ? "Ask anything" : "Describe what to build", text: $text, axis: .vertical).lineLimit(1...4)
                    if store.busy {
                        Button { store.stop() } label: { Image(systemName: "stop.circle.fill").font(.largeTitle) }.accessibilityLabel("Stop generation")
                    } else {
                        Button { let value = text; text = ""; store.start(value, mode: mode) } label: { Image(systemName: "arrow.up.circle.fill").font(.largeTitle) }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }.glass().padding(.horizontal, 16).padding(.bottom, 8)
        }
    }
}
struct LabsView: View {
    @EnvironmentObject var store: Store
    @State private var prompt = ""
    @State private var title = ""
    @State private var fields = "Name, Notes"
    @State private var selected: UUID?
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 18) { Text("AI Labs").font(.largeTitle.bold()); Text("Make what you need.").font(.title3); VStack(alignment: .leading) { TextField("Describe a tracker or database app", text: $prompt, axis: .vertical).lineLimit(2...5); Button("Create with local AI") { store.start(prompt, mode: "app") }.buttonStyle(.borderedProminent).disabled(store.busy || prompt.isEmpty) }.glass(); DisclosureGroup("Create manually") { TextField("App name", text: $title); TextField("Fields separated by commas", text: $fields); Button("Create app") { let plan = Plan(action: "app", title: title, fields: fields.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }); if let app = Validation.miniApp(plan) { store.apps.append(app); title = "" } }.disabled(title.isEmpty) }.glass(); AgentProgressView(); ArtifactLibrary(); Text("My applications").font(.title2.bold()); ForEach(store.apps) { app in Button { selected = app.id } label: { HStack { Image(systemName: "square.stack"); Text(app.title); Spacer(); Text("\(app.rows.count)"); Image(systemName: "chevron.right") }.glass() }.buttonStyle(.plain) } }.padding(20) }.sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) { if let selected, let index = store.apps.firstIndex(where: { $0.id == selected }) { MiniAppView(app: $store.apps[index]) } } }
}
struct MiniAppView: View {
    @Binding var app: MiniApp
    @State private var draft: [String: String] = [:]
    var body: some View { NavigationStack { Form { Section("Add record") { ForEach(app.fields, id: \.self) { field in TextField(field, text: Binding(get: { draft[field, default: ""] }, set: { draft[field] = $0 })) }; Button("Save record") { app.rows.append(draft); draft = [:] }.disabled(draft.values.allSatisfy(\.isEmpty)) }; Section("Records") { ForEach(app.rows.indices, id: \.self) { i in VStack(alignment: .leading) { ForEach(app.fields, id: \.self) { field in Text("\(field): \(app.rows[i][field, default: ""])") } } }.onDelete { app.rows.remove(atOffsets: $0) } } }.navigationTitle(app.title) } }
}
struct WorkflowsView: View {
    @EnvironmentObject var store: Store
    @State private var prompt = ""
    @State private var checked: Set<String> = []
    @State private var shortcut = ""
    @Environment(\.openURL) private var openURL
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 18) { Text("Automation Studio").font(.largeTitle.bold()); VStack(alignment: .leading) { TextField("Describe a routine", text: $prompt, axis: .vertical).lineLimit(2...5); Button("Generate workflow") { store.start(prompt, mode: "workflow") }.buttonStyle(.borderedProminent).disabled(store.busy || prompt.isEmpty) }.glass(); AgentProgressView(); ArtifactLibrary(kind: "workflow"); ForEach(store.workflows) { flow in VStack(alignment: .leading, spacing: 10) { Text(flow.title).font(.headline); Text("Manual checklist · not background automation").font(.caption); ForEach(Array(flow.steps.enumerated()), id: \.offset) { i, step in let key = "\(flow.id)-\(i)"; Button { if checked.contains(key) { checked.remove(key) } else { checked.insert(key) } } label: { HStack { Image(systemName: checked.contains(key) ? "checkmark.circle.fill" : "circle"); Text(step) } }.buttonStyle(.plain) } }.glass() }; VStack(alignment: .leading) { Text("Apple Shortcuts").font(.headline); TextField("Existing shortcut name", text: $shortcut); Button("Run installed shortcut") { var parts = URLComponents(); parts.scheme = "shortcuts"; parts.host = "run-shortcut"; parts.queryItems = [URLQueryItem(name: "name", value: shortcut)]; if let url = parts.url { openURL(url) } }.disabled(shortcut.isEmpty); Button("Open Shortcuts") { if let url = URL(string: "shortcuts://") { openURL(url) } } }.glass() }.padding(20) } }
}
struct ConnectView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject var store: Store
    @State private var phone = ""
    @State private var email = ""
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var event = ""
    @State private var date = Date()
    @State private var status = ""
    @State private var confirmCall = false
    @State private var showMail = false
    @State private var browser = "https://www.google.com"
    @State private var page: URL?
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 16) { Text("Connect").font(.largeTitle.bold()); VStack(alignment: .leading, spacing: 12) { Label("Phone", systemImage: "phone").font(.headline); TextField("Telephone number", text: $phone).keyboardType(.phonePad); Button("Prepare call") { confirmCall = true }.disabled(phone.isEmpty) }.glass(); VStack(alignment: .leading, spacing: 12) { Label("Mail composer", systemImage: "envelope").font(.headline); TextField("Recipient", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never); TextField("Subject", text: $subject); TextField("Message", text: $bodyText, axis: .vertical); Button("Review in Mail") { if MFMailComposeViewController.canSendMail() { showMail = true } else { status = "Set up an Apple Mail account first." } }.disabled(email.isEmpty) }.glass(); VStack(alignment: .leading, spacing: 12) { Label("Calendar", systemImage: "calendar").font(.headline); TextField("Event title", text: $event); DatePicker("Start", selection: $date); Button("Save 1-hour event") { Task { await saveEvent() } }.disabled(event.isEmpty) }.glass(); VStack(alignment: .leading) { Label("Notes", systemImage: "note.text").font(.headline); TextEditor(text: $store.notes).frame(minHeight: 100).scrollContentBackground(.hidden) }.glass(); VStack(alignment: .leading) { Label("Browser", systemImage: "globe").font(.headline); TextField("HTTPS URL", text: $browser).keyboardType(.URL).textInputAutocapitalization(.never); Button("Open page") { if let url = URL(string: browser), url.scheme == "https", url.host != nil { page = url } else { status = "Enter a valid HTTPS URL." } } }.glass(); Text(status).font(.caption) }.padding(20) }.alert("Place this call?", isPresented: $confirmCall) { Button("Call") { let number = phone.filter { "0123456789+".contains($0) }; if !number.isEmpty, let url = URL(string: "tel:\(number)") { openURL(url) } }; Button("Cancel", role: .cancel) {} } message: { Text(phone) }.sheet(isPresented: $showMail) { MailComposer(recipient: email, subject: subject, messageBody: bodyText) }.sheet(isPresented: Binding(get: { page != nil }, set: { if !$0 { page = nil } })) { if let page { WebPage(url: page) } } }
    @MainActor private func saveEvent() async { let db = EKEventStore(); do { guard try await db.requestFullAccessToEvents() else { status = "Calendar permission denied."; return }; guard let calendar = db.defaultCalendarForNewEvents else { status = "No writable default calendar."; return }; let item = EKEvent(eventStore: db); item.title = event; item.startDate = date; item.endDate = date.addingTimeInterval(3600); item.calendar = calendar; try db.save(item, span: .thisEvent); status = "Event saved."; event = "" } catch { status = error.localizedDescription } }
}
struct MailComposer: UIViewControllerRepresentable {
    let recipient: String; let subject: String; let messageBody: String
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(close: { dismiss() }) }
    func makeUIViewController(context: Context) -> MFMailComposeViewController { let vc = MFMailComposeViewController(); vc.mailComposeDelegate = context.coordinator; vc.setToRecipients([recipient]); vc.setSubject(subject); vc.setMessageBody(messageBody, isHTML: false); return vc }
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate { let close: () -> Void; init(close: @escaping () -> Void) { self.close = close }; func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) { close() } }
}
struct WebPage: UIViewRepresentable { let url: URL; func makeUIView(context: Context) -> WKWebView { let view = WKWebView(); view.load(URLRequest(url: url)); return view }; func updateUIView(_ uiView: WKWebView, context: Context) {} }
struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var importing = false
    var body: some View { NavigationStack { Form { Section("Local AI") { Text(store.status); Button("Import .litertlm model") { importing = true }.disabled(store.busy); Link("Find compatible models", destination: URL(string: "https://huggingface.co/litert-community")!); Text("No cloud inference. Small quantized models recommended; actual RAM usage depends on the model.").font(.caption) }; Section("Privacy") { Text("Chats and app records are stored locally. Mail and web connections use their respective services."); Button("Clear chat history", role: .destructive) { store.chat = [] }.disabled(store.busy) } }.navigationTitle("Settings").fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in switch result { case .success(let url): store.importModel(url); case .failure(let error): store.status = error.localizedDescription } } } }
}
