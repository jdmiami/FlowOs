import SwiftUI
import UniformTypeIdentifiers

import UIKit

struct HTMLStudio:View {
    @EnvironmentObject var store:Store
    @State private var selected:Artifact?
    @State private var query=""
    @State private var installedOnly=false
    private var items:[Artifact] {
        store.artifacts.filter { $0.isHTML && (!installedOnly || $0.installedID != nil) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {Text("Web applications").font(.title2.bold());Spacer();Text("\(items.count)").font(.caption)}
            TextField("Find apps and revisions",text:$query).textFieldStyle(.roundedBorder)
            Toggle("Installed only",isOn:$installedOnly).font(.caption)
            if items.isEmpty {Text("Generate an application or try an offline starter.").font(.caption).foregroundStyle(.secondary)}
            ForEach(items) { item in
                Button {selected=item} label:{
                    HStack(spacing:12) {
                        Image(systemName:item.canRunHTML ? "macwindow" : "doc.text.magnifyingglass").font(.title2).frame(width:45,height:45).background(Palette.lavender.opacity(0.4),in:RoundedRectangle(cornerRadius:16))
                        VStack(alignment:.leading,spacing:3) {
                            Text(item.title).font(.headline)
                            Text(item.state+(item.revisionOf == nil ? "" : " · Revision")).font(.caption)
                        }
                        Spacer()
                        if item.canRunHTML {Image(systemName:"play.circle.fill").font(.title2)}
                        else {Image(systemName:"chevron.right")}
                    }.glass()
                }.buttonStyle(FlowPress())
            }
            DisclosureGroup("Offline starters · no AI required") {
                Button("Interactive calculator"){Task{await store.starterHTML(HTMLStarters.calculator)}}.disabled(store.busy)
                Button("Inventory dashboard"){Task{await store.starterHTML(HTMLStarters.inventory)}}.disabled(store.busy)
            }.glass()
        }
        .sheet(item:$selected){item in HTMLArtifactView(id:item.id).environmentObject(store)}
    }
}
struct HTMLArtifactView:View {
    @EnvironmentObject var store:Store
    @Environment(\.dismiss) private var dismiss
    let id:UUID
    @State private var tab="Run"
    @State private var source=""
    @State private var change=""
    @State private var verification:HTMLReport?
    @State private var runtimeReport:HTMLReport?
    @State private var verifying=false
    @State private var export=false
    @State private var dark=false
    @State private var compact=false
    @State private var reload=UUID()
    @State private var message=""
    @State private var selectedRevision:Artifact?
    var artifact:Artifact?{store.artifacts.first{$0.id==id}}
    var body:some View {
        NavigationStack {
            if let artifact {
                VStack(spacing:10) {
                    HStack {
                        VStack(alignment:.leading,spacing:3) {
                            Text(artifact.title).font(.system(.title2,design:.serif)).lineLimit(2)
                            Text(artifact.state).font(.caption)
                        }
                        Spacer()
                        if artifact.canRunHTML {Button {store.installHTML(id)} label:{Image(systemName:artifact.installedID == nil ? "plus.circle":"checkmark.circle.fill").font(.title2)}.disabled(artifact.installedID != nil).accessibilityLabel("Install in Labs")}
                    }.padding(.horizontal,16)
                    FlowModePicker(selection:$tab,options:[("Run","App"),("Code","Code"),("Tests","Tests"),("Revise","Revise")]).padding(.horizontal,12)
                    if tab=="Run" {
                        if artifact.canRunHTML,let doc=HTMLHarness.parse(artifact.source).0 {
                            HStack {
                                Toggle("Dark",isOn:$dark).toggleStyle(.switch).font(.caption)
                                Button(compact ? "Full size":"Compact"){compact.toggle()}.font(.caption)
                                Spacer()
                                Button("Reload"){reload=UUID();runtimeReport=nil}
                            }.padding(.horizontal,16)
                            if let r=runtimeReport,!r.passed {
                                Text(r.errors.joined(separator:" · ")).font(.caption).foregroundStyle(.red).padding(.horizontal,16)
                            }
                            HTMLAppSurface(document:doc,appID:id,dark:dark,onReport:{runtimeReport=$0})
                                .id(reload).environment(\.colorScheme,dark ? .dark:.light)
                                .frame(maxWidth:.infinity,maxHeight:compact ? 450:.infinity)
                            if compact {Spacer(minLength:0)}
                        }else{
                            ContentUnavailableView("Draft needs repair",systemImage:"exclamationmark.triangle",description:Text("Inspect the tests, edit source, or ask the coding model to fix the application."))
                        }
                    }else if tab=="Code" {
                        VStack(alignment:.leading,spacing:10) {
                            TextEditor(text:$source).font(.system(.caption,design:.monospaced)).autocorrectionDisabled().textInputAutocapitalization(.never).scrollContentBackground(.hidden).padding(8).background(Color.white,in:RoundedRectangle(cornerRadius:16))
                            HStack {
                                Button("Copy"){UIPasteboard.general.string=source}
                                Spacer()
                                Button("Validate & save copy"){
                                    verifying=true
                                    Task{verification=await store.saveHTMLSource(source,from:id);verifying=false;if verification?.passed==true{message="New runnable revision saved in Labs."};tab="Tests"}
                                }.disabled(verifying || store.busy)
                                if verifying{ProgressView()}
                            }
                            if artifact.canRunHTML {Button("Export standalone HTML"){export=true}.buttonStyle(FlowPrimary())}
                            Text("Export uses the last validated source, not unsaved edits. App data stays local.").font(.caption2)
                        }.padding(16)
                    }else if tab=="Tests" {
                        ScrollView {
                            VStack(alignment:.leading,spacing:12) {
                                let report=verification ?? artifact.htmlReport
                                Text(report?.passed==true ? "Startup checks passed":"Not ready").font(.title2.bold())
                                ForEach(Array((report?.checks ?? []).enumerated()),id:\.offset){_,check in Label(check,systemImage:"checkmark.circle")}
                                ForEach(Array((report?.errors ?? []).enumerated()),id:\.offset){_,error in Label(error,systemImage:"exclamationmark.triangle").foregroundStyle(.red)}
                                Text("Startup validation is not proof that every feature or calculation is correct. Test the app yourself before relying on it.").font(.caption)
                                Text(message).font(.caption)
                            }.padding(20)
                        }
                    }else{
                        ScrollView {
                            VStack(alignment:.leading,spacing:14) {
                                Text("Improve this version").font(.title2.bold())
                                TextField("Describe changes or bugs",text:$change,axis:.vertical).lineLimit(3...7).glass()
                                ChatBackendPicker(hub:store.cloud,mode:"app")
                                Text("The previous source is included in the request. A new copy is created; the original and its data remain unchanged.").font(.caption)
                                Button("Build revision"){
                                    let request=change.trimmingCharacters(in:.whitespacesAndNewlines)
                                    dismiss();Task {try? await Task.sleep(for:.milliseconds(350));store.start(request,mode:"app",parentID:id)}
                                }.buttonStyle(FlowPrimary()).disabled(store.busy || change.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                                Text("Related versions").font(.headline)
                                ForEach(store.artifacts.filter{$0.isHTML && ($0.revisionOf==id || $0.id==artifact.revisionOf)}) { item in
                                    Button {selectedRevision=item} label:{HStack{Text(item.title);Spacer();Text(item.state).font(.caption)}}.glass()
                                }
                            }.padding(20)
                        }
                    }
                }.background{FlowBackdrop(tab:2,busy:store.busy)}
                    .toolbar{ToolbarItem(placement:.cancellationAction){Button("Done"){dismiss()}}}
                    .navigationBarTitleDisplayMode(.inline)
                    .onAppear {source=artifact.source;if !artifact.canRunHTML{tab="Tests"}}
                    .fileExporter(isPresented:$export,document:SourceDocument(text:HTMLHarness.parse(artifact.source).0.map{HTMLHarness.prepared($0,embedded:false)} ?? artifact.source),contentType:.html,defaultFilename:"FlowOS-\(artifact.id.uuidString).html"){result in
                        switch result {case .success:message="HTML exported.";case .failure(let e):message=e.localizedDescription}
                    }
                    .sheet(item:$selectedRevision){item in HTMLArtifactView(id:item.id).environmentObject(store)}
            }else{Text("App unavailable")}
        }
    }
}

enum HTMLStarters {
    static let calculator = """
    <!DOCTYPE html><html><head><title>Margin Studio</title><style>
    h1{font-size:32px;letter-spacing:-1px;margin:0}small{color:var(--muted-foreground)}.panel{background:var(--card);border:1px solid var(--border);border-radius:24px;padding:18px;margin:16px 0}label{display:block;margin:12px 0}input{width:100%;border:1px solid var(--border);border-radius:12px;background:var(--content);padding:8px}output{font-size:40px;font-weight:700;color:var(--primary)}.bar{height:12px;background:var(--secondary);border-radius:99px;overflow:hidden}.bar i{display:block;height:100%;background:var(--chart-2);transition:width .6s cubic-bezier(.2,1.3,.4,1)}
    </style></head><body><small>FINANCIAL TOOL</small><h1>Margin Studio</h1><div class="panel"><label>Sale price <input id="price" type="number" min="0" step=".01" value="10"></label><label>Cost <input id="cost" type="number" min="0" step=".01" value="4"></label></div><div class="panel"><small>Gross margin</small><br><output id="margin">60%</output><div class="bar"><i id="bar"></i></div><p id="profit"></p></div><script>
    const p=document.getElementById('price'),c=document.getElementById('cost'),m=document.getElementById('margin'),b=document.getElementById('bar'),o=document.getElementById('profit');const old=FlowOS.load();if(old){p.value=old.p;c.value=old.c}function margin(a,z){return a>0?(a-z)/a*100:0}function render(){let a=Number(p.value),z=Number(c.value);if(!Number.isFinite(a)||!Number.isFinite(z)||a<=0||z<0){m.textContent='—';b.style.width='0%';o.textContent='Enter a positive sale price and nonnegative cost.';return}let v=margin(a,z);m.textContent=v.toFixed(1)+'%';b.style.width=Math.min(100,Math.max(0,v))+'%';o.textContent='Gross profit: $'+(a-z).toFixed(2);FlowOS.save({p:a,c:z})}p.oninput=c.oninput=render;window.flowSelfTest=()=>margin(10,4)===60&&margin(0,1)===0;render();
    </script></body></html>
    """
    static let inventory = """
    <!DOCTYPE html><html><head><title>Inventory Studio</title><style>
    h1{font-size:30px;letter-spacing:-1px;margin:0}small{color:var(--muted-foreground)}.panel{background:var(--card);border:1px solid var(--border);border-radius:22px;padding:16px;margin:14px 0}input{width:100%;border:1px solid var(--border);border-radius:12px;background:var(--content);padding:8px;margin:5px 0}button{background:var(--primary);color:var(--primary-foreground);border:0;border-radius:14px;padding:10px 14px}button:active{transform:scale(.95)}.row{display:flex;align-items:center;justify-content:space-between;gap:8px;border-bottom:1px solid var(--border);padding:10px 0}.metric{font-size:36px;font-weight:700;color:var(--primary)}.track{height:8px;background:var(--secondary);border-radius:8px}.track i{display:block;height:100%;background:var(--chart-2);border-radius:8px;transition:width .5s cubic-bezier(.2,1.3,.4,1)}
    </style></head><body><small>OPERATIONS</small><h1>Inventory Studio</h1><section class="panel"><small>Stock value</small><div id="total" class="metric">$0.00</div><div id="count"></div></section><form id="add" class="panel"><label>Product<input id="name" required maxlength="80"></label><label>Quantity<input id="qty" type="number" min="0" step="1" required></label><label>Unit cost<input id="cost" type="number" min="0" step=".01" required></label><button>Add record</button></form><div class="panel"><label>Search<input id="find" type="search"></label><div id="rows"></div></div><script>
    const el=id=>document.getElementById(id);let rows=FlowOS.load();if(!Array.isArray(rows))rows=[];const total=r=>r.reduce((s,x)=>s+x.q*x.c,0);function render(){el('total').textContent='$'+total(rows).toFixed(2);el('count').textContent=rows.length+' products';const box=el('rows');box.replaceChildren();const max=Math.max(1,...rows.map(x=>x.q));rows.forEach((x,i)=>{if(!x.n.toLowerCase().includes(el('find').value.toLowerCase()))return;const r=document.createElement('div');r.className='row';const info=document.createElement('div');info.style.flex='1';const title=document.createElement('strong');title.textContent=x.n;const v=document.createElement('div');v.textContent=x.q+' units · $'+x.c.toFixed(2);const track=document.createElement('div');track.className='track';const bar=document.createElement('i');bar.style.width=(100*x.q/max)+'%';track.append(bar);info.append(title,v,track);const edit=document.createElement('button');edit.type='button';edit.textContent='Edit';edit.onclick=()=>{const q=prompt('Quantity',x.q);if(q!==null&&q.trim()!==''&&Number.isFinite(Number(q))&&Number(q)>=0){x.q=Number(q);save()}};const del=document.createElement('button');del.type='button';del.textContent='Delete';del.onclick=()=>{rows.splice(i,1);save()};r.append(info,edit,del);box.append(r)});if(!box.children.length)box.textContent='No matching records.'}function save(){FlowOS.save(rows);render()}el('add').onsubmit=e=>{e.preventDefault();const n=el('name').value.trim(),q=Number(el('qty').value),c=Number(el('cost').value);if(n&&Number.isFinite(q)&&Number.isFinite(c)&&q>=0&&c>=0){rows.push({n,q,c});e.target.reset();save()}};el('find').oninput=render;window.flowSelfTest=()=>total([{q:2,c:3},{q:1,c:4}])===10;render();
    </script></body></html>
    """
}
