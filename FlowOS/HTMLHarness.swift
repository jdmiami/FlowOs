import Foundation

struct HTMLReport: Codable, Equatable {
    var passed: Bool
    var checks: [String]
    var errors: [String]
}
struct HTMLDocument {
    var source: String
    var title: String
}
enum HTMLHarness {
    static let maximumBytes = 180_000
    static let skill = """
    You are the FlowOS visual application engineer. Build a genuinely usable mobile-first application, not a description, screenshot, wireframe, or JSON field schema. Output ONLY one complete HTML document starting <!DOCTYPE html> and ending </html>. Include a meaningful <title>, a <head>, inline <style>, <body>, and inline JavaScript for every requested interaction. No markdown. Make every control work; implement create/edit/delete/search/calculations as requested, sensible defaults, empty states, validation, and responsive layout. Prefer a focused working MVP to unfinished ambitious features.
    DESIGN: Premium modern Liquid Glass-inspired visual design: editorial hierarchy, soft depth, intentional negative space, fluid transitions, tactile buttons, accessible contrast, touch targets >=44px, readable labels >=12px. Use semantic CSS tokens --background, --content, --card, --sidebar, --card-border, --border, --foreground, --muted-foreground, --placeholder, --code-foreground, --primary, --primary-foreground, --secondary, --secondary-foreground, --accent, --link, --success, --warning, --error, --chart-1 through --chart-6. FlowOS supplies these, including light/dark mode. Do not overwrite them. Use CSS Grid/Flexbox, SVG or Canvas for charts and visuals; redraw canvas on themechange. Use CSS spring-like cubic-bezier motion, and honor prefers-reduced-motion. Standalone pages use a page background and grouped panels; compact widgets stay flush and transparent, no outer card, no viewport-height top-level containers. Target <=450px for compact widgets; larger apps scroll normally.
    RUNTIME: Offline only. Use vanilla JS and inline CSS, NOT Tailwind CDN or external assets. No fetch, iframe, links to other pages, imports, external scripts, fonts, eval, device APIs, or network. No native permissions. For persistent data use const state=window.FlowOS.load() || initialState; window.FlowOS.save(state) after edits. Exported documents also provide this API. Do not use localStorage directly. Use textContent for user input. Register window.flowSelfTest=function(){return true or false;} with meaningful synchronous assertions of core logic; do not mutate saved data or fake tests. No modal JavaScript alert/prompt/confirm; use inline controls. No infinite loops. Finish all code and closing tags. A partial or invalid page is not an app.
    """
    static let localSkill = """
    Return ONLY complete <!DOCTYPE html><html><head><title>...</title><style>...</style></head><body>...</body></html>. Create a tiny working mobile app with inline CSS+JS. Use var(--foreground), var(--card), var(--primary), var(--background), touch-friendly controls and meaningful visuals. No external URLs, imports, fetch, iframe, links, or eval. All controls work. Save data with FlowOS.save(state), load with FlowOS.load(). Keep under 550 tokens; finish closing tags.
    """
    static func parse(_ output: String) -> (HTMLDocument?, HTMLReport) {
        var errors: [String] = []
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= maximumBytes else { return (nil,.init(passed:false,checks:[],errors:["Output exceeds 180 KB."])) }
        guard let start=trimmed.range(of:"<!doctype html",options:.caseInsensitive),
              let end=trimmed.range(of:"</html>",options:[.caseInsensitive,.backwards]), start.lowerBound<end.lowerBound else {
            return (nil,.init(passed:false,checks:[],errors:["Missing complete HTML document."]))
        }
        let source=String(trimmed[start.lowerBound..<end.upperBound])
        let lower=source.lowercased()
        if source.range(of:"<head(?:\\s[^>]*)?>",options:[.regularExpression,.caseInsensitive]) == nil { errors.append("A valid head element is required for the sandbox.") }
        if lower.components(separatedBy:"<!doctype html").count != 2 || lower.components(separatedBy:"</html>").count != 2 { errors.append("Expected exactly one document.") }
        for pattern in ["<html(?:\\s|>)","<head(?:\\s|>)","</head\\s*>","<body(?:\\s|>)","</body\\s*>"] {
            if source.range(of:pattern,options:[.regularExpression,.caseInsensitive]) == nil { errors.append("Missing required HTML structure: "+pattern) }
        }
        let blocked=["<\\s*(iframe|frame|object|embed|portal|base|link)\\b","<\\s*script\\b[^>]*\\bsrc\\s*=","<\\s*meta\\b[^>]*http-equiv","<\\s*form\\b[^>]*\\baction\\s*=","<\\s*html\\b[^>]*\\bmanifest\\s*="]
        for pattern in blocked where source.range(of:pattern,options:[.regularExpression,.caseInsensitive]) != nil {
            errors.append("External resources or navigation are not supported.")
        }
        let title: String
        if let range=source.range(of:"<title\\s*>[^<]{1,160}</title\\s*>",options:[.regularExpression,.caseInsensitive]) {
            title=String(source[range]).replacingOccurrences(of:"<[^>]+>",with:"",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines)
        } else { title="Generated application";errors.append("Include a meaningful title.") }
        guard errors.isEmpty else {return (nil,.init(passed:false,checks:[],errors:Array(Set(errors)).sorted()))}
        return (.init(source:source,title:String(title.prefix(80))),.init(passed:false,checks:["Complete document","Offline structure check","Size within limit"],errors:[]))
    }
    static func escapeAttribute(_ s:String)->String {
        s.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"\"",with:"&quot;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;")
    }
    // CSS is injected by the host, not generated. The exported HTML receives the same tokens.
    static let themeCSS = """
    :root{color-scheme:light dark;--background:#f8f6fc;--content:#f8f6fc;--card:#fff;--sidebar:#f1edf8;--card-border:#ded9ea;--border:#d9d4e4;--foreground:#272638;--muted-foreground:#666178;--placeholder:#777186;--code-foreground:#323047;--primary:#6650a4;--primary-foreground:#fff;--secondary:#e8e1f7;--secondary-foreground:#30274e;--accent:#c0e6df;--link:#514094;--success:#16704f;--warning:#8b5200;--error:#ad304b;--chart-1:#785db7;--chart-2:#218d82;--chart-3:#c96b79;--chart-4:#457bce;--chart-5:#b07a24;--chart-6:#8b5a9c}
    @media(prefers-color-scheme:dark){:root{--background:#191823;--content:#191823;--card:#252433;--sidebar:#211f2d;--card-border:#413e50;--border:#49465a;--foreground:#f2effa;--muted-foreground:#c3bdd4;--placeholder:#a9a2bc;--code-foreground:#eee8fa;--primary:#c9b6ff;--primary-foreground:#241841;--secondary:#3d335b;--secondary-foreground:#f0e9ff;--accent:#305a57;--link:#d5c5ff;--success:#7de0b0;--warning:#ffd085;--error:#ff9ba9;--chart-1:#c3a8ff;--chart-2:#75d8ca;--chart-3:#f49ba7;--chart-4:#91bdff;--chart-5:#f0c575;--chart-6:#e5a6eb}}
    *{box-sizing:border-box}html{margin:0;padding:0;overflow-x:hidden}body{margin:0;padding:16px;color:var(--foreground);background:var(--background);font:16px -apple-system,BlinkMacSystemFont,system-ui,sans-serif;line-height:1.5;overflow-wrap:anywhere}button,input,select,textarea{font:inherit;min-height:44px;color:inherit}button{cursor:pointer;touch-action:manipulation}button:focus-visible,input:focus-visible,select:focus-visible,textarea:focus-visible{outline:3px solid var(--primary);outline-offset:2px}img,svg,canvas{max-width:100%}a{color:var(--link)}@media(prefers-reduced-motion:reduce){*,*::before,*::after{animation-duration:.01ms!important;transition-duration:.01ms!important;scroll-behavior:auto!important}}
    """
    static let csp = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; media-src data: blob:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'; worker-src 'none'; manifest-src 'none'"
    static func inject(_ source:String, fragment:String)->String {
        guard let head=source.range(of:"<head(?:\\s[^>]*)?>",options:[.regularExpression,.caseInsensitive]) else {return source}
        var result=source;result.insert(contentsOf:fragment,at:head.upperBound);return result
    }
    static func prepared(_ document:HTMLDocument, state:String="null", embedded:Bool)->String {
        // Encode state to keep it from ever becoming executable script.
        let encoded=Data(state.utf8).base64EncodedString()
        let storageKey="flowos-artifact-"+Data(document.title.utf8).base64EncodedString()
        let runtime = """
        <meta http-equiv="Content-Security-Policy" content="\(csp)"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"><style>\(themeCSS)</style>
        <script>
        (()=>{let state=null;const embedded=\(embedded ? "true":"false"),key="\(storageKey)";
        try{state=JSON.parse(new TextDecoder().decode(Uint8Array.from(atob("\(encoded)"),c=>c.charCodeAt(0))));if(!embedded){const old=localStorage.getItem(key);if(old!==null)state=JSON.parse(old)}}catch(e){}
        const send=(kind,value)=>{if(embedded)parent.postMessage({flow:1,kind,value},"*")};
        Object.defineProperty(window,"FlowOS",{value:Object.freeze({load:()=>JSON.parse(JSON.stringify(state)),save:(v)=>{try{const s=JSON.stringify(v);if(typeof s!=="string"||new TextEncoder().encode(s).length>65536)return false;state=JSON.parse(s);if(embedded)send("save",s);else localStorage.setItem(key,s);return true}catch(e){return false}}}),writable:false,configurable:false});
        window.addEventListener("error",e=>send("error",String(e.message||"Resource or script error").slice(0,400)),true);
        window.addEventListener("unhandledrejection",e=>send("error",String(e.reason||"Unhandled promise rejection").slice(0,400)));
        document.addEventListener("securitypolicyviolation",e=>send("error","Blocked resource: "+e.violatedDirective));
        const media=matchMedia("(prefers-color-scheme: dark)");media.addEventListener("change",()=>window.dispatchEvent(new Event("themechange")));
        window.addEventListener("load",()=>setTimeout(()=>{let test="not supplied";try{if(typeof window.flowSelfTest==="function")test=window.flowSelfTest()===true?"passed":"failed"}catch(e){test="failed";send("error",String(e).slice(0,400))}const body=document.body;const visible=!!body&&(body.innerText.trim().length>0||!!body.querySelector("canvas,svg,img,input,button"))&&body.getBoundingClientRect().height>0;send("ready",{visible,test})},180),{once:true});
        })();
        </script>
        """
        return inject(document.source,fragment:runtime)
    }
    static func wrapper(_ document:HTMLDocument,state:String="null")->String {
        let child=escapeAttribute(prepared(document,state:state,embedded:true))
        // The only privileged bridge lives in the trusted top-level document.
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; media-src data: blob:; frame-src about:; connect-src 'none'; base-uri 'none'; form-action 'none'; object-src 'none'"><style>html,body,iframe{margin:0;padding:0;width:100%;height:100%;border:0;display:block;background:transparent}</style></head><body>
        <script>window.addEventListener("message",e=>{const frame=document.getElementById("flow-frame"),m=e.data;if(!frame||e.source!==frame.contentWindow||!m||m.flow!==1)return;let v=m.value;if(m.kind==="save"&&(typeof v!=="string"||v.length>65536))return;if(m.kind==="error")v=String(v).slice(0,400);if(m.kind==="ready")v={visible:v?.visible===true,test:["passed","failed"].includes(v?.test)?v.test:"not supplied"};if(["ready","error","save"].includes(m.kind))try{window.webkit.messageHandlers.flowRuntime.postMessage({kind:m.kind,value:v})}catch(_){} });</script>
        <iframe id="flow-frame" title="Generated application" sandbox="allow-scripts" referrerpolicy="no-referrer" srcdoc="\(child)"></iframe></body></html>
        """
    }
}
