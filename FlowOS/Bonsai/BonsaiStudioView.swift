import SwiftUI
import UIKit

struct BonsaiStudioView: View {
    @EnvironmentObject var store:Store
    @ObservedObject var studio:BonsaiStudio
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scene
    @State private var confirmRemove=false
    @State private var selectedImage:URL?
    private func bytes(_ n:Int64)->String{ByteCountFormatter.string(fromByteCount:n,countStyle:.file)}
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16){
                    FlowSectionTitle(title:"ImageMaker",subtitle:"Bonsai Image 4B · Offline creation")
                    VStack(alignment:.leading,spacing:10){
                        HStack {
                            Image(systemName:"cpu").font(.title2)
                            VStack(alignment:.leading){Text("Bonsai · INT4").font(.headline);Text("LiteRT CPU / XNNPACK · 4 threads").font(.caption)}
                            Spacer()
                            Text(studio.ready ? "Ready":"Download").font(.caption.weight(.semibold))
                        }
                        Picker("Resolution",selection:$studio.size){Text("256 × 256 · Fast").tag(256);Text("512 × 512").tag(512)}.pickerStyle(.segmented).disabled(studio.generating || studio.downloading)
                        Text("Downloads continue on Wi-Fi when you lock your phone or switch apps. Reopen to verify the files. Do not force-quit FlowOS.").font(.caption)
                        ForEach(studio.required){file in
                            HStack {
                                Image(systemName:studio.readyFiles.contains(file.name) ? "checkmark.circle.fill":"arrow.down.circle")
                                Text(file.name).font(.caption).lineLimit(1)
                                Spacer();Text(bytes(file.bytes)).font(.caption.monospacedDigit())
                            }
                        }
                        Text("\(bytes(studio.stored)) installed · \(bytes(studio.needed)) remaining for selected size").font(.caption)
                        if studio.downloading {
                            ProgressView(value:studio.progress)
                            Text("\(Int(studio.progress*100))% · \(studio.detail)").font(.caption.monospacedDigit())
                            Button("Pause download"){studio.cancel()}
                        } else {
                            if !studio.ready {Button("Download / resume model"){studio.download()}.buttonStyle(FlowPrimary()).disabled(studio.manifest==nil || store.busy)}
                            if studio.stored>0{Button("Remove model files",role:.destructive){confirmRemove=true}.font(.caption).disabled(studio.generating || store.busy)}
                        }
                        Link("Source and license",destination:URL(string:"https://huggingface.co/litert-community/Bonsai-Image-ternary-4B")!).font(.caption)
                    }.glass()
                    VStack(alignment:.leading,spacing:12){
                        Text("Create").font(.title2.bold())
                        TextField("Describe an image…",text:$studio.prompt,axis:.vertical).lineLimit(4...7).padding(10).background(.white.opacity(0.6),in:RoundedRectangle(cornerRadius:16))
                        Stepper("Sampling steps: \(studio.steps)",value:$studio.steps,in:2...8)
                        HStack{
                            TextField("Seed",text:$studio.seed).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                            Button{studio.seed=String(UInt64.random(in:0...UInt64.max))}label:{Image(systemName:"dice").font(.title2)}.accessibilityLabel("Random seed")
                        }
                        if studio.generating {
                            ProgressView(value:studio.progress)
                            Text("Generation stage · \(Int(studio.progress*100))%").font(.caption)
                            Text(studio.detail).font(.caption.monospacedDigit())
                            Button("Stop after current step",role:.cancel){studio.cancel()}.buttonStyle(FlowPrimary())
                        }else{
                            Button("Generate image"){studio.generate(store:store)}.buttonStyle(FlowPrimary())
                                .disabled(!studio.ready || studio.downloading || store.busy || studio.prompt.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || UInt64(studio.seed)==nil)
                        }
                        Text(studio.status).font(.caption).textSelection(.enabled)
                        if let t=studio.lastSeconds{Text(String(format:"Measured generation: %.1f seconds",t)).font(.caption.monospacedDigit())}
                        Text("Experimental on iPhone 14 Pro Max. Keep FlowOS open. Generation may be stopped by iOS if memory is exhausted.").font(.caption)
                    }.glass().disabled(studio.downloading)
                    if let url=studio.output,let image=UIImage(contentsOfFile:url.path){
                        Image(uiImage:image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius:22))
                        ShareLink(item:url){Label("Share generated PNG",systemImage:"square.and.arrow.up")}.buttonStyle(FlowPrimary())
                    }
                    Text("Image gallery").font(.title2.bold())
                    if studio.gallery.isEmpty {Text("Your offline creations appear here.").font(.caption)}
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10){
                        ForEach(studio.gallery,id:\.self){url in
                            Button{selectedImage=url}label:{
                                if let image=UIImage(contentsOfFile:url.path){Image(uiImage:image).resizable().aspectRatio(1,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:16))}
                                else {Label("PNG",systemImage:"photo")}
                            }.buttonStyle(FlowPress())
                        }
                    }
                    Text("Created using Bonsai Image by Prism ML.").font(.caption)
                }.padding(20)
            }.background{FlowBackdrop(tab:2,busy:store.busy)}
            .navigationTitle("Media").navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){dismiss()}.disabled(studio.generating)}}
            .interactiveDismissDisabled(studio.generating)
            .confirmationDialog("Remove all Bonsai weights? Generated images will be retained.",isPresented:$confirmRemove){Button("Remove models",role:.destructive){studio.removeModels()}}
            .sheet(isPresented:Binding(get:{selectedImage != nil},set:{if !$0{selectedImage=nil}})){
                if let url=selectedImage,let image=UIImage(contentsOfFile:url.path){
                    VStack(spacing:16){Image(uiImage:image).resizable().scaledToFit();ShareLink(item:url);Button("Done"){selectedImage=nil}}.padding()
                }
            }
            .onChange(of:scene){_,value in if value == .background && studio.generating {studio.cancel()}; if value == .active {studio.syncDownloads()}}
            .onReceive(NotificationCenter.default.publisher(for:UIApplication.didReceiveMemoryWarningNotification)){_ in if studio.generating{studio.cancel()}}
        }
    }
}
