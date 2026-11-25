import SwiftUI

struct CloudProvidersView: View {
    @ObservedObject var hub:CloudHub
    @EnvironmentObject var store:Store
    @Environment(\.dismiss) private var dismiss
    @State private var selected:CloudProvider?
    @State private var task="chat"
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    FlowSectionTitle(title:"Cloud providers",subtitle:"Your keys. Your models. Your choice.")
                    Text("Optional internet inference. Prompts and selected conversation context go to the selected provider. Charges and retention depend on your API account. Local remains the default.").font(.caption).glass()
                    ForEach(CloudProvider.allCases) { p in
                        Button { selected=p } label:{
                            HStack(spacing:12) {
                                Image(systemName:p == .nvidia ? "cpu" : p == .gemini ? "sparkle" : "cloud").font(.title2).frame(width:44,height:44).liquidSurface(radius:20)
                                VStack(alignment:.leading) {
                                    Text(p.title).font(.headline)
                                    Text(hub.connected.contains(p) ? "Key saved · \(hub.models[p.rawValue]?.count ?? 0) models":"Not connected").font(.caption)
                                }
                                Spacer();Image(systemName:"chevron.right")
                            }.glass()
                        }.buttonStyle(FlowPress()).disabled(store.busy)
                    }
                    FlowSectionTitle(title:"Inference routing",subtitle:"Pick a different model for each task.")
                    Picker("Task",selection:$task) {
                        Text("Chat").tag("chat");Text("App builder").tag("app");Text("Workflows").tag("workflow");Text("Themes").tag("theme")
                    }
                    CloudRouteEditor(hub:hub,task:task).id(task)
                    VStack(alignment:.leading,spacing:10) {
                        Text("Usage recorded on this device").font(.headline)
                        ForEach(CloudProvider.allCases) { p in
                            let u=hub.ledger[p.rawValue] ?? CloudUsage()
                            VStack(alignment:.leading,spacing:3) {
                                Text(p.title).font(.subheadline.bold())
                                Text("\(u.input) input · \(u.output) output tokens").font(.caption.monospacedDigit())
                                if u.cached>0 || u.reasoning>0 {Text("\(u.cached) cached input · \(u.reasoning) reasoning").font(.caption)}
                            }
                        }
                        Text("Only usage returned by provider APIs is counted. Not a billing statement or spending limit.").font(.caption)
                    }.glass()
                }.padding(20)
            }.background { FlowBackdrop(tab:2,busy:store.busy) }
            .navigationTitle("Inference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done"){dismiss()} } }
            .sheet(item:$selected) { p in CloudProviderDetail(hub:hub,provider:p) }
        }
    }
}
struct CloudProviderDetail:View {
    @ObservedObject var hub:CloudHub
    let provider:CloudProvider
    @EnvironmentObject var store:Store
    @Environment(\.dismiss) private var dismiss
    @State private var key=""
    @State private var manual=""
    @State private var search=""
    @State private var disconnect=false
    var body:some View {
        NavigationStack {
            Form {
                Section("API connection") {
                    SecureField("Paste API key",text:$key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save key") {hub.save(key,provider:provider);key=""}.disabled(key.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || store.busy)
                    Link("Get an API key",destination:URL(string:provider.keysURL)!)
                    Button("Verify key & refresh models"){Task{await hub.refresh(provider)}}.disabled(!hub.connected.contains(provider) || hub.loading.contains(provider) || store.busy)
                    if hub.loading.contains(provider){ProgressView("Fetching available models")}
                    if let msg=hub.messages[provider.rawValue]{Text(msg).font(.caption)}
                    Button("Disconnect",role:.destructive){disconnect=true}.disabled(!hub.connected.contains(provider) || store.busy)
                }
                Section("Model catalog") {
                    TextField("Search models",text:$search)
                    TextField("Exact custom model ID",text:$manual).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Add model ID"){hub.addModel(manual,provider:provider);manual=""}.disabled(manual.isEmpty || store.busy)
                    ForEach((hub.models[provider.rawValue] ?? []).filter{search.isEmpty || ($0.name+" "+$0.id).localizedCaseInsensitiveContains(search)}) { m in
                        VStack(alignment:.leading,spacing:4) {
                            Text(m.name).font(.headline);Text(m.id).font(.caption2).textSelection(.enabled)
                            Text("Effort: "+m.efforts.map(\.title).joined(separator:", ")).font(.caption)
                            if let limit=m.outputLimit {Text("Model output limit: \(limit)").font(.caption)}
                            Menu("Assign model") {
                                ForEach(["chat","app","workflow","theme"],id:\.self){task in
                                    Button(task.capitalized){hub.setRoute(task,CloudRoute(provider:provider,model:m.id))}
                                }
                            }.disabled(!hub.connected.contains(provider) || store.busy)
                        }
                    }
                }
            }.navigationTitle(provider.title)
            .toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){key="";dismiss()}}}
            .confirmationDialog("Remove this provider key and its routes?",isPresented:$disconnect){Button("Disconnect",role:.destructive){hub.disconnect(provider)}}
        }
    }
}
struct CloudRouteEditor:View {
    @ObservedObject var hub:CloudHub
    let task:String
    @EnvironmentObject var store:Store
    @State private var provider=""
    @State private var modelID=""
    @State private var effort:CloudEffort = .automatic
    @State private var output=2048
    @State private var context=12000
    private var selected:CloudProvider?{CloudProvider(rawValue:provider)}
    private var choices:[CloudModel]{selected.map{hub.models[$0.rawValue] ?? []} ?? []}
    private var model:CloudModel?{choices.first{$0.id==modelID}}
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Active: "+(hub.route(task).map{$0.provider.title+" · "+$0.model} ?? "On-device model")).font(.caption.weight(.semibold))
            Picker("Provider",selection:$provider){
                Text("On device (private)").tag("")
                ForEach(CloudProvider.allCases.filter{hub.connected.contains($0)}){p in Text(p.title).tag(p.rawValue)}
            }
            if selected != nil {
                Picker("Model",selection:$modelID){
                    Text("Select model").tag("")
                    ForEach(choices){m in Text(m.name).tag(m.id)}
                }
                Picker("Reasoning effort",selection:$effort){
                    ForEach(model?.efforts ?? [.automatic]){e in Text(e.title).tag(e)}
                }
                Picker("Output token cap",selection:$output){
                    ForEach([512,1024,2048,4096,8192,16384,32768],id:\.self){n in Text("\(n)").tag(n)}
                }
                Picker("Context size (characters)",selection:$context){
                    ForEach([4000,12000,32000,64000,120000],id:\.self){n in Text("\(n)").tag(n)}
                }
                Text("Higher effort may increase billable reasoning and latency. The provider may impose lower limits.").font(.caption)
            }
            Button("Apply \(task.capitalized) route"){
                if let p=selected,!modelID.isEmpty {hub.setRoute(task,.init(provider:p,model:modelID,effort:effort,maxOutput:output,contextCharacters:context))}
                else if provider.isEmpty {hub.setRoute(task,nil)}
            }.buttonStyle(FlowPrimary()).disabled(store.busy || (selected != nil && modelID.isEmpty))
        }.glass()
        .onAppear {
            if let r=hub.route(task){provider=r.provider.rawValue;modelID=r.model;effort=r.effort;output=r.maxOutput;context=r.contextCharacters}
        }
        .onChange(of:provider){_,new in if !choices.contains(where:{$0.id==modelID}){modelID=""};if new.isEmpty{effort = .automatic}}
        .onChange(of:modelID){_,_ in if !(model?.efforts ?? [.automatic]).contains(effort){effort = .automatic}}
    }
}

struct ChatBackendPicker: View {
    @ObservedObject var hub:CloudHub
    let mode:String
    @EnvironmentObject var store:Store
    @State private var show=false
    var body:some View {
        Button { show=true } label: {
            HStack(spacing:8) {
                Image(systemName:hub.route(mode)==nil ? "iphone" : "cloud")
                VStack(alignment:.leading,spacing:2) {
                    Text(hub.route(mode).map{$0.provider.title+" · "+$0.model} ?? "On-device AI").font(.caption.weight(.semibold)).lineLimit(1)
                    if let r=hub.route(mode) {Text(r.effort.title+" · "+String(r.maxOutput)+" output cap").font(.caption2)}
                    else {Text("Local · no API charges").font(.caption2)}
                }
                Spacer()
                Image(systemName:"chevron.up.chevron.down").font(.caption)
            }.padding(10).liquidSurface(radius:20,interactive:true)
        }.buttonStyle(FlowPress()).disabled(store.busy)
        .sheet(isPresented:$show) {
            NavigationStack {
                ScrollView { VStack(spacing:16) {
                    CloudRouteEditor(hub:hub,task:mode)
                    Text("Connect providers and refresh available models in Settings → Cloud providers.").font(.caption)
                }.padding(20) }
                .navigationTitle("Select model").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction){Button("Done"){show=false}} }
            }.presentationDetents([.large])
        }
    }
}
