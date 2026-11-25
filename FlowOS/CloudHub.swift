import Foundation
import SwiftUI
import Security

enum CloudKeychain {
    private static let service="com.flowos.personal.cloud"
    private static func query(_ p:CloudProvider)->[String:Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:p.rawValue]
    }
    static func get(_ p:CloudProvider)->String? {
        var q=query(p);q[kSecReturnData as String]=true;q[kSecMatchLimit as String]=kSecMatchLimitOne
        var value:CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary,&value)==errSecSuccess,let data=value as? Data else {return nil}
        return String(data:data,encoding:.utf8)
    }
    static func set(_ key:String,provider:CloudProvider)throws {
        let q=query(provider), data=Data(key.utf8)
        let status=SecItemUpdate(q as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if status==errSecSuccess {return}
        guard status==errSecItemNotFound else {throw NSError(domain:NSOSStatusErrorDomain,code:Int(status))}
        var add=q;add[kSecValueData as String]=data;add[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let result=SecItemAdd(add as CFDictionary,nil)
        guard result==errSecSuccess else {throw NSError(domain:NSOSStatusErrorDomain,code:Int(result))}
    }
    static func remove(_ p:CloudProvider) {SecItemDelete(query(p) as CFDictionary)}
}
@MainActor final class CloudHub:ObservableObject {
    @Published private(set) var connected:Set<CloudProvider>=[]
    @Published private(set) var models:[String:[CloudModel]]=[:]
    @Published private(set) var routes:[String:CloudRoute]=[:]
    @Published private(set) var loading:Set<CloudProvider>=[]
    @Published var messages:[String:String]=[:]
    @Published private(set) var ledger:[String:CloudUsage]=[:]
    @Published var lastUsage:CloudUsage?
    let planAuth=ChatGPTPlanAuth()
    private var catalogOwner:String?
    private let session=URLSession(configuration:.ephemeral,delegate:PlanNoRedirect(),delegateQueue:nil)
    init() {
        connected=Set(CloudProvider.allCases.filter{$0 != .chatgptPlan && CloudKeychain.get($0) != nil})
        let defaults=UserDefaults.standard
        if let data=defaults.data(forKey:"flow.cloud.models"),let value=try? JSONDecoder().decode([String:[CloudModel]].self,from:data){models=value}
        if let data=defaults.data(forKey:"flow.cloud.routes"),let value=try? JSONDecoder().decode([String:CloudRoute].self,from:data){routes=value}
        if let data=defaults.data(forKey:"flow.cloud.usage"),let value=try? JSONDecoder().decode([String:CloudUsage].self,from:data){ledger=value}
        models[CloudProvider.chatgptPlan.rawValue]=nil
        syncPlan()
    }
    private func persist<T:Encodable>(_ value:T,_ name:String) {if let data=try? JSONEncoder().encode(value){UserDefaults.standard.set(data,forKey:name)}}
    func syncPlan() {
        let id=planAuth.active?.id
        if catalogOwner != id { models[CloudProvider.chatgptPlan.rawValue]=nil; catalogOwner=id }
        if id != nil { connected.insert(.chatgptPlan) } else { connected.remove(.chatgptPlan) }
    }
    func save(_ key:String,provider:CloudProvider) {
        guard provider != .chatgptPlan else {return}
        let clean=key.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty,!clean.contains(where:{$0.isWhitespace}) else {messages[provider.rawValue]="Enter a valid single API key.";return}
        do {try CloudKeychain.set(clean,provider:provider);connected.insert(provider);messages[provider.rawValue]="Saved on this device. Refresh models to verify access."}
        catch {messages[provider.rawValue]="Keychain storage failed."}
    }
    func disconnect(_ p:CloudProvider) {
        guard p != .chatgptPlan else {return}
        CloudKeychain.remove(p);connected.remove(p);models[p.rawValue]=nil
        routes=routes.filter{$0.value.provider != p};persist(routes,"flow.cloud.routes");persist(models,"flow.cloud.models")
        messages[p.rawValue]="Disconnected."
    }
    func route(_ task:String)->CloudRoute? {routes[task]}
    func setRoute(_ task:String,_ route:CloudRoute?) {
        var selected=route
        if selected?.provider == .chatgptPlan {
            guard let id=planAuth.active?.id,let model=selected?.model,models[CloudProvider.chatgptPlan.rawValue]?.contains(where:{$0.id==model})==true else {return}
            selected?.planProfileID=id
        }
        routes[task]=selected;persist(routes,"flow.cloud.routes")
    }
    func model(_ route:CloudRoute)->CloudModel {
        models[route.provider.rawValue]?.first{$0.id==route.model} ?? CloudModel.infer(provider:route.provider,id:route.model)
    }
    func addModel(_ id:String,provider:CloudProvider) {
        guard provider != .chatgptPlan else {return}
        let clean=id.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty,clean.count<=180,clean.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,47,95,58].contains($0) }) else {return}
        if !(models[provider.rawValue] ?? []).contains(where:{$0.id==clean}) {
            models[provider.rawValue,default:[]].append(.infer(provider:provider,id:clean))
            persist(models,"flow.cloud.models")
        }
    }
    private func request(_ url:URL,provider:CloudProvider,key:String)->URLRequest {
        var req=URLRequest(url:url);req.timeoutInterval=120
        switch provider {
        case .anthropic:req.setValue(key,forHTTPHeaderField:"x-api-key");req.setValue("2023-06-01",forHTTPHeaderField:"anthropic-version")
        case .gemini:req.setValue(key,forHTTPHeaderField:"x-goog-api-key")
        default:req.setValue("Bearer "+key,forHTTPHeaderField:"Authorization")
        }
        return req
    }
    private func fail(_ message:String)->NSError {NSError(domain:"FlowOS.Cloud",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
    private func checked(_ response:URLResponse)throws {
        guard let http=response as? HTTPURLResponse else {throw fail("Invalid provider response.")}
        guard (200...299).contains(http.statusCode) else {
            let explanation:String
            switch http.statusCode {case 400:explanation="Unsupported model or settings. Try provider default effort.";case 401,403:explanation="Check API key and account access.";case 404:explanation="Model or endpoint unavailable.";case 429:explanation="Rate limit or quota reached. Check provider billing.";default:explanation="Provider request failed."}
            throw fail("HTTP \(http.statusCode): \(explanation)")
        }
    }
    func refresh(_ p:CloudProvider) async {
        if p == .chatgptPlan {await refreshPlan();return}
        guard !loading.contains(p),let key=CloudKeychain.get(p) else {return}
        loading.insert(p);defer{loading.remove(p)}
        do {
            var results:[CloudModel]=[], next:String?=p.modelsURL
            for _ in 0..<10 {
                guard let raw=next,let url=URL(string:raw) else {break}
                let (data,response)=try await session.data(for:request(url,provider:p,key:key));try checked(response)
                guard let object=try JSONSerialization.jsonObject(with:data) as? [String:Any] else {throw fail("Invalid model catalog.")}
                let rows=(object[p == .gemini ? "models":"data"] as? [[String:Any]]) ?? []
                for row in rows {
                    guard let rawID=row[p == .gemini ? "name":"id"] as? String else {continue}
                    let id=p == .gemini && rawID.hasPrefix("models/") ? String(rawID.dropFirst(7)):rawID
                    if p == .gemini && !(row["supportedGenerationMethods"] as? [String] ?? []).contains("generateContent") {continue}
                    if p == .openai && ["embedding","whisper","tts","dall-e","image","realtime","moderation","audio","transcribe","sora"].contains(where:{id.contains($0)}) {continue}
                    var m=CloudModel.infer(provider:p,id:id,name:row["display_name"] as? String ?? row["displayName"] as? String)
                    m.inputLimit=row["inputTokenLimit"] as? Int ?? row["max_input_tokens"] as? Int
                    m.outputLimit=row["outputTokenLimit"] as? Int ?? row["max_tokens"] as? Int
                    if p == .anthropic,let capabilities=row["capabilities"] as? [String:Any] {
                        let thinking=capabilities["thinking"] as? [String:Any]
                        let types=thinking?["types"] as? [String:Any]
                        let adaptive=types?["adaptive"] as? [String:Any]
                        let effort=capabilities["effort"] as? [String:Any]
                        if adaptive?["supported"] as? Bool == true {
                            m.thinking="adaptive"
                            for level in [CloudEffort.low,.medium,.high,.xhigh,.max] {
                                if (effort?[level.rawValue] as? [String:Any])?["supported"] as? Bool == true {m.efforts.append(level)}
                            }
                        }
                    }
                    results.append(m)
                }
                next=nil
                if p == .gemini,let token=object["nextPageToken"] as? String {
                    var parts=URLComponents(string:p.modelsURL)!;parts.queryItems=(parts.queryItems ?? [])+[URLQueryItem(name:"pageToken",value:token)];next=parts.url?.absoluteString
                } else if p == .anthropic,object["has_more"] as? Bool == true,let last=object["last_id"] as? String {
                    var parts=URLComponents(string:p.modelsURL)!;parts.queryItems=(parts.queryItems ?? [])+[URLQueryItem(name:"after_id",value:last)];next=parts.url?.absoluteString
                }
            }
            var seen=Set<String>();models[p.rawValue]=results.filter{seen.insert($0.id).inserted}.sorted{$0.id<$1.id}
            persist(models,"flow.cloud.models");messages[p.rawValue]="\(results.count) models returned. Individual inference access may vary."
        } catch {messages[p.rawValue]=error.localizedDescription}
    }
    private func refreshPlan() async {
        syncPlan(); let p=CloudProvider.chatgptPlan
        guard !loading.contains(p),let id=planAuth.active?.id else {return}
        loading.insert(p);defer{loading.remove(p)}
        do {
            let token=try await planAuth.accessToken(for:id)
            let (data,response)=try await session.data(for:request(URL(string:p.modelsURL)!,provider:p,key:token));try checked(response)
            guard let object=try JSONSerialization.jsonObject(with:data) as? [String:Any],let rows=object["models"] as? [[String:Any]],planAuth.active?.id==id else {throw fail("Account catalog unavailable.")}
            var seen=Set<String>()
            models[p.rawValue]=rows.compactMap { row in
                guard row["visibility"] as? String=="list",let slug=row["slug"] as? String,seen.insert(slug).inserted else {return nil}
                return CloudModel.infer(provider:p,id:slug,name:row["display_name"] as? String)
            }
            messages[p.rawValue]="Refreshed account-specific models."
        } catch {messages[p.rawValue]=error.localizedDescription}
    }
    func stream(route:CloudRoute,turns:[CloudTurn],system:String,onChunk:(String)->Void,onStage:(String)->Void) async throws -> String {
        let p=route.provider
        let key:String
        if p == .chatgptPlan {
            guard let id=route.planProfileID,id==planAuth.active?.id else {throw fail("Re-select the ChatGPT account and model. No other account will be used.")}
            if models[p.rawValue]==nil {await refreshPlan()}
            guard models[p.rawValue]?.contains(where:{$0.id==route.model})==true else {throw fail("Refresh the model catalog and choose an available ChatGPT model.")}
            key=try await planAuth.accessToken(for:id)
        } else {
            guard let saved=CloudKeychain.get(p) else {throw fail("Connect this provider in Model Hub first.")};key=saved
        }
        let m=model(route)
        let path:String
        switch p {
        case .openai,.chatgptPlan:path="https://api.openai.com/v1/responses"
        case .anthropic:path="https://api.anthropic.com/v1/messages"
        case .nvidia:path="https://integrate.api.nvidia.com/v1/chat/completions"
        case .gemini:
            guard let encoded=m.id.addingPercentEncoding(withAllowedCharacters:.alphanumerics.union(CharacterSet(charactersIn:"-._"))) else {throw fail("Invalid Gemini model.")}
            path="https://generativelanguage.googleapis.com/v1beta/models/\(encoded):streamGenerateContent?alt=sse"
        }
        guard let url=URL(string:path) else {throw fail("Invalid endpoint.")}
        var req=request(url,provider:p,key:key);req.httpMethod="POST";req.setValue("application/json",forHTTPHeaderField:"Content-Type");req.setValue("text/event-stream",forHTTPHeaderField:"Accept")
        let contextCap=min(route.contextCharacters,(m.inputLimit ?? 100000)*3)
        req.httpBody=try JSONSerialization.data(withJSONObject:CloudPayload.build(provider:p,model:m,route:route,turns:CloudPayload.bounded(turns,limit:contextCap),system:system))
        lastUsage=nil;onStage("Connecting to \(p.title) · \(m.id)")
        let (bytes,response)=try await session.bytes(for:req);try checked(response)
        onStage("Streaming from \(p.title)")
        var result="",usage=CloudUsage(),hasUsage=false,finished=false,reasoning=false
        defer {
            if hasUsage {
                lastUsage=usage; let id=p.rawValue
                var total=ledger[id] ?? CloudUsage();total.input+=usage.input;total.output+=usage.output;total.reasoning+=usage.reasoning;total.cached+=usage.cached
                ledger[id]=total;persist(ledger,"flow.cloud.usage")
            }
        }
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else {continue}
            let raw=line.dropFirst(5).trimmingCharacters(in:.whitespaces)
            if raw=="[DONE]" {finished=true;break}
            guard let data=raw.data(using:.utf8),let event=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else {continue}
            if event["error"] != nil || event["type"] as? String=="error" {throw fail("Provider returned a streaming error.")}
            var delta=""
            switch p {
            case .openai,.chatgptPlan:
                let type=event["type"] as? String ?? ""
                if type=="response.output_text.delta" {delta=event["delta"] as? String ?? ""}
                if type=="response.failed" || type=="response.incomplete" {throw fail("Response failed or reached its output limit.")}
                if type.contains("reasoning") && !reasoning {reasoning=true;onStage("Provider reasoning")}
                if type=="response.completed" {
                    finished=true
                    if let u=(event["response"] as? [String:Any])?["usage"] as? [String:Any] {
                        usage.input=u["input_tokens"] as? Int ?? 0;usage.output=u["output_tokens"] as? Int ?? 0
                        usage.reasoning=(u["output_tokens_details"] as? [String:Any])?["reasoning_tokens"] as? Int ?? 0
                        usage.cached=(u["input_tokens_details"] as? [String:Any])?["cached_tokens"] as? Int ?? 0;hasUsage=true
                    }
                }
            case .anthropic:
                let type=event["type"] as? String ?? ""
                if let d=event["delta"] as? [String:Any] {
                    if d["type"] as? String=="text_delta" {delta=d["text"] as? String ?? ""}
                    if d["type"] as? String=="thinking_delta" && !reasoning {reasoning=true;onStage("Provider reasoning")}
                    if d["stop_reason"] as? String=="max_tokens" {throw fail("Response reached its output limit.")}
                }
                if let u=(event["message"] as? [String:Any])?["usage"] as? [String:Any] {
                    usage.cached=u["cache_read_input_tokens"] as? Int ?? 0;usage.input=(u["input_tokens"] as? Int ?? 0)+usage.cached+(u["cache_creation_input_tokens"] as? Int ?? 0);hasUsage=true
                }
                if let u=event["usage"] as? [String:Any] {usage.output=u["output_tokens"] as? Int ?? usage.output;hasUsage=true}
                if type=="message_stop" {finished=true}
            case .gemini:
                let candidate=(event["candidates"] as? [[String:Any]])?.first
                for part in (candidate?["content"] as? [String:Any])?["parts"] as? [[String:Any]] ?? [] {
                    if part["thought"] as? Bool==true {if !reasoning {reasoning=true;onStage("Provider reasoning")}}
                    else {delta += part["text"] as? String ?? ""}
                }
                if let reason=candidate?["finishReason"] as? String {
                    if reason != "STOP" {throw fail("Gemini ended with \(reason).")}
                    finished=true
                }
                if let u=event["usageMetadata"] as? [String:Any] {
                    usage.input=u["promptTokenCount"] as? Int ?? 0;usage.reasoning=u["thoughtsTokenCount"] as? Int ?? 0
                    usage.output=(u["candidatesTokenCount"] as? Int ?? 0)+usage.reasoning;usage.cached=u["cachedContentTokenCount"] as? Int ?? 0;hasUsage=true
                }
            case .nvidia:
                if let choice=(event["choices"] as? [[String:Any]])?.first {
                    let d=choice["delta"] as? [String:Any]
                    delta=d?["content"] as? String ?? ""
                    if d?["reasoning_content"] != nil && !reasoning {reasoning=true;onStage("Provider reasoning")}
                    if let reason=choice["finish_reason"] as? String {
                        if reason=="length" {throw fail("Response reached its output limit.")}
                        finished=true
                    }
                }
                if let u=event["usage"] as? [String:Any] {
                    usage.input=u["prompt_tokens"] as? Int ?? 0;usage.output=u["completion_tokens"] as? Int ?? 0;hasUsage=true
                }
            }
            if !delta.isEmpty {result+=delta;onChunk(result)}
        }
        guard finished,!result.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {throw fail("No complete text response received.")}
        return result
    }
}
