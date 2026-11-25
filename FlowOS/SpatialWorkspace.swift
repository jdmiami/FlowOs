import SwiftUI

// A zoomable card canvas. Drag cards to arrange them; drag empty space to pan.
struct SpatialWorkspace: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduced
    @AppStorage("flow.spatial.positions") private var saved = "{}"
    @State private var positions: [String: [Double]] = [:]
    @State private var pan = CGSize.zero
    @GestureState private var panDelta = CGSize.zero
    @State private var zoom: CGFloat = 0.8
    @GestureState private var magnification: CGFloat = 1
    @State private var selected: Artifact?
    @State private var installed: UUID?
    @State private var listMode = false
    private var scale: CGFloat { max(0.45,min(1.5,zoom*magnification)) }
    private var nodes: [WorkspaceNode] {
        store.apps.map { WorkspaceNode(id:"app-"+$0.id.uuidString,title:$0.title,detail:"\($0.rows.count) records",symbol:"square.stack",app:$0.id) } +
        store.artifacts.prefix(30).map { WorkspaceNode(id:"artifact-"+$0.id.uuidString,title:$0.title,detail:$0.state,symbol:"doc.text",artifact:$0) }
    }
    private func point(_ node: WorkspaceNode, _ index: Int) -> CGPoint {
        if let p = positions[node.id],p.count == 2 { return CGPoint(x:p[0],y:p[1]) }
        return CGPoint(x:CGFloat(index%2)*174-87,y:CGFloat(index/2)*142-75)
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(positions),let text = String(data:data,encoding:.utf8) { saved = text }
    }
    private func open(_ node: WorkspaceNode) {
        if let artifact = node.artifact { selected = artifact } else { installed = node.app }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing:8) {
                HStack {
                    Text("Spatial workspace").font(.system(.title,design:.serif))
                    Spacer()
                    Button { listMode.toggle() } label: { Image(systemName:listMode ? "square.grid.2x2" : "list.bullet").frame(width:44,height:44).liquidSurface(radius:22,interactive:true) }
                    Button { withAnimation(reduced ? nil : FlowMotion.hero) { pan = .zero; zoom = 0.8; positions = [:] }; persist() } label: { Image(systemName:"scope").frame(width:44,height:44).liquidSurface(radius:22,interactive:true) }.accessibilityLabel("Reset layout")
                }.padding(.horizontal,18)
                if nodes.isEmpty {
                    ContentUnavailableView("Your space is empty",systemImage:"square.stack",description:Text("Create an app or artifact in Labs."))
                } else if listMode {
                    ScrollView { VStack { ForEach(nodes) { node in Button { open(node) } label: { Label(node.title,systemImage:node.symbol).glass() }.buttonStyle(FlowPress()) } }.padding() }
                } else {
                    GeometryReader { geo in
                        ZStack {
                            Color.clear.contentShape(Rectangle()).gesture(DragGesture().updating($panDelta) { value,state,_ in state = value.translation }.onEnded { value in pan.width += value.translation.width; pan.height += value.translation.height })
                            ZStack {
                                ForEach(Array(nodes.enumerated()),id:\.element.id) { index,node in
                                    let p = point(node,index)
                                    SpatialCard(node:node,scale:scale,onOpen:{ open(node) },onMove:{ delta in
                                        positions[node.id] = [Double(p.x+delta.width),Double(p.y+delta.height)]; persist()
                                    }).position(x:geo.size.width/2+p.x,y:geo.size.height/2+p.y)
                                }
                            }.scaleEffect(scale).offset(x:pan.width+panDelta.width,y:pan.height+panDelta.height)
                            .allowsHitTesting(true)
                        }.clipped()
                        .simultaneousGesture(MagnifyGesture().updating($magnification) { value,state,_ in state = value.magnification }.onEnded { value in zoom = max(0.45,min(1.5,zoom*value.magnification)) })
                    }
                    HStack {
                        Text("Pinch to zoom · drag cards").font(.caption)
                        Spacer()
                        Text("\(Int(scale*100))%").font(.caption.monospacedDigit())
                    }.padding(.horizontal,20)
                }
            }.padding(.bottom,16)
            .background { FlowBackdrop(tab:2,busy:store.busy) }
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(item:$selected) { artifact in ArtifactDetail(id:artifact.id).environmentObject(store) }
            .sheet(isPresented:Binding(get:{ installed != nil },set:{ if !$0 { installed = nil } })) {
                if let installed,let index = store.apps.firstIndex(where:{$0.id == installed}) { MiniAppView(app:$store.apps[index]) }
            }
            .onAppear { positions = (try? JSONDecoder().decode([String:[Double]].self,from:Data(saved.utf8))) ?? [:] }
        }
    }
}
private struct WorkspaceNode: Identifiable {
    var id: String
    var title: String
    var detail: String
    var symbol: String
    var app: UUID? = nil
    var artifact: Artifact? = nil
}
private struct SpatialCard: View {
    let node: WorkspaceNode
    let scale: CGFloat
    let onOpen: () -> Void
    let onMove: (CGSize) -> Void
    @GestureState private var drag = CGSize.zero
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Button(action:onOpen) {
            VStack(alignment:.leading,spacing:9) {
                Image(systemName:node.symbol).font(.title2)
                Text(node.title).font(.headline).lineLimit(2)
                Text(node.detail).font(.caption).lineLimit(1)
            }.frame(width:133,height:100,alignment:.leading).padding(12).liquidSurface(radius:25,interactive:true)
        }.buttonStyle(FlowPress())
        .offset(x:drag.width/scale,y:drag.height/scale)
        .rotationEffect(.degrees(reduced ? 0 : Double(drag.width)/80))
        .simultaneousGesture(DragGesture(minimumDistance:10).updating($drag) { value,state,_ in state = value.translation }.onEnded { value in onMove(CGSize(width:value.translation.width/scale,height:value.translation.height/scale)) })
        .accessibilityHint("Opens the application. List view is available for navigation.")
    }
}
