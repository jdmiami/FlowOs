import SwiftUI
import UniformTypeIdentifiers
import EventKit
import MessageUI
import UIKit
import WebKit

@main struct FlowOSApp: App {
    @UIApplicationDelegateAdaptor(FlowDownloadDelegate.self) private var downloadDelegate
    @StateObject private var store = Store()
    var body: some Scene { WindowGroup { LivingRoot().environmentObject(store) } }
}

struct LivingRoot: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var scene
    @Environment(\.accessibilityReduceMotion) private var reduced
    @AppStorage("flow.effects") private var effects = true
    @State private var thermal = ProcessInfo.processInfo.thermalState
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    var body: some View {
        RootView()
            .environment(\.flowTheme,store.theme)
            .environment(\.renderBudget,RenderBudget(lowPower:lowPower,thermal:thermal,busy:store.busy,reducedMotion:reduced,effectsEnabled:effects,foreground:scene == .active))
            .onReceive(NotificationCenter.default.publisher(for:ProcessInfo.thermalStateDidChangeNotification)) { _ in thermal = ProcessInfo.processInfo.thermalState }
            .onReceive(NotificationCenter.default.publisher(for:.NSProcessInfoPowerStateDidChange)) { _ in lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
    }
}
enum Palette {
    static let lavender = Color(red: 0.76, green: 0.73, blue: 0.93)
    static let peach = Color(red: 0.98, green: 0.82, blue: 0.80)
    static let mint = Color(red: 0.72, green: 0.89, blue: 0.87)
    static let ink = Color(red: 0.15, green: 0.16, blue: 0.23)
}
extension View { func glass() -> some View { modifier(FlowCard()) } }
struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduced
    @SceneStorage("flow.tab") private var tab = 0
    @State private var settings = false
    @State private var spatial = false
    @State private var media = false
    @Environment(\.renderBudget) private var budget
    @State private var cloudSettings = false
    @State private var chatDraft = ""
    @State private var entered = false
    let tabs = [("Home", "sparkle"), ("Chat", "bubble.left"), ("Labs", "square.stack.3d.up"), ("Connect", "phone"), ("Flow", "point.3.connected.trianglepath.dotted")]
    private func navigate(_ index: Int, mode: String? = nil) {
        withAnimation(reduced ? .easeOut(duration: 0.14) : FlowMotion.hero) { tab = index }; FlowFeedback.shared.play()
    }
    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .center) {
                Button { navigate(0) } label: {
                    Text("flow.").font(.system(size: 39, weight: .semibold, design: .serif)).tracking(-2.4)
                }.buttonStyle(FlowPress()).accessibilityLabel("FlowOS home")
                Spacer()
                FlowGlassGroup {
                    HStack(spacing: 10) {
                Button {
                    if store.busy { if store.activeMode == "image" {media=true} else { navigate(store.activeMode == "app" ? 2 : store.activeMode == "workflow" ? 4 : 1) } } else { cloudSettings = true }
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(store.busy ? Palette.lavender : store.model != nil ? Color.green.opacity(0.8) : Color.gray).frame(width: 7, height: 7)
                        Text(store.busy ? "Working" : "Models").font(.caption.weight(.semibold))
                    }.padding(.horizontal, 12).frame(minHeight: 40).liquidSurface(radius: 22, interactive: true)
                }.buttonStyle(FlowPress())
                Button { settings = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 19, weight: .medium)).frame(width: 46, height: 46).liquidSurface(radius: 25, interactive: true)
                }.buttonStyle(FlowPress()).accessibilityLabel("Settings")
                    }
                }
            }.padding(.horizontal, 22).padding(.top, 4)
            Group {
                switch tab {
                case 0: home
                case 1: ChatView(text: $chatDraft)
                case 2: LabsView()
                case 3: ConnectView()
                default: WorkflowsView()
                }
            }.id(tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(reduced ? .opacity : .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)).combined(with: .offset(y: 14)), removal: .opacity))
            FlowDock(selection: $tab, items: tabs)
        }
        .foregroundStyle(Palette.ink).tint(Palette.ink)
        .background { FlowBackdrop(tab: tab, busy: store.busy) }
        .preferredColorScheme(.light)
        .sheet(isPresented: $settings) { SettingsView().environmentObject(store).presentationDragIndicator(.visible).presentationCornerRadius(34) }
        .sheet(isPresented:$cloudSettings) { CloudProvidersView(hub:store.cloud).environmentObject(store) }
        .alert(item:Binding(get:{settings ? nil : store.pendingCloud},set:{if !settings {store.pendingCloud=$0}})) { approval in
            cloudApprovalAlert(approval,store:store)
        }
        .sheet(isPresented:$media) { BonsaiStudioView(studio:store.bonsai).environmentObject(store).presentationDragIndicator(.visible) }
        .sheet(isPresented:$spatial) { SpatialWorkspace().environmentObject(store).presentationDragIndicator(.visible) }
        .onAppear {
            withAnimation(reduced ? .easeOut(duration: 0.15) : FlowMotion.hero) { entered = true }
        }
    }
    var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                VStack(spacing: 1) {
                    LivingPortal(busy:store.busy,stage:store.stage,navigate:{ navigate($0) }).frame(maxWidth:.infinity)
                    Text(store.busy ? "INTELLIGENCE IN MOTION" : "YOUR PERSONAL INTELLIGENCE")
                        .font(.caption2.weight(.semibold)).tracking(2.5).foregroundStyle(Palette.ink.opacity(0.62))
                }.scaleEffect(entered || reduced ? 1 : 0.78).opacity(entered ? 1 : 0)
                Text("What would you\nlike to do today?")
                    .font(.system(size: 38, weight: .regular, design: .serif)).tracking(-1.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Button { navigate(1, mode: "chat") } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "sparkle").font(.title2)
                        Text("Start a conversation…").font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .semibold))
                    }.padding(19).liquidSurface(radius: 30, interactive: true, tint: Palette.lavender.opacity(0.25))
                }.buttonStyle(FlowPress())
                HStack {
                    Text("Your space").font(.system(.title2, design: .serif))
                    Spacer()
                    Text("\(store.apps.count) apps · \(store.workflows.count) flows").font(.caption.monospacedDigit())
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    homeTile("Create", "Build with AI", "plus.square.on.square", Palette.peach, 2, nil)
                    homeTile("Labs", "Apps & artifacts", "square.stack.3d.up", Palette.lavender, 2, nil)
                    homeTile("Connect", "Calls & email", "phone.bubble", Palette.mint, 3, nil)
                    homeTile("Automate", "Design a flow", "point.3.connected.trianglepath.dotted", Palette.lavender, 4, nil)
                }
                Button { media = true } label: { Label("ImageMaker · Bonsai",systemImage:"photo.on.rectangle.angled").frame(maxWidth:.infinity) }.buttonStyle(FlowPrimary())
                Button { spatial = true } label: { Label("Open spatial workspace",systemImage:"square.on.square").frame(maxWidth:.infinity) }.buttonStyle(FlowPrimary())
                Text(budget.label).font(.caption.monospaced()).foregroundStyle(.secondary)
                if store.busy { AgentProgressView() }
                Text("PRIVATE BY DESIGN · LOCAL MODEL").font(.caption2.weight(.medium)).tracking(1.2).foregroundStyle(.secondary)
            }.padding(.horizontal, 22).padding(.bottom, 16)
        }.scrollIndicators(.hidden)
    }
    private func homeTile(_ title: String, _ subtitle: String, _ icon: String, _ color: Color, _ target: Int, _ mode: String?) -> some View {
        Button { navigate(target, mode: mode) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon).font(.system(size: 23, weight: .medium))
                        .frame(width: 48, height: 48)
                        .background(color.opacity(0.58), in: RoundedRectangle(cornerRadius: 18))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
                }
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }.glass()
        }.buttonStyle(FlowPress())
    }
}
struct ChatView: View {
    @EnvironmentObject var store: Store
    @Binding var text: String
    @State private var modelPicker = false
    @FocusState private var composerFocused: Bool
    @State private var follow = true
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Intelligence").font(.system(.title, design: .serif))
                Spacer()
                Toggle("Follow", isOn: $follow).toggleStyle(.switch).labelsHidden()
                    .accessibilityLabel("Follow streaming output")
            }.padding(.horizontal, 20)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if store.chat.isEmpty { Text("Your conversation stays on your phone.").glass() }
                        ForEach(store.chat) { line in
                            ChatBubble(line: line)
                        }
                        if store.activeMode == "chat" { AgentProgressView() }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(16)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: store.live) { _, _ in if follow { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: store.chat.count) { _, _ in if follow { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            VStack(spacing: 8) {
                ChatBackendPicker(hub:store.cloud,mode:"chat")
                HStack {
                    TextField("Ask anything", text: $text, axis: .vertical).lineLimit(1...4).focused($composerFocused)
                    if store.busy && store.activeMode == "chat" {
                        Button { store.stop() } label: { Image(systemName: "stop.circle.fill").font(.largeTitle) }.accessibilityLabel("Stop generation")
                    } else {
                        Button { let value = text; text = ""; composerFocused = false; store.start(value, mode: "chat") } label: { Image(systemName: "arrow.up.circle.fill").font(.largeTitle) }.disabled(store.busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }.glass().padding(.horizontal, 16).padding(.bottom, 8)
        }
    }
}
struct ChatBubble: View {
    let line: ChatLine
    @Environment(\.accessibilityReduceTransparency) private var solid
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !line.user {
                Label("Flow", systemImage: "sparkle").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(line.text).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(line.user ? Palette.lavender.opacity(0.37) : Color.white.opacity(solid ? 1 : 0.72), in: RoundedRectangle(cornerRadius: 25))
        .overlay { RoundedRectangle(cornerRadius: 25).strokeBorder(.white.opacity(0.8)) }
        .padding(line.user ? .leading : .trailing, 22)
    }
}
struct LabsView: View {
    @EnvironmentObject var store: Store
    @SceneStorage("flow.labs.prompt") private var prompt = ""
    @SceneStorage("flow.labs.title") private var title = ""
    @SceneStorage("flow.labs.fields") private var fields = "Name, Notes"
    @State private var selected: UUID?
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 18) { FlowSectionTitle(title: "AI Labs", subtitle: "Build, preview and evolve your own applications."); VStack(alignment: .leading) { ChatBackendPicker(hub:store.cloud,mode:"app"); Text("Build real HTML, CSS and JavaScript. For complex apps, select a cloud coding model with at least 8,192 output tokens.").font(.caption); TextField("Describe the app, layout and interactions you want", text: $prompt, axis: .vertical).lineLimit(2...5); Button("Build interactive app") { store.start(prompt, mode: "app") }.buttonStyle(FlowPrimary()).disabled(store.busy || prompt.isEmpty) }.glass(); DisclosureGroup("Create manually") { TextField("App name", text: $title); TextField("Fields separated by commas", text: $fields); Button("Create app") { let plan = Plan(action: "app", title: title, fields: fields.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }); if let app = Validation.miniApp(plan) { store.apps.append(app); title = "" } }.disabled(title.isEmpty) }.glass(); if store.activeMode == "app" { AgentProgressView() }; HTMLStudio(); DisclosureGroup("Legacy native tracker artifacts") { ArtifactLibrary(kind:"app") }; Text("Native trackers").font(.title2.bold()); ForEach(store.apps) { app in Button { selected = app.id } label: { HStack { Image(systemName: "square.stack"); Text(app.title); Spacer(); Text("\(app.rows.count)"); Image(systemName: "chevron.right") }.glass() }.buttonStyle(FlowPress()) } }.padding(20) }.sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) { if let selected, let index = store.apps.firstIndex(where: { $0.id == selected }) { MiniAppView(app: $store.apps[index]) } } }
}
struct MiniAppView: View {
    @Binding var app: MiniApp
    @Environment(\.dismiss) private var dismiss
    @State private var draft: [String:String] = [:]
    @State private var search = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    FlowSectionTitle(title:app.title,subtitle:"Your generated application")
                    GeneratedDashboard(rows:app.rows,components:app.components ?? [])
                    VStack(alignment:.leading,spacing:12) {
                        Text("Add record").font(.headline)
                        GeneratedFields(fields:app.fields,components:app.components ?? [],draft:$draft)
                        Button("Save record") { app.rows.append(draft); draft = [:]; FlowFeedback.shared.play() }.buttonStyle(FlowPrimary()).disabled(draft.values.allSatisfy(\.isEmpty))
                    }.glass()
                    TextField("Find records",text:$search).textFieldStyle(.roundedBorder)
                    ForEach(app.rows.indices.filter { i in search.isEmpty || app.rows[i].values.contains { $0.localizedCaseInsensitiveContains(search) } },id:\.self) { i in
                        VStack(alignment:.leading,spacing:8) {
                            ForEach(app.fields,id:\.self) { field in
                                HStack { Text(field).font(.caption); Spacer(); Text(app.rows[i][field,default:""]).font(.subheadline).textSelection(.enabled) }
                            }
                            Button("Delete record",role:.destructive) { app.rows.remove(at:i) }.font(.caption)
                        }.glass()
                    }
                }.padding(20)
            }.background { FlowBackdrop(tab:2,busy:false) }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
struct WorkflowsView: View {
    @EnvironmentObject var store: Store
    @SceneStorage("flow.workflow.prompt") private var prompt = ""
    @State private var checked: Set<String> = []
    @State private var shortcut = ""
    @Environment(\.openURL) private var openURL
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 18) { FlowSectionTitle(title: "Automation Studio", subtitle: "Turn intention into repeatable workflows."); VStack(alignment: .leading) { ChatBackendPicker(hub:store.cloud,mode:"workflow"); TextField("Describe a routine", text: $prompt, axis: .vertical).lineLimit(2...5); Button("Generate workflow") { store.start(prompt, mode: "workflow") }.buttonStyle(FlowPrimary()).disabled(store.busy || prompt.isEmpty) }.glass(); if store.activeMode == "workflow" { AgentProgressView() }; ArtifactLibrary(kind: "workflow"); ForEach(store.workflows) { flow in VStack(alignment: .leading, spacing: 10) { Text(flow.title).font(.headline); Text("Manual checklist · not background automation").font(.caption); ForEach(Array(flow.steps.enumerated()), id: \.offset) { i, step in let key = "\(flow.id)-\(i)"; Button { if checked.contains(key) { checked.remove(key) } else { checked.insert(key) } } label: { HStack { Image(systemName: checked.contains(key) ? "checkmark.circle.fill" : "circle"); Text(step) } }.buttonStyle(FlowPress()) } }.glass() }; VStack(alignment: .leading) { Text("Apple Shortcuts").font(.headline); TextField("Existing shortcut name", text: $shortcut); Button("Run installed shortcut") { var parts = URLComponents(); parts.scheme = "shortcuts"; parts.host = "run-shortcut"; parts.queryItems = [URLQueryItem(name: "name", value: shortcut)]; if let url = parts.url { openURL(url) } }.buttonStyle(FlowPrimary()).disabled(shortcut.isEmpty); Button("Open Shortcuts") { if let url = URL(string: "shortcuts://") { openURL(url) } } }.glass() }.padding(20) } }
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
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 16) { FlowSectionTitle(title: "Connect", subtitle: "Your communications and personal tools."); VStack(alignment: .leading, spacing: 12) { Label("Phone", systemImage: "phone").font(.headline); TextField("Telephone number", text: $phone).keyboardType(.phonePad); Button("Prepare call") { confirmCall = true }.buttonStyle(FlowPrimary()).disabled(phone.isEmpty) }.glass(); VStack(alignment: .leading, spacing: 12) { Label("Mail composer", systemImage: "envelope").font(.headline); TextField("Recipient", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never); TextField("Subject", text: $subject); TextField("Message", text: $bodyText, axis: .vertical); Button("Review in Mail") { if MFMailComposeViewController.canSendMail() { showMail = true } else { status = "Set up an Apple Mail account first." } }.buttonStyle(FlowPrimary()).disabled(email.isEmpty) }.glass(); VStack(alignment: .leading, spacing: 12) { Label("Calendar", systemImage: "calendar").font(.headline); TextField("Event title", text: $event); DatePicker("Start", selection: $date); Button("Save 1-hour event") { Task { await saveEvent() } }.buttonStyle(FlowPrimary()).disabled(event.isEmpty) }.glass(); VStack(alignment: .leading) { Label("Notes", systemImage: "note.text").font(.headline); TextEditor(text: $store.notes).frame(minHeight: 100).scrollContentBackground(.hidden) }.glass(); VStack(alignment: .leading) { Label("Browser", systemImage: "globe").font(.headline); TextField("HTTPS URL", text: $browser).keyboardType(.URL).textInputAutocapitalization(.never); Button("Open page") { if let url = URL(string: browser), url.scheme == "https", url.host != nil { page = url } else { status = "Enter a valid HTTPS URL." } } }.glass(); Text(status).font(.caption) }.padding(20) }.alert("Place this call?", isPresented: $confirmCall) { Button("Call") { let number = phone.filter { "0123456789+".contains($0) }; if !number.isEmpty, let url = URL(string: "tel:\(number)") { openURL(url) } }; Button("Cancel", role: .cancel) {} } message: { Text(phone) }.sheet(isPresented: $showMail) { MailComposer(recipient: email, subject: subject, messageBody: bodyText) }.sheet(isPresented: Binding(get: { page != nil }, set: { if !$0 { page = nil } })) { if let page { WebPage(url: page) } } }
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
    @State private var providers = false
    var body: some View { NavigationStack { Form { Section("Inference") { Button("Cloud providers & model routing") { providers=true } }; Section("Local AI") { Text(store.status); Button("Import .litertlm model") { importing = true }.disabled(store.busy); Link("Find compatible models", destination: URL(string: "https://huggingface.co/litert-community")!); Text("No cloud inference. Small quantized models recommended; actual RAM usage depends on the model.").font(.caption) }; ThemeStudio(); Section("Privacy") { Text("Chats and app records are stored locally. Mail and web connections use their respective services."); Button("Clear chat history", role: .destructive) { store.chat = [] }.disabled(store.busy) } }.navigationTitle("Settings").alert(item:$store.pendingCloud) { approval in cloudApprovalAlert(approval,store:store) }.sheet(isPresented:$providers) { CloudProvidersView(hub:store.cloud).environmentObject(store) }.fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in switch result { case .success(let url): store.importModel(url); case .failure(let error): store.status = error.localizedDescription } } } }
}

@MainActor func cloudApprovalAlert(_ approval:Store.CloudApproval,store:Store)->Alert {
    let plan=approval.route.provider == .chatgptPlan
    let account=plan ? (store.cloud.planAuth.active?.email ?? "No selected account") : ""
    let billing=plan ? "Uses your authorized ChatGPT allowance or credits. Account: \(account)." : "API charges may apply."
    let scope=approval.mode == "app" ? " Up to two model requests (generation and validation repair). Previous source is included for revisions." : ""
    return Alert(title:Text("Send to \(approval.route.provider.title)?"),message:Text("\(approval.route.model) will receive this request\(approval.mode == "chat" ? " and bounded chat history" : ""). \(billing)\(scope)"),primaryButton:.default(Text("Send")){store.approveCloud(approval)},secondaryButton:.cancel())
}
