import SwiftUI
import WebKit

@MainActor final class HTMLStateVault {
    static let shared=HTMLStateVault()
    private let folder=URL.applicationSupportDirectory.appending(path:"FlowOS/WebAppState",directoryHint:.isDirectory)
    private func url(_ id:UUID)->URL {folder.appending(path:id.uuidString+".json")}
    func read(_ id:UUID)->String {
        guard let data=try? Data(contentsOf:url(id)),data.count<=65536,let s=String(data:data,encoding:.utf8) else{return "null"}
        return s
    }
    func save(_ state:String,for id:UUID)throws {
        let data=Data(state.utf8)
        guard data.count<=65536 else{throw CocoaError(.fileWriteOutOfSpace)}
        _=try JSONSerialization.jsonObject(with:data,options:.fragmentsAllowed)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try data.write(to:url(id),options:[.atomic,.completeFileProtection])
    }
}
@MainActor final class HTMLRuntime: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let web:WKWebView
    private(set) var report:HTMLReport?
    private var errors:[String]=[]
    private var ready=false
    private var active=true
    private var allowInitial=true
    private var startup:Task<Void,Never>?
    private var lastWrite=Date.distantPast
    private var pendingState:String?
    private var flushTask:Task<Void,Never>?
    private let appID:UUID?
    private let onReport:(HTMLReport)->Void
    init(appID:UUID?,onReport:@escaping(HTMLReport)->Void) {
        self.appID=appID;self.onReport=onReport
        let config=WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically=false
        config.defaultWebpagePreferences.allowsContentJavaScript=true
        web=WKWebView(frame:CGRect(x:0,y:0,width:390,height:650),configuration:config)
        super.init()
        web.navigationDelegate=self;web.uiDelegate=self
        web.configuration.userContentController.add(self,name:"flowRuntime")
        web.isOpaque=false;web.backgroundColor = .clear
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsLinkPreview=false
    }
    func load(_ document:HTMLDocument) {
        guard active else{return}
        let state=appID.map{HTMLStateVault.shared.read($0)} ?? "null"
        startup=Task { [weak self] in
            // Refuse to run if the additional network/file blocking layer cannot compile.
            do {
                let rules:WKContentRuleList=try await withCheckedThrowingContinuation { continuation in
                    WKContentRuleListStore.default().compileContentRuleList(forIdentifier:"flow-runtime-deny-external-v1",encodedContentRuleList:"[{\"trigger\":{\"url-filter\":\"^http:\"},\"action\":{\"type\":\"block\"}},{\"trigger\":{\"url-filter\":\"^https:\"},\"action\":{\"type\":\"block\"}},{\"trigger\":{\"url-filter\":\"^ws:\"},\"action\":{\"type\":\"block\"}},{\"trigger\":{\"url-filter\":\"^wss:\"},\"action\":{\"type\":\"block\"}},{\"trigger\":{\"url-filter\":\"^ftp:\"},\"action\":{\"type\":\"block\"}},{\"trigger\":{\"url-filter\":\"^file:\"},\"action\":{\"type\":\"block\"}}]") { rules,error in
                        if let rules {continuation.resume(returning:rules)} else {continuation.resume(throwing:error ?? CocoaError(.fileReadUnknown))}
                    }
                }
                guard let self,self.active,!Task.isCancelled else{return}
                self.web.configuration.userContentController.add(rules)
                self.web.loadHTMLString(HTMLHarness.wrapper(document,state:state),baseURL:nil)
            }catch{self?.fail("Offline sandbox could not initialize.")}
        }
    }
    private func emit(_ r:HTMLReport){report=r;onReport(r)}
    private func fail(_ error:String) {
        if errors.count<12{errors.append(String(error.prefix(400)))}
        emit(.init(passed:false,checks:ready ? ["WebKit loaded"]:[],errors:errors))
    }
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage) {
        guard active,message.frameInfo.isMainFrame,message.name=="flowRuntime",
              let m=message.body as? [String:Any],let kind=m["kind"] as? String else{return}
        switch kind {
        case "error":fail(m["value"] as? String ?? "JavaScript error")
        case "ready":
            guard !ready,let info=m["value"] as? [String:Any] else{return}
            ready=true
            if info["visible"] as? Bool != true {fail("No visible interface rendered.")}
            if info["test"] as? String=="failed"{fail("Generated self-test failed.")}
            var checks=["WebKit loaded"]
            if info["visible"] as? Bool == true {checks.append("Visible interface")}
            if errors.isEmpty {checks.append("No startup script errors")}
            if info["test"] as? String=="passed"{checks.append("Generated self-test passed")}
            else{checks.append("No self-test supplied · manual interaction testing needed")}
            emit(.init(passed:errors.isEmpty,checks:checks,errors:errors))
        case "save":
            guard appID != nil,let state=m["value"] as? String,state.utf8.count<=65536 else{return}
            pendingState=state
            if Date().timeIntervalSince(lastWrite)>0.4 {flush()}
            else if flushTask==nil {
                flushTask=Task{[weak self] in
                    try? await Task.sleep(for:.milliseconds(450))
                    guard !Task.isCancelled else{return}
                    self?.flushTask=nil;self?.flush()
                }
            }
        default:break
        }
    }
    private func flush(){
        guard let id=appID,let value=pendingState else{return}
        pendingState=nil;lastWrite=Date()
        do{try HTMLStateVault.shared.save(value,for:id)}catch{fail("Could not save local app data.")}
    }
    func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){
        guard let frame=action.targetFrame,let url=action.request.url else{decisionHandler(.cancel);return}
        let target=url.absoluteString
        if frame.isMainFrame {
            if allowInitial && target=="about:blank"{allowInitial=false;decisionHandler(.allow)}
            else{decisionHandler(.cancel)}
        }else if (target=="about:srcdoc" || target=="about:blank") && action.navigationType == .other {
            decisionHandler(.allow)
        }else{decisionHandler(.cancel)}
    }
    func webView(_ webView:WKWebView,createWebViewWith configuration:WKWebViewConfiguration,for navigationAction:WKNavigationAction,windowFeatures:WKWindowFeatures)->WKWebView?{nil}
    func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error){fail("WebKit load failed: "+error.localizedDescription)}
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error){fail("WebKit startup failed: "+error.localizedDescription)}
    func webViewWebContentProcessDidTerminate(_ webView:WKWebView){fail("Web process stopped. Simplify the application and retry.")}
    func close(){
        guard active else{return};active=false;startup?.cancel();flushTask?.cancel();flush()
        web.stopLoading();web.configuration.userContentController.removeScriptMessageHandler(forName:"flowRuntime")
        web.navigationDelegate=nil;web.uiDelegate=nil
    }
    static func verify(_ doc:HTMLDocument)async throws->HTMLReport{
        let runtime=HTMLRuntime(appID:nil,onReport:{_ in})
        defer{runtime.close()}
        runtime.load(doc)
        for _ in 0..<100 {
            try Task.checkCancellation()
            if let r=runtime.report {
                if !r.passed{return r}
                // Let deferred startup errors surface before passing.
                try await Task.sleep(for:.milliseconds(550))
                return runtime.report ?? r
            }
            try await Task.sleep(for:.milliseconds(100))
        }
        return .init(passed:false,checks:[],errors:["WebKit did not report readiness within 10 seconds."])
    }
}

struct HTMLAppSurface:UIViewRepresentable {
    let document:HTMLDocument
    let appID:UUID?
    var dark:Bool=false
    let onReport:(HTMLReport)->Void
    func makeCoordinator()->Coordinator{Coordinator()}
    func makeUIView(context:Context)->WKWebView{
        let r=HTMLRuntime(appID:appID,onReport:onReport)
        context.coordinator.runtime=r;r.web.overrideUserInterfaceStyle=dark ? .dark:.light;r.load(document);return r.web
    }
    func updateUIView(_ uiView:WKWebView,context:Context){uiView.overrideUserInterfaceStyle=dark ? .dark:.light}
    static func dismantleUIView(_ uiView:WKWebView,coordinator:Coordinator){coordinator.runtime?.close();coordinator.runtime=nil}
    @MainActor final class Coordinator{var runtime:HTMLRuntime?}
}
