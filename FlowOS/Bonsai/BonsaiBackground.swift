import Foundation
import UIKit

// The system owns transfers. Staging is synchronous in the delegate; hashing
// is deferred until the next foreground visit, so suspension cannot lose data.
final class BonsaiBackground: NSObject, URLSessionDownloadDelegate {
    static let shared = BonsaiBackground()
    static let identifier = "com.flowos.personal.bonsai.download.v1"
    static let changed = Notification.Name("BonsaiBackgroundChanged")
    let folder = URL.applicationSupportDirectory.appendingPathComponent("FlowOS/BonsaiModels",isDirectory:true)
    private var completion: (() -> Void)?
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        c.sessionSendsLaunchEvents = true
        c.isDiscretionary = false
        c.allowsCellularAccess = false
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration:c,delegate:self,delegateQueue:queue)
    }()
    func reconnect(){ _ = session }
    func events(_ handler:@escaping ()->Void){completion=handler;reconnect()}
    func staged(_ name:String)->URL{folder.appendingPathComponent(name+".downloaded")}
    private func resumePath(_ name:String)->URL{folder.appendingPathComponent(name+".resume")}
    func snapshot(_ callback:@escaping ([URLSessionTask])->Void){
        session.getAllTasks{tasks in DispatchQueue.main.async{callback(tasks)}}
    }
    func start(_ assets:[BonsaiAsset]){
        for asset in assets {
            let url=URL(string:"https://huggingface.co/"+BonsaiManifest.repository+"/resolve/"+BonsaiManifest.pinned+"/"+asset.name)!
            let task:URLSessionDownloadTask
            if let data=try? Data(contentsOf:resumePath(asset.name)), !data.isEmpty {
                task=session.downloadTask(withResumeData:data)
                try? FileManager.default.removeItem(at:resumePath(asset.name))
            } else { task=session.downloadTask(with:url) }
            task.taskDescription=asset.name
            task.resume()
        }
    }
    func pause(){
        session.getAllTasks{tasks in
            for case let task as URLSessionDownloadTask in tasks{
                let name=task.taskDescription ?? ""
                task.cancel(byProducingResumeData:{data in
                    if let data, self.allowed(name){try? data.write(to:self.resumePath(name),options:.atomic)}
                    self.notify()
                })
            }
        }
    }
    private func allowed(_ name:String)->Bool{
        Set(BonsaiManifest.names(size:256)+BonsaiManifest.names(size:512)).contains(name)
    }
    private func notify(_ error:String?=nil){
        DispatchQueue.main.async{NotificationCenter.default.post(name:Self.changed,object:nil,userInfo:error.map{["error":$0]})}
    }
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL){
        let name=downloadTask.taskDescription ?? ""
        guard allowed(name),let http=downloadTask.response as? HTTPURLResponse,(200...299).contains(http.statusCode) else{notify("Download failed: "+name);return}
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let dest=staged(name)
            if FileManager.default.fileExists(atPath:dest.path){try FileManager.default.removeItem(at:dest)}
            try FileManager.default.moveItem(at:location,to:dest)
            try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:dest.path)
            try? FileManager.default.removeItem(at:resumePath(name))
            notify()
        }catch{notify(error.localizedDescription)}
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?){
        if let error{
            let e=error as NSError
            if let name=task.taskDescription,allowed(name),let data=e.userInfo[NSURLSessionDownloadTaskResumeData] as? Data{try? data.write(to:resumePath(name),options:.atomic)}
            notify(e.code == NSURLErrorCancelled ? nil : error.localizedDescription)
        }else{notify()}
    }
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64){notify()}
    func urlSessionDidFinishEvents(forBackgroundURLSession session:URLSession){
        DispatchQueue.main.async{let handler=self.completion;self.completion=nil;handler?();self.notify()}
    }
}
final class FlowDownloadDelegate:NSObject,UIApplicationDelegate {
    func application(_ application:UIApplication,didFinishLaunchingWithOptions launchOptions:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool{
        BonsaiBackground.shared.reconnect();return true
    }
    func application(_ application:UIApplication,handleEventsForBackgroundURLSession identifier:String,completionHandler:@escaping ()->Void){
        if identifier==BonsaiBackground.identifier{BonsaiBackground.shared.events(completionHandler)}else{completionHandler()}
    }
}
