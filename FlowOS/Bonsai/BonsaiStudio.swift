import Foundation
import CryptoKit
import SwiftUI
import os
import UIKit

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
    private var verification=false
    private var observer:NSObjectProtocol?
    private var timer:Timer?
    private var starting=false
    private var polling=false
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
        observer=NotificationCenter.default.addObserver(forName:BonsaiBackground.changed,object:nil,queue:.main){[weak self] note in
            let error=note.userInfo?["error"] as? String
            Task{@MainActor in if let error,self?.generating == false{ self?.status=error }; self?.syncDownloads()}
        }
        timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true){[weak self] _ in Task{@MainActor in self?.syncDownloads()}}
        syncDownloads()
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
        stopFlag?.cancel();if downloading{BonsaiBackground.shared.pause()}
        status="Stopping after current operation…"
    }
    func removeModels(){
        guard !downloading,!generating else{return}
        for asset in manifest?.files ?? [] {try? FileManager.default.removeItem(at:path(asset));try? FileManager.default.removeItem(at:BonsaiBackground.shared.staged(asset.name));try? FileManager.default.removeItem(at:folder.appendingPathComponent(asset.name+".resume"))}
        refresh();status="Model files removed. Your images were kept."
    }
    func download(){
        guard !downloading,!generating,!starting,!ready else{return}
        let assets=required.filter{!readyFiles.contains($0.name) && !FileManager.default.fileExists(atPath:BonsaiBackground.shared.staged($0.name).path)}
        let bytes=assets.reduce(Int64(0)){$0+$1.bytes}
        let capacity=(try? folder.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
        guard assets.isEmpty || capacity>bytes+700_000_000 else{status="Free more storage before downloading.";return}
        starting=true;downloading=true;status="Downloading in background · Wi-Fi";progress=0
        BonsaiBackground.shared.start(assets)
        starting=false;syncDownloads()
    }
    func syncDownloads(){
        guard !generating,!polling,!starting,!verification,manifest != nil else{return}
        polling=true
        BonsaiBackground.shared.snapshot{[weak self] tasks in
            guard let self else{return}
            self.polling=false
            guard !self.generating,!self.starting,!self.verification else{return}
            self.refresh()
            let active=tasks.filter{$0.state == .running || $0.state == .suspended}
            let staged=self.required.filter{FileManager.default.fileExists(atPath:BonsaiBackground.shared.staged($0.name).path)}
            let total=self.required.reduce(Int64(0)){$0+$1.bytes}
            let completed=self.required.filter{self.readyFiles.contains($0.name)}.reduce(Int64(0)){$0+$1.bytes}
            let pending=staged.reduce(Int64(0)){$0+$1.bytes}
            let received=active.reduce(Int64(0)){sum,task in
                guard let asset=self.required.first(where:{$0.name==task.taskDescription}),!self.readyFiles.contains(asset.name),!staged.contains(where:{$0.name==asset.name}) else{return sum}
                return sum+min(asset.bytes,max(0,task.countOfBytesReceived))
            }
            self.progress=total>0 ? min(1,Double(completed+pending+received)/Double(total)):0
            self.detail=ByteCountFormatter.string(fromByteCount:completed+pending+received,countStyle:.file)+" / "+ByteCountFormatter.string(fromByteCount:total,countStyle:.file)
            self.downloading = !active.isEmpty || !staged.isEmpty
            if !active.isEmpty{self.status="Downloading in background · Wi-Fi"}
            if !staged.isEmpty,UIApplication.shared.applicationState == .active{
                self.verifyStaged(staged)
            }else if self.ready{self.status="Model ready for offline generation."}
            else if !staged.isEmpty{self.status="Downloaded. Verification will finish when you reopen ImageMaker."}
        }
    }
    private func verifyStaged(_ assets:[BonsaiAsset]){
        verification=true;downloading=true
        let flag=BonsaiStop();stopFlag=flag
        Task{
            defer{verification=false;stopFlag=nil;refresh();syncDownloads()}
            for asset in assets{
                let temp=BonsaiBackground.shared.staged(asset.name)
                status="Verifying SHA-256 · "+asset.name
                do{
                    try await Task.detached(priority:.utility){try Self.verifyFile(temp,asset:asset,flag:flag)}.value
                    if flag.isStopped{break}
                    let dest=path(asset)
                    if FileManager.default.fileExists(atPath:dest.path){try FileManager.default.removeItem(at:dest)}
                    try FileManager.default.moveItem(at:temp,to:dest)
                    refresh()
                }catch{
                    if flag.isStopped{break}
                    try? FileManager.default.removeItem(at:temp)
                    status=error.localizedDescription
                }
            }
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
