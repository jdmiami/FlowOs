import Foundation
import CryptoKit
import SwiftUI
import os

struct BonsaiAsset: Codable, Identifiable {
    let name:String
    let bytes:Int64
    let sha256:String
    var id:String{name}
}
struct BonsaiManifest:Codable {
    let revision:String
    let files:[BonsaiAsset]
    static let repository="litert-community/Bonsai-Image-ternary-4B"
    static let pinned="317d577f5f962eb2d5a3980bca2ce047a8338212"
    static func names(size:Int)->[String] {
        ["textenc_int4.tflite",size==256 ? "dit_256_int4b32.tflite":"dit_int4b32.tflite",size==256 ? "vae_dec_256_fp32.tflite":"vae_dec_fp32.tflite"]
    }
    static func read()throws->Self{
        guard let url=Bundle.main.url(forResource:"bonsai_manifest",withExtension:"json") else{throw Failure("Model manifest missing from build.")}
        let m=try JSONDecoder().decode(Self.self,from:Data(contentsOf:url))
        guard m.revision==pinned,m.files.count==5,Set(m.files.map(\.name))==Set(names(size:256)+names(size:512)),m.files.allSatisfy({$0.bytes>0 && $0.sha256.count==64 && $0.sha256.allSatisfy{"0123456789abcdef".contains($0)}}) else{throw Failure("Model manifest invalid.")}
        return m
    }
    struct Failure:LocalizedError {
        let message:String
        init(_ message:String){self.message=message}
        var errorDescription:String?{message}
    }
}
final class BonsaiStop: @unchecked Sendable {
    private let lock=NSLock()
    private var stopped=false
    func cancel(){lock.lock();stopped=true;lock.unlock()}
    var isStopped:Bool{lock.lock();defer{lock.unlock()};return stopped}
}
@MainActor final class BonsaiStudio:ObservableObject {
    @Published var size=256
    @Published var prompt=""
    @Published var steps=4
    @Published var seed="42"
    @Published private(set) var downloading=false
    @Published private(set) var generating=false
    @Published private(set) var progress=0.0
    @Published private(set) var status="Download the model to begin."
    @Published private(set) var detail=""
    @Published private(set) var gallery:[URL]=[]
    @Published private(set) var readyFiles:Set<String>=[]
    @Published private(set) var manifest:BonsaiManifest?
    @Published private(set) var output:URL?
    @Published private(set) var lastSeconds:Double?
    private let folder=URL.applicationSupportDirectory.appendingPathComponent("FlowOS/BonsaiModels",isDirectory:true)
    private var transfer:URLSessionDownloadTask?
    private var stopFlag:BonsaiStop?
    private var job:Task<Void,Never>?
    init(){
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            var directory=folder;var v=URLResourceValues();v.isExcludedFromBackup=true;try directory.setResourceValues(v)
            manifest=try BonsaiManifest.read()
            refresh()
        }catch{status=error.localizedDescription}
        scanGallery()
    }
    var required:[BonsaiAsset]{
        let names=BonsaiManifest.names(size:size)
        return names.compactMap{n in manifest?.files.first{$0.name==n}}
    }
    var ready:Bool{required.count==3 && required.allSatisfy{readyFiles.contains($0.name)}}
    var needed:Int64{required.filter{!readyFiles.contains($0.name)}.reduce(0){$0+$1.bytes}}
    var stored:Int64{(manifest?.files ?? []).filter{readyFiles.contains($0.name)}.reduce(0){$0+$1.bytes}}
    private func path(_ asset:BonsaiAsset)->URL{folder.appendingPathComponent(asset.name)}
    func refresh(){
        readyFiles=Set((manifest?.files ?? []).filter{asset in
            let size=(try? path(asset).resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? -1
            return Int64(size)==asset.bytes
        }.map(\.name))
    }
    func scanGallery(){
        let dir=URL.documentsDirectory.appendingPathComponent("Bonsai",isDirectory:true)
        gallery=((try? FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil)) ?? []).filter{$0.pathExtension=="png"}.sorted{$0.lastPathComponent>$1.lastPathComponent}
    }
    func cancel(){
        stopFlag?.cancel();transfer?.cancel()
        status="Stopping after current operation…"
    }
    func removeModels(){
        guard !downloading,!generating else{return}
        for asset in manifest?.files ?? [] {try? FileManager.default.removeItem(at:path(asset))}
        refresh();status="Model files removed. Your images were kept."
    }
    func download(){
        guard !downloading,!generating,manifest != nil,!ready else{return}
        let assets=required.filter{!readyFiles.contains($0.name)}
        guard assets.count>0 else{return}
        let bytes=assets.reduce(Int64(0)){$0+$1.bytes}
        let capacity=(try? folder.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
        guard capacity>bytes+700_000_000 else{status="Free more storage before downloading.";return}
        let flag=BonsaiStop();stopFlag=flag;downloading=true;progress=0;detail=""
        job=Task{
            var completed:Int64=0
            defer{downloading=false;transfer=nil;stopFlag=nil;job=nil;refresh()}
            do{
                for asset in assets{
                    if flag.isStopped{throw CancellationError()}
                    status="Downloading "+asset.name
                    let temp=folder.appendingPathComponent(UUID().uuidString+".partial")
                    defer{try? FileManager.default.removeItem(at:temp)}
                    let url=URL(string:"https://huggingface.co/"+BonsaiManifest.repository+"/resolve/"+BonsaiManifest.pinned+"/"+asset.name)!
                    let baseline=completed
                    try await fetch(url,to:temp,asset:asset,completed:baseline,total:bytes)
                    status="Verifying SHA-256 · "+asset.name
                    try await Task.detached(priority:.utility){try Self.verifyFile(temp,asset:asset,flag:flag)}.value
                    if flag.isStopped{throw CancellationError()}
                    let dest=path(asset)
                    if FileManager.default.fileExists(atPath:dest.path){try FileManager.default.removeItem(at:dest)}
                    try FileManager.default.moveItem(at:temp,to:dest)
                    completed+=asset.bytes;progress=Double(completed)/Double(bytes);refresh()
                }
                status="Downloaded and verified. Ready for offline generation."
            }catch{status=flag.isStopped ? "Stopped. Completed files are kept." : error.localizedDescription}
        }
    }
    nonisolated private static func verifyFile(_ url:URL,asset:BonsaiAsset,flag:BonsaiStop)throws{
        // All file reads are bounded, on a worker rather than the UI actor.
        let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? -1
        guard Int64(size)==asset.bytes else{throw BonsaiManifest.Failure("Incorrect file size: "+asset.name)}
        let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
        let header=try handle.read(upToCount:8) ?? Data()
        guard header.count==8,String(data:header.suffix(4),encoding:.ascii)=="TFL3" else{throw BonsaiManifest.Failure("Not a TFLite graph: "+asset.name)}
        try handle.seek(toOffset:0)
        var sha=SHA256()
        while let block=try handle.read(upToCount:4*1024*1024),!block.isEmpty{
            if flag.isStopped{throw CancellationError()}
            sha.update(data:block)
        }
        guard sha.finalize().map({String(format:"%02x",$0)}).joined()==asset.sha256 else{throw BonsaiManifest.Failure("Checksum mismatch: "+asset.name)}
    }
    private func fetch(_ url:URL,to temp:URL,asset:BonsaiAsset,completed:Int64,total:Int64)async throws{
        var observer:Task<Void,Never>?
        defer{observer?.cancel();transfer=nil}
        try await withCheckedThrowingContinuation{(c:CheckedContinuation<Void,Error>) in
            let task=URLSession.shared.downloadTask(with:url){location,response,error in
                do{
                    if let error{throw error}
                    guard let location,let http=response as? HTTPURLResponse,http.statusCode==200 else{throw BonsaiManifest.Failure("Model download failed. Check your connection.")}
                    try FileManager.default.moveItem(at:location,to:temp)
                    c.resume()
                }catch{c.resume(throwing:error)}
            }
            transfer=task;task.resume()
            observer=Task{[weak self] in
                while !Task.isCancelled{
                    try? await Task.sleep(for:.milliseconds(250))
                    guard !Task.isCancelled,let self,self.transfer===task else{return}
                    let count=max(0,task.countOfBytesReceived)
                    self.progress=min(1,Double(completed+min(count,asset.bytes))/Double(total))
                    self.detail=ByteCountFormatter.string(fromByteCount:count,countStyle:.file)+" / "+ByteCountFormatter.string(fromByteCount:asset.bytes,countStyle:.file)
                }
            }
        }
    }
    func generate(store:Store){
        guard ready,!downloading,!generating,!prompt.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,let value=UInt64(seed),store.beginImageGeneration() else{return}
        let thermal=ProcessInfo.processInfo.thermalState
        if thermal == .serious || thermal == .critical {store.finishImageGeneration("Phone too warm");status="Allow the device to cool first.";return}
        let free=os_proc_available_memory()
        if free>0 && free<3_200_000_000 {store.finishImageGeneration("Insufficient memory");status="Available process memory is below 3.2 GB. Close other apps or restart FlowOS.";return}
        let flag=BonsaiStop();stopFlag=flag;generating=true;progress=0;lastSeconds=nil;detail="";status="Loading offline image pipeline"
        let directory=folder, text=String(prompt.prefix(1500)), resolution=size, count=steps
        job=Task{
            defer{generating=false;stopFlag=nil;job=nil;store.finishImageGeneration(status)}
            do{
                let result=try await Task.detached(priority:.userInitiated){
                    let pipe=try BonsaiPipeline(modelsDir:directory,size:resolution,shouldStop:{
                        let state=ProcessInfo.processInfo.thermalState
                        return flag.isStopped || state == .serious || state == .critical
                    })
                    return try pipe.generate(prompt:text,seed:value,steps:count,status:{line in Task{@MainActor in self.detail=line}},progress:{label,fraction in Task{@MainActor in self.status=label;self.progress=fraction}})
                }.value
                output=result.pngURL;lastSeconds=result.seconds;progress=1;status="Image generated locally";scanGallery()
            }catch{status=flag.isStopped ? "Generation stopped." : error is BonsaiPipeline.Cancelled ? "Stopped due to thermal pressure." : error.localizedDescription}
        }
    }
}
