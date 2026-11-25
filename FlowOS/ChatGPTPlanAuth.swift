import Foundation
import SwiftUI
import Security
import CryptoKit
import Network
import SafariServices

// Official Sign in with ChatGPT public-client flow. No passwords, cookies,
// client secret, private ChatGPT endpoints, or remote credential storage.
enum PlanAuthError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(s)=self { return s }; return nil }
}
struct PlanProfile: Codable, Identifiable {
    var id: String { clientID }
    var clientID: String
    var subject: String
    var email: String
    var accessToken: String
    var refreshToken: String
    var idToken: String
    var scopes: Set<String>
    var expires: Date
    var enabled: Bool { scopes.contains("chatgpt.tokens.use.direct") && !accessToken.isEmpty }
}
private enum PlanVault {
    static let query: [String:Any] = [
        kSecClass as String:kSecClassGenericPassword,
        kSecAttrService as String:"com.flowos.personal.chatgpt-plan",
        kSecAttrAccount as String:"profiles-v1"
    ]
    static func read() -> [PlanProfile] {
        var q=query; q[kSecReturnData as String]=true; q[kSecMatchLimit as String]=kSecMatchLimitOne
        var value:CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary,&value)==errSecSuccess,let d=value as? Data else {return []}
        return (try? JSONDecoder().decode([PlanProfile].self,from:d)) ?? []
    }
    static func write(_ profiles:[PlanProfile]) throws {
        let d=try JSONEncoder().encode(profiles)
        let status=SecItemUpdate(query as CFDictionary,[kSecValueData as String:d] as CFDictionary)
        if status==errSecSuccess {return}
        guard status==errSecItemNotFound else {throw PlanAuthError.invalid("Could not update protected credentials.")}
        var q=query; q[kSecValueData as String]=d; q[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(q as CFDictionary,nil)==errSecSuccess else {throw PlanAuthError.invalid("Could not save protected credentials.")}
    }
}
enum PlanOAuth {
    static let issuer="https://auth.openai.com"
    static let resource="https://api.openai.com/v1"
    static let tokenURL=URL(string:issuer+"/api/accounts/oauth/token")!
    static let revokeURL=URL(string:issuer+"/api/accounts/oauth/revoke")!
    static let jwksURL=URL(string:issuer+"/.well-known/jwks.json")!
    static func base64URL(_ d:Data)->String { d.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"") }
    static func decode(_ s:String)->Data? {
        var b=s.replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")
        b += String(repeating:"=",count:(4-b.count%4)%4)
        return Data(base64Encoded:b)
    }
    static func random() throws -> String {
        var bytes=[UInt8](repeating:0,count:32)
        let status=bytes.withUnsafeMutableBytes { buffer in SecRandomCopyBytes(kSecRandomDefault,buffer.count,buffer.baseAddress!) }
        guard status==errSecSuccess else {throw PlanAuthError.invalid("Random generator unavailable.")}
        return base64URL(Data(bytes))
    }
    static func form(_ values:[String:String])->Data {
        let allowed=CharacterSet.alphanumerics.union(CharacterSet(charactersIn:"-._~"))
        func enc(_ s:String)->String {s.addingPercentEncoding(withAllowedCharacters:allowed) ?? ""}
        return Data(values.keys.sorted().map{enc($0)+"="+enc(values[$0] ?? "")}.joined(separator:"&").utf8)
    }
    static func der(_ tag:UInt8,_ value:Data)->Data {
        let n=value.count
        var length=Data()
        if n<128 {length.append(UInt8(n))}
        else {
            var bytes=[UInt8](); var x=n
            while x>0 {bytes.insert(UInt8(x&255),at:0);x >>= 8}
            length.append(UInt8(128+bytes.count)); length.append(contentsOf:bytes)
        }
        return Data([tag])+length+value
    }
    static func integer(_ raw:Data)->Data {
        var bytes=Array(raw.drop(while:{$0==0}))
        if bytes.isEmpty {bytes=[0]}
        if bytes[0]&128 != 0 {bytes.insert(0,at:0)}
        return der(2,Data(bytes))
    }
    static func identity(_ jwt:String,clientID:String,nonce:String,session:URLSession) async throws -> (String,String) {
        let p=jwt.split(separator:".",omittingEmptySubsequences:false).map(String.init)
        guard p.count==3,let h=decode(p[0]),let body=decode(p[1]),let signature=decode(p[2]),
              let header=try JSONSerialization.jsonObject(with:h) as? [String:Any],
              header["alg"] as? String=="RS256",let kid=header["kid"] as? String,
              let claims=try JSONSerialization.jsonObject(with:body) as? [String:Any] else {throw PlanAuthError.invalid("Invalid identity token.")}
        let (data,response)=try await session.data(from:jwksURL)
        guard (response as? HTTPURLResponse)?.statusCode==200,
              let jwks=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let keys=jwks["keys"] as? [[String:Any]],
              let key=keys.first(where:{$0["kid"] as? String==kid && $0["kty"] as? String=="RSA"}),
              let n=decode(key["n"] as? String ?? ""),let e=decode(key["e"] as? String ?? ""),
              n.count>=256,!e.isEmpty else {throw PlanAuthError.invalid("Could not verify OpenAI signing key.")}
        let rsa=der(0x30,integer(n)+integer(e))
        let attrs:[String:Any]=[kSecAttrKeyType as String:kSecAttrKeyTypeRSA,kSecAttrKeyClass as String:kSecAttrKeyClassPublic]
        guard let publicKey=SecKeyCreateWithData(rsa as CFData,attrs as CFDictionary,nil),
              SecKeyVerifySignature(publicKey,.rsaSignatureMessagePKCS1v15SHA256,Data((p[0]+"."+p[1]).utf8) as CFData,signature as CFData,nil) else {throw PlanAuthError.invalid("Identity signature verification failed.")}
        let audience=(claims["aud"] as? [String]) ?? [(claims["aud"] as? String) ?? ""]
        guard claims["iss"] as? String==issuer,audience.contains(clientID),
              audience.count==1 || claims["azp"] as? String==clientID,
              let exp=claims["exp"] as? Double,exp>Date().timeIntervalSince1970,
              claims["nonce"] as? String==nonce,
              let subject=claims["sub"] as? String,!subject.isEmpty else {throw PlanAuthError.invalid("Identity claims did not match this sign-in.")}
        return (subject,claims["email"] as? String ?? "ChatGPT account")
    }
}
final class PlanNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void) { completionHandler(nil) }
}

// Only listens on the loopback interface, accepts one validated OAuth GET.
// Keep the system-provided browser sheet open until the callback arrives.
private final class PlanLoopback {
    private let queue=DispatchQueue(label:"flow.plan.loopback")
    private let listener:NWListener
    private var connections:[NWConnection]=[]
    init() throws {
        let p=NWParameters.tcp
        p.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:.any)
        listener=try NWListener(using:p)
    }
    func start(ready:@escaping (UInt16)->Void,failed:@escaping ()->Void,callback:@escaping (URLComponents)->Bool) {
        listener.stateUpdateHandler={ [weak self] state in
            switch state {
            case .ready: if let port=self?.listener.port?.rawValue {ready(port)} else {failed()}
            case .failed:failed()
            default:break
            }
        }
        listener.newConnectionHandler={ [weak self] c in
            guard let self,self.connections.count<16 else {c.cancel();return}
            self.connections.append(c);c.start(queue:self.queue)
            self.receive(c,data:Data(),callback:callback)
        }
        listener.start(queue:queue)
    }
    private func receive(_ c:NWConnection,data:Data,callback:@escaping (URLComponents)->Bool) {
        c.receive(minimumIncompleteLength:1,maximumLength:4096){ [weak self] chunk,_,complete,error in
            guard let self else {c.cancel();return}
            let d=data+(chunk ?? Data())
            guard d.count<=16384,error==nil else {c.cancel();return}
            if let request=String(data:d,encoding:.utf8),request.contains("\r\n\r\n") {
                let first=request.components(separatedBy:"\r\n").first?.split(separator:" ") ?? []
                var ok=false
                if first.count==3,first[0]=="GET",first[1].hasPrefix("/auth/callback?"),
                   let parts=URLComponents(string:"http://127.0.0.1"+String(first[1])),parts.path=="/auth/callback" {
                    ok=callback(parts)
                }
                let body=ok ? "Authorization received. Return to FlowOS." : "Request not accepted."
                let response="HTTP/1.1 \(ok ? "200 OK":"400 Bad Request")\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n"+body
                c.send(content:Data(response.utf8),completion:.contentProcessed{_ in c.cancel()})
            } else if !complete {self.receive(c,data:d,callback:callback)}
            else {c.cancel()}
        }
    }
    func stop(){queue.async{self.listener.cancel();self.connections.forEach{$0.cancel()};self.connections=[]}}
}
@MainActor final class ChatGPTPlanAuth: ObservableObject {
    @Published private(set) var profiles:[PlanProfile]=PlanVault.read()
    @Published private(set) var activeID:String?=UserDefaults.standard.string(forKey:"flow.plan.active")
    @Published var browserURL:URL?
    @Published private(set) var busy=false
    @Published var message=""
    private let session=URLSession(configuration:.ephemeral,delegate:PlanNoRedirect(),delegateQueue:nil)
    private var listener:PlanLoopback?
    private var timeout:Task<Void,Never>?
    private var operation:UUID?
    private var refreshing=false
    var active:PlanProfile? {profiles.first{$0.id==activeID && $0.enabled}}
    private var hostID:String {
        if let id=UserDefaults.standard.string(forKey:"flow.plan.host") {return id}
        let id="urn:uuid:"+UUID().uuidString.lowercased()
        UserDefaults.standard.set(id,forKey:"flow.plan.host");return id
    }
    private func setActive(_ id:String?) {activeID=id;UserDefaults.standard.set(id,forKey:"flow.plan.active")}
    func select(_ id:String) {
        guard !busy,!refreshing,profiles.contains(where:{$0.id==id && $0.enabled}) else {return}
        setActive(id);message="Account selected. Refresh models before routing requests."
    }
    func cancel() {
        operation=nil;listener?.stop();listener=nil;timeout?.cancel();timeout=nil;browserURL=nil;busy=false
    }
    func start(existing:PlanProfile?=nil) {
        guard !busy,!refreshing else {return}
        do {
            let state=try PlanOAuth.random(),nonce=try PlanOAuth.random(),verifier=try PlanOAuth.random()
            let challenge=PlanOAuth.base64URL(Data(SHA256.hash(data:Data(verifier.utf8))))
            let loop=try PlanLoopback();listener=loop;busy=true;message="Opening official ChatGPT authorization…"
            let attempt=UUID();operation=attempt
            let host=hostID
            loop.start(ready:{ [weak self] port in
                Task { @MainActor in
                    guard let self,self.operation==attempt else {return}
                    let redirect="http://127.0.0.1:\(port)/auth/callback"
                    var url=URLComponents(string:PlanOAuth.issuer+"/api/accounts/authorize")!
                    var q=["client_id":existing?.clientID ?? "dynamic_agent_client","ext_agent_host_id":host,"response_type":"code","redirect_uri":redirect,"scope":"openid profile email offline_access resource.invoke chatgpt.tokens.use.direct","resource":PlanOAuth.resource,"state":state,"nonce":nonce,"code_challenge_method":"S256","code_challenge":challenge]
                    if let existing { if !existing.idToken.isEmpty {q["id_token_hint"]=existing.idToken} }
                    else {q["agent_name_hint"]="FlowOS"}
                    url.queryItems=q.keys.sorted().map{URLQueryItem(name:$0,value:q[$0])}
                    self.browserURL=url.url
                }
            },failed:{ [weak self] in Task { @MainActor in
                guard let self,self.operation==attempt else {return};self.cancel();self.message="Local OAuth callback could not start."
            }},callback:{ [weak self] parts in
                let items=parts.queryItems ?? []
                guard items.filter({$0.name=="state"}).count==1,items.first(where:{$0.name=="state"})?.value==state else {return false}
                // Capture exact listener port from the browser authorization URL on the main actor.
                Task { @MainActor in
                    guard let self,self.operation==attempt,
                          let url=self.browserURL,let redirect=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name=="redirect_uri"})?.value else {return}
                    self.browserURL=nil;self.listener?.stop();self.listener=nil;self.timeout?.cancel()
                    do {
                        guard !items.contains(where:{$0.name=="error"}),items.filter({$0.name=="code"}).count==1,items.filter({$0.name=="client_id"}).count<=1,let code=items.first(where:{$0.name=="code"})?.value,!code.isEmpty else {throw PlanAuthError.invalid("Authorization declined or incomplete.")}
                        let issued=items.first(where:{$0.name=="client_id"})?.value
                        guard let client=existing?.clientID ?? issued,client.hasPrefix("oaiapp_"),issued==nil || issued==client else {throw PlanAuthError.invalid("Client registration did not match.")}
                        let tokens=try await self.token(["grant_type":"authorization_code","client_id":client,"code":code,"code_verifier":verifier,"redirect_uri":redirect,"resource":PlanOAuth.resource])
                        guard let idToken=tokens["id_token"] as? String,let access=tokens["access_token"] as? String,let refresh=tokens["refresh_token"] as? String,let expires=tokens["expires_in"] as? Double,expires>0 else {throw PlanAuthError.invalid("Incomplete token response.")}
                        let (subject,email)=try await PlanOAuth.identity(idToken,clientID:client,nonce:nonce,session:self.session)
                        guard self.operation==attempt,existing==nil || existing?.subject==subject else {throw PlanAuthError.invalid("Account identity did not match.")}
                        let scopes=Set((tokens["scope"] as? String ?? "").split(separator:" ").map(String.init))
                        guard scopes.contains("chatgpt.tokens.use.direct") else {throw PlanAuthError.invalid("ChatGPT plan permission was not granted.")}
                        let profile=PlanProfile(clientID:client,subject:subject,email:email,accessToken:access,refreshToken:refresh,idToken:idToken,scopes:scopes,expires:Date().addingTimeInterval(expires))
                        var list=self.profiles
                        if let i=list.firstIndex(where:{$0.id==client}) {guard list[i].subject==subject else {throw PlanAuthError.invalid("Registration identity mismatch.")};list[i]=profile}
                        else {list.append(profile)}
                        try PlanVault.write(list);self.profiles=list;self.setActive(client)
                        self.cancel();self.message="ChatGPT plan connected."
                    } catch {if self.operation==attempt {self.cancel();self.message=error.localizedDescription}}
                }
                return true
            })
            timeout=Task { [weak self] in
                try? await Task.sleep(for:.seconds(180))
                guard !Task.isCancelled,let self,self.operation==attempt else {return}
                self.cancel();self.message="Sign-in timed out. Try again."
            }
        } catch {cancel();message=error.localizedDescription}
    }
    private func token(_ fields:[String:String]) async throws -> [String:Any] {
        var req=URLRequest(url:PlanOAuth.tokenURL);req.httpMethod="POST";req.timeoutInterval=30
        req.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type");req.httpBody=PlanOAuth.form(fields)
        let (data,response)=try await session.data(for:req)
        guard (response as? HTTPURLResponse)?.statusCode==200,let object=try JSONSerialization.jsonObject(with:data) as? [String:Any] else {throw PlanAuthError.invalid("Authorization expired or unavailable. Reconnect your account.")}
        return object
    }
    func accessToken(for id:String) async throws -> String {
        guard let p=active,p.id==id,!busy else {throw PlanAuthError.invalid("Select and authorize this ChatGPT account first.")}
        if p.expires.timeIntervalSinceNow>90 {return p.accessToken}
        guard !refreshing else {throw PlanAuthError.invalid("Account renewal already running.")}
        refreshing=true;defer{refreshing=false}
        let response=try await token(["grant_type":"refresh_token","client_id":p.clientID,"refresh_token":p.refreshToken,"resource":PlanOAuth.resource])
        guard let access=response["access_token"] as? String,let expires=response["expires_in"] as? Double,expires>0,activeID==id else {throw PlanAuthError.invalid("Renewal did not complete. Reconnect.")}
        var updated=p;updated.accessToken=access;updated.expires=Date().addingTimeInterval(expires)
        updated.refreshToken=response["refresh_token"] as? String ?? p.refreshToken
        if let raw=response["scope"] as? String {updated.scopes=Set(raw.split(separator:" ").map(String.init))}
        guard updated.enabled else {throw PlanAuthError.invalid("ChatGPT plan permission was removed.")}
        var list=profiles;guard let i=list.firstIndex(where:{$0.id==id}) else {throw PlanAuthError.invalid("Account no longer selected.")}
        list[i]=updated;try PlanVault.write(list);profiles=list;return access
    }
    func signOut(_ id:String) async {
        guard !busy,!refreshing,let p=profiles.first(where:{$0.id==id}) else {return}
        busy=true;defer{busy=false}
        var req=URLRequest(url:PlanOAuth.revokeURL);req.httpMethod="POST";req.timeoutInterval=15
        req.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type")
        req.httpBody=PlanOAuth.form(["token":p.refreshToken,"token_type_hint":"refresh_token","client_id":p.clientID])
        let revoked:Bool
        if let (_,r)=try? await session.data(for:req) {revoked=(r as? HTTPURLResponse)?.statusCode==200} else {revoked=false}
        var list=profiles
        if let i=list.firstIndex(where:{$0.id==id}) {
            list[i].accessToken="";list[i].refreshToken="";list[i].idToken="";list[i].scopes=[];list[i].expires = .distantPast
        }
        do {try PlanVault.write(list);profiles=list;if activeID==id {setActive(nil)};message=revoked ? "Signed out.":"Signed out locally; revoke the connection in ChatGPT Settings to confirm remote removal."}
        catch {setActive(nil);message="Could not erase Keychain credentials. Revoke in ChatGPT Settings."}
    }
}
struct PlanBrowser: UIViewControllerRepresentable {
    let url:URL
    func makeUIViewController(context:Context)->SFSafariViewController {SFSafariViewController(url:url)}
    func updateUIViewController(_ uiViewController:SFSafariViewController,context:Context){}
}
