import Flutter
import UIKit
import Foundation

private let kMethod = "quarklite.com/ios_range_download"
private let kEvent = "quarklite.com/ios_range_download_events"
private let kPersist = "quark_range_tasks.json"

enum RStatus: String, Codable { case wait, running, pause, done, error }

struct PTask: Codable {
    var id: String; var url: String; var headers: [String:String]
    var targetPath: String; var fileName: String; var totalSize: Int64
    var chunkCount: Int; var completed: Int; var window: Int
    var status: String; var tempDir: String; var createdAt: Int64; var downloaded: Int64
}

class RContext {
    var p: PTask
    var ranges: [(Int64,Int64)] = []
    var paused=false; var canceled=false; var success=0; var fail=0
    var bytes:Int64=0
    // Speed sampling is confined to the serial q queue.
    var speedSampleBytes:Int64=0
    var speedSampleAt:TimeInterval=Date().timeIntervalSince1970
    var speedBytesPerSecond:Int64=0
    var fallingBack=false
    var activeTasks:[URLSessionTask]=[]
    init(p: PTask){ self.p=p; self.bytes=p.downloaded; self.speedSampleBytes=p.downloaded }
}

class IosRangeDownloadManager: NSObject, FlutterStreamHandler {
    static let shared = IosRangeDownloadManager()
    private var mChannel: FlutterMethodChannel?
    private var sink: FlutterEventSink?
    private var tasks:[String:RContext]=[:]
    private let q=DispatchQueue(label:"quark.range",qos:.utility)
    private var fg: URLSession!
    private var bg: URLSession!
    private var isFg=true
    private let minChunk:Int64=8*1024*1024
    private let maxC=128
    private let steps=[128,64,32,16,8]
    override init(){
        super.init()
        let c=URLSessionConfiguration.default
        c.timeoutIntervalForRequest=30; c.timeoutIntervalForResource=600
        c.httpMaximumConnectionsPerHost=128
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        fg=URLSession(configuration:c)
        let b=URLSessionConfiguration.background(withIdentifier:"com.quarklite.range.bg")
        b.isDiscretionary=false; b.sessionSendsLaunchEvents=true
        bg=URLSession(configuration:b)
    }
    private var didSetup=false
    func setup(with ctrl: FlutterViewController){
        if didSetup { return }
        didSetup=true
        mChannel=FlutterMethodChannel(name:kMethod,binaryMessenger:ctrl.binaryMessenger)
        let e=FlutterEventChannel(name:kEvent,binaryMessenger:ctrl.binaryMessenger)
        e.setStreamHandler(self)
        mChannel?.setMethodCallHandler{[weak self] c,r in self?.handle(c:c,r:r)}
        load()
        NotificationCenter.default.addObserver(self,selector:#selector(bgNot),name:UIApplication.didEnterBackgroundNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(fgNot),name:UIApplication.willEnterForegroundNotification,object:nil)
    }
    @objc func bgNot(){isFg=false; q.async{for(_,x) in self.tasks where x.p.status==RStatus.running.rawValue{x.p.window=min(x.p.window,4); if(x.p.window<4){x.p.window=4}}; self.save()}}
    @objc func fgNot(){isFg=true; q.async{for(_,x) in self.tasks where x.p.status==RStatus.running.rawValue && !x.paused && !x.canceled{self.sched(x)}}}
    func onListen(withArguments a: Any?, eventSink e: @escaping FlutterEventSink)->FlutterError?{sink=e; return nil}
    func onCancel(withArguments a: Any?)->FlutterError?{sink=nil; return nil}
    private func emit(id:String,st:String,pr:Double,sp:Int64,exp:Int64,code:Int?){
        guard let s=sink else{return}
        var m:[String:Any]=["taskId":id,"status":st,"progress":pr,"speed":max(0,sp),"expectedFileSize":exp]
        if let c=code{m["httpCode"]=c}
        DispatchQueue.main.async{s(m)}
    }
    private func handle(c:FlutterMethodCall,r:@escaping FlutterResult){
        switch c.method{
        case "create":
            guard let a=c.arguments as?[String:Any],let u=a["url"] as?String,let p=a["path"] as?String else{r(FlutterError(code:"bad",message:"url/path",details:nil));return}
            let n=a["name"] as?String ?? "download"
            let h=a["headers"] as?[String:String] ?? [:]
            let con=a["connections"] as?Int ?? 32
            let tid=a["taskId"] as?String
            create(u:u,path:p,name:n,headers:h,con:con,tid:tid,r:r)
        case "list": list(r:r)
        case "pause": guard let a=c.arguments as?[String:Any],let id=a["id"] as?String else{r(FlutterError(code:"bad",message:"id",details:nil));return}; pause(id:id,r:r)
        case "resume": guard let a=c.arguments as?[String:Any],let id=a["id"] as?String else{r(FlutterError(code:"bad",message:"id",details:nil));return}; resume(id:id,r:r)
        case "remove": guard let a=c.arguments as?[String:Any],let id=a["id"] as?String else{r(FlutterError(code:"bad",message:"id",details:nil));return}; let f=a["force"] as?Bool ?? true; remove(id:id,force:f,r:r)
        case "removeAll": let a=c.arguments as?[String:Any]; removeAll(ids:a?["ids"] as?[String],r:r)
        case "pauseAll": let a=c.arguments as?[String:Any]; pauseAll(ids:a?["ids"] as?[String],r:r)
        case "updateConfig": r(nil)
        case "getConfig": r(["downloadDir":"","maxRunning":4,"protocolConfig":["http":["connections":maxC]]])
        case "notifyLifecycle": if let a=c.arguments as?[String:Any],let s=a["state"] as?String{isFg=(s=="foreground"); if(isFg){fgNot()}else{bgNot()}}; r(nil)
        case "probe": guard let a=c.arguments as?[String:Any],let u=a["url"] as?String else{r(FlutterError(code:"bad",message:"url",details:nil));return}; let h=a["headers"] as?[String:String] ?? [:]; probe(u:u,h:h,r:r)
        default: r(FlutterMethodNotImplemented)
        }
    }
    private func probe(u:String,h:[String:String],r:@escaping FlutterResult){
        probeReq(u:u,h:h){len,sup,code in r(["contentLength":len ?? -1,"rangeSupported":sup,"httpCode":code])}
    }
    private func probeReq(u:String,h:[String:String],cb:@escaping(Int64?,Bool,Int)->Void){
        guard let url=URL(string:u) else{cb(nil,false,-1);return}
        var req=URLRequest(url:url); req.httpMethod="HEAD"; req.timeoutInterval=15
        for(k,v) in h{req.setValue(v,forHTTPHeaderField:k)}
        URLSession.shared.dataTask(with:req){_,resp,err in
            if let http=resp as?HTTPURLResponse, err==nil, (200...299).contains(http.statusCode){
                if let l=http.value(forHTTPHeaderField:"Content-Length"),let v=Int64(l),v>0{
                    let sup=(http.value(forHTTPHeaderField:"Accept-Ranges")?.lowercased()=="bytes")
                    cb(v,sup,http.statusCode);return
                }
            }
            var g=URLRequest(url:url); g.httpMethod="GET"; g.setValue("bytes=0-0",forHTTPHeaderField:"Range")
            for(k,v) in h{g.setValue(v,forHTTPHeaderField:k)}; g.timeoutInterval=15
            URLSession.shared.dataTask(with:g){_,resp2,_ in
                if let h2=resp2 as?HTTPURLResponse{
                    let is206=h2.statusCode==206
                    var tot:Int64?
                    if(is206),let cr=h2.value(forHTTPHeaderField:"Content-Range"),let s=cr.split(separator:"/").last,let v=Int64(s){tot=v}
                    if(tot==nil && h2.statusCode==200),let cl=h2.value(forHTTPHeaderField:"Content-Length"),let v=Int64(cl){tot=v}
                    cb(tot,is206,h2.statusCode)
                } else{cb(nil,false,-1)}
            }.resume()
        }.resume()
    }
    /// Returns bytes per second from the recent sample; stale samples are zero.
    private func currentSpeed(_ ctx:RContext, now:TimeInterval=Date().timeIntervalSince1970)->Int64{
        guard ctx.p.status == RStatus.running.rawValue else { return 0 }
        // Download-task callbacks only fire on completion, so sample the active
        // single-connection task when Flutter polls the task list.
        if ctx.p.chunkCount == 1, let task=ctx.activeTasks.first {
            let received=max(0, task.countOfBytesReceived)
            if received > ctx.p.downloaded { recordProgress(ctx,downloaded:received) }
        }
        guard ctx.speedBytesPerSecond > 0, now - ctx.speedSampleAt <= 3 else { return 0 }
        return ctx.speedBytesPerSecond
    }

    /// Records aggregate task progress and updates the speed sample.
    private func recordProgress(_ ctx:RContext, downloaded:Int64){
        let now=Date().timeIntervalSince1970
        let delta=downloaded-ctx.speedSampleBytes
        let elapsed=now-ctx.speedSampleAt
        ctx.p.downloaded=max(0,downloaded)
        ctx.bytes=ctx.p.downloaded
        if delta > 0 && elapsed > 0.05 {
            // Smooth samples to avoid spikes when a chunk completes.
            let instant=Int64(Double(delta)/elapsed)
            ctx.speedBytesPerSecond = ctx.speedBytesPerSecond > 0
                ? (ctx.speedBytesPerSecond * 3 + instant) / 4
                : instant
            ctx.speedSampleBytes=downloaded
            ctx.speedSampleAt=now
        } else if delta > 0 {
            ctx.speedSampleBytes=downloaded
            ctx.speedSampleAt=now
        }
    }

    private func resetSpeed(_ ctx:RContext){
        ctx.speedSampleBytes=ctx.p.downloaded
        ctx.speedSampleAt=Date().timeIntervalSince1970
        ctx.speedBytesPerSecond=0
    }

    private func adaptive(req:Int,len:Int64?,sup:Bool)->Int{
        if(!sup||req<=1){return 1}
        let cap=min(maxC,max(1,req))
        if(len==nil||len!<=0){return cap}
        let by=Int(ceil(Double(len!)/Double(minChunk)))
        return min(cap,max(1,by))
    }
    private func create(u:String,path:String,name:String,headers:[String:String],con:Int,tid:String?,r:@escaping FlutterResult){
        let id=tid ?? UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased()
        let target=(path as NSString).appendingPathComponent(name)
        let tmp=(NSTemporaryDirectory() as NSString).appendingPathComponent("quark_range_\(id)")
        probeReq(u:u,h:headers){[weak self] len,sup,code in
            guard let self=self else{return}
            self.q.async{
                let tot=len ?? 0
                let ad=self.adaptive(req:con,len:len,sup:sup)
                let win=min(32,ad)
                let cnt: Int = (!sup || tot<=0) ? 1 : ad
                let p=PTask(id:id,url:u,headers:headers,targetPath:target,fileName:name,totalSize:tot,chunkCount:cnt,completed:0,window:cnt==1 ? 1:win,status:RStatus.running.rawValue,tempDir:tmp,createdAt:Int64(Date().timeIntervalSince1970*1000),downloaded:0)
                let ctx=RContext(p:p)
                if(cnt>1 && tot>0){
                    let base=tot/Int64(cnt)
                    for i in 0..<cnt{let s=Int64(i)*base;let e: Int64=(i==cnt-1 ? tot-1 : s+base-1);ctx.ranges.append((s,e))}
                }
                self.tasks[id]=ctx
                try?FileManager.default.createDirectory(atPath:tmp,withIntermediateDirectories:true)
                try?FileManager.default.createDirectory(atPath:(target as NSString).deletingLastPathComponent,withIntermediateDirectories:true)
                self.resetSpeed(ctx)
                self.save(); self.emit(id:id,st:RStatus.running.rawValue,pr:0,sp:self.currentSpeed(ctx),exp:tot,code:code)
                DispatchQueue.main.async{r(id)}
                if(cnt==1){self.single(ctx:ctx)}else{self.sched(ctx)}
            }
        }
    }
    private func degrade(_ ctx:RContext){
        let cur=ctx.p.window
        if let idx=self.steps.firstIndex(of:cur), idx+1<self.steps.count{ctx.p.window=self.steps[idx+1]}
        else if(cur>8){for s in self.steps.reversed() where s<cur{ctx.p.window=s;break}}
        else{ctx.p.window=8}
        save()
    }
    private func upgrade(_ ctx:RContext){
        if(ctx.success>=ctx.p.window && ctx.p.window<maxC && isFg){
            if(ctx.p.window==32){ctx.p.window=64;save()}
            else if(ctx.p.window==64){ctx.p.window=128;save()}
            ctx.success=0
        }
    }
    private func single(ctx:RContext){
        guard let url=URL(string:ctx.p.url) else{fail(ctx,code:-1,msg:"bad url");return}
        var req=URLRequest(url:url); req.timeoutInterval=60
        for(k,v) in ctx.p.headers{req.setValue(v,forHTTPHeaderField:k)}
        let ses=isFg ? fg! : bg!
        var task:URLSessionDownloadTask!
        task=ses.downloadTask(with:req){[weak self] tmp,resp,err in
            guard let self=self else{return}
            self.q.async{
                if let task=task { ctx.activeTasks.removeAll { $0 === task } }
                if(ctx.canceled||ctx.paused){return}
                if let e=err as NSError?{self.fail(ctx,code:(resp as?HTTPURLResponse)?.statusCode ?? e.code,msg:e.localizedDescription);return}
                guard let http=resp as?HTTPURLResponse else{self.fail(ctx,code:-1,msg:"no resp");return}
                if(!(200...299).contains(http.statusCode)){self.fail(ctx,code:http.statusCode,msg:"http \(http.statusCode)");return}
                if(ctx.p.totalSize<=0){ctx.p.totalSize=max(0,http.expectedContentLength)}
                guard let tmp=tmp else{self.fail(ctx,code:http.statusCode,msg:"no tmp");return}
                do{
                    let d=ctx.p.targetPath
                    if(FileManager.default.fileExists(atPath:d)){try FileManager.default.removeItem(atPath:d)}
                    try FileManager.default.moveItem(atPath:tmp.path,toPath:d)
                    if(ctx.p.totalSize>0),let a=try?FileManager.default.attributesOfItem(atPath:d),let s=a[.size] as?UInt64,Int64(truncatingIfNeeded:s) != ctx.p.totalSize{self.fail(ctx,code:http.statusCode,msg:"size mismatch");return}
                    self.recordProgress(ctx,downloaded:ctx.p.totalSize)
                    ctx.p.status=RStatus.done.rawValue; self.resetSpeed(ctx); self.save()
                    self.emit(id:ctx.p.id,st:RStatus.done.rawValue,pr:1,sp:0,exp:ctx.p.totalSize,code:http.statusCode)
                    try?FileManager.default.removeItem(atPath:ctx.p.tempDir)
                }catch{self.fail(ctx,code:http.statusCode,msg:error.localizedDescription)}
            }
        }
        ctx.p.status=RStatus.running.rawValue
        ctx.activeTasks.append(task)
        task.resume()
        emit(id:ctx.p.id,st:RStatus.running.rawValue,pr:0.01,sp:currentSpeed(ctx),exp:ctx.p.totalSize,code:nil)
    }
    private func sched(_ ctx:RContext){
        q.async{[weak self] in
            guard let self=self else{return}
            if(ctx.paused||ctx.canceled){return}
            if(ctx.p.status != RStatus.running.rawValue){return}
            if(ctx.ranges.isEmpty || ctx.p.chunkCount<=1){return}
            var pend:[Int]=[]
            for i in 0..<ctx.ranges.count{
                let p=(ctx.p.tempDir as NSString).appendingPathComponent("chunk_\(i).dat")
                if(!FileManager.default.fileExists(atPath:p)){pend.append(i)}
            }
            if(pend.isEmpty){self.merge(ctx);return}
            let w=min(ctx.p.window,pend.count)
            let ew=self.isFg ? w : min(4,w)
            let batch=Array(pend.prefix(ew))
            let g=DispatchGroup()
            let ses=self.isFg ? self.fg! : self.bg!
            for idx in batch{
                g.enter()
                self.chunk(idx:idx,ctx:ctx,ses:ses){ok,code in
                    self.q.async{
                        if(ctx.paused||ctx.canceled||ctx.fallingBack){g.leave(); return}
                        if(ok){
                            ctx.success+=1; ctx.fail=0; ctx.p.completed+=1
                            if(ctx.p.totalSize>0 && idx<ctx.ranges.count){let r=ctx.ranges[idx]; self.recordProgress(ctx,downloaded:ctx.bytes+(r.1-r.0+1))}
                            self.upgrade(ctx)
                            let pr=ctx.p.totalSize>0 ? Double(ctx.bytes)/Double(ctx.p.totalSize) : Double(ctx.p.completed)/Double(ctx.ranges.count)
                            self.emit(id:ctx.p.id,st:RStatus.running.rawValue,pr:min(0.99,pr),sp:self.currentSpeed(ctx),exp:ctx.p.totalSize,code:code)
                            self.save()
                        } else{
                            self.fallbackToSingle(ctx)
                            g.leave(); return
                        }
                        g.leave()
                    }
                }
            }
            g.notify(queue:self.q){
                if(ctx.paused||ctx.canceled||ctx.fallingBack){return}
                if(ctx.p.status==RStatus.error.rawValue){return}
                var still=0
                for i in 0..<ctx.ranges.count{let p=(ctx.p.tempDir as NSString).appendingPathComponent("chunk_\(i).dat"); if(!FileManager.default.fileExists(atPath:p)){still+=1}}
                if(still==0){self.merge(ctx)}
                else{DispatchQueue.global().asyncAfter(deadline:.now()+0.2){self.sched(ctx)}}
            }
        }
    }
    private func chunk(idx:Int,ctx:RContext,ses:URLSession,cb:@escaping(Bool,Int)->Void){
        guard idx<ctx.ranges.count else{cb(false,-1);return}
        let r=ctx.ranges[idx]
        guard let url=URL(string:ctx.p.url) else{cb(false,-1);return}
        var req=URLRequest(url:url); req.setValue("bytes=\(r.0)-\(r.1)",forHTTPHeaderField:"Range")
        for(k,v) in ctx.p.headers{req.setValue(v,forHTTPHeaderField:k)}
        req.timeoutInterval=30; req.cachePolicy = .reloadIgnoringLocalCacheData
        let path=(ctx.p.tempDir as NSString).appendingPathComponent("chunk_\(idx).dat")
        var attempts=0
        var task:URLSessionDownloadTask!
        var start: (() -> Void)!
        start = { [weak self] in
            guard let self=self else{return}
            attempts+=1
            task=ses.downloadTask(with:req){tmp,resp,err in
                self.q.async{
                    if let t=task{ctx.activeTasks.removeAll{$0 === t}}
                    if let e=err as NSError?{
                        if(e.code==NSURLErrorTimedOut && attempts<2){start(); return}
                        cb(false,e.code==NSURLErrorTimedOut ? -1001 : e.code);return
                    }
                    guard let h=resp as?HTTPURLResponse else{cb(false,-1);return}
                    if(h.statusCode==206){
                        guard let tmp=tmp else{cb(false,h.statusCode);return}
                        let expected=r.1-r.0+1
                        if let a=try?FileManager.default.attributesOfItem(atPath:tmp.path),let s=a[.size] as?UInt64,Int64(truncatingIfNeeded:s)==expected{
                            do{
                                try FileManager.default.createDirectory(atPath:ctx.p.tempDir,withIntermediateDirectories:true)
                                if(FileManager.default.fileExists(atPath:path)){try FileManager.default.removeItem(atPath:path)}
                                try FileManager.default.moveItem(atPath:tmp.path,toPath:path)
                                cb(true,h.statusCode)
                            }catch{try?FileManager.default.removeItem(atPath:tmp.path); cb(false,h.statusCode)}
                        }else{
                            try?FileManager.default.removeItem(atPath:tmp.path)
                            cb(false,h.statusCode)
                        }
                    }else{
                        if let tmp=tmp{try?FileManager.default.removeItem(atPath:tmp.path)}
                        cb(false,h.statusCode)
                    }
                }
            }
            ctx.activeTasks.append(task)
            task.resume()
        }
        start()
    }

    /// 多分片遇到任何硬失败时（403/5xx/200 整包/超时重试后仍失败），安全回退为单连接整包下载。
    /// 仅在串行队列 q 内调用；幂等（fallingBack 置位后直接返回）。
    private func fallbackToSingle(_ ctx:RContext){
        if(ctx.fallingBack){return}
        ctx.fallingBack=true
        for t in ctx.activeTasks{t.cancel()}
        ctx.activeTasks.removeAll()
        ctx.ranges=[]
        ctx.p.chunkCount=1
        ctx.p.window=1
        ctx.p.completed=0
        try?FileManager.default.removeItem(atPath:ctx.p.tempDir)
        try?FileManager.default.createDirectory(atPath:ctx.p.tempDir,withIntermediateDirectories:true)
        self.save()
        print("[range] \(ctx.p.id) fallback to single")
        self.single(ctx:ctx)
    }
    private func merge(_ ctx:RContext){
        q.async{
            if(ctx.canceled){return}
            let t=ctx.p.targetPath; let tmp=ctx.p.tempDir
            do{
                if(FileManager.default.fileExists(atPath:t)){try FileManager.default.removeItem(atPath:t)}
                try FileManager.default.createDirectory(atPath:(t as NSString).deletingLastPathComponent,withIntermediateDirectories:true)
                FileManager.default.createFile(atPath:t,contents:nil)
                guard let fh=FileHandle(forWritingAtPath:t) else{self.fail(ctx,code:-1,msg:"open fail");return}
                for i in 0..<ctx.ranges.count{
                    let p=(tmp as NSString).appendingPathComponent("chunk_\(i).dat")
                    guard let d=FileManager.default.contents(atPath:p) else{fh.closeFile(); self.fail(ctx,code:-1,msg:"missing \(i)");return}
                    fh.write(d)
                }
                fh.closeFile()
                if(ctx.p.totalSize>0),let a=try?FileManager.default.attributesOfItem(atPath:t),let s=a[.size] as?UInt64,Int64(truncatingIfNeeded:s) != ctx.p.totalSize{self.fail(ctx,code:200,msg:"size mismatch");return}
                self.recordProgress(ctx,downloaded:ctx.p.totalSize)
                ctx.p.status=RStatus.done.rawValue; self.resetSpeed(ctx); self.save()
                self.emit(id:ctx.p.id,st:RStatus.done.rawValue,pr:1,sp:0,exp:ctx.p.totalSize,code:200)
                try?FileManager.default.removeItem(atPath:tmp)
            }catch{self.fail(ctx,code:-1,msg:error.localizedDescription)}
        }
    }
    private func fail(_ ctx:RContext,code:Int,msg:String){
        ctx.p.status=RStatus.error.rawValue; resetSpeed(ctx); save()
        emit(id:ctx.p.id,st:RStatus.error.rawValue,pr:0,sp:0,exp:ctx.p.totalSize,code:code)
        print("[range] \(ctx.p.id) fail \(code) \(msg)")
    }
    private func pause(id:String,r:@escaping FlutterResult){
        q.async{
            guard let c=self.tasks[id] else{r(FlutterError(code:"not_found",message:"not found",details:nil));return}
            if(c.p.status==RStatus.done.rawValue){DispatchQueue.main.async{r(nil)};return}
            c.paused=true; c.p.status=RStatus.pause.rawValue; self.resetSpeed(c); self.save()
            let pr=c.p.totalSize>0 ? Double(c.p.downloaded)/Double(c.p.totalSize) : 0
            self.emit(id:id,st:RStatus.pause.rawValue,pr:pr,sp:0,exp:c.p.totalSize,code:nil)
            DispatchQueue.main.async{r(nil)}
        }
    }
    private func resume(id:String,r:@escaping FlutterResult){
        q.async{
            guard let c=self.tasks[id] else{r(FlutterError(code:"not_found",message:"not found",details:nil));return}
            if(c.p.status==RStatus.done.rawValue){DispatchQueue.main.async{r(FlutterError(code:"done",message:"done",details:nil))};return}
            c.paused=false; c.canceled=false; c.p.status=RStatus.running.rawValue; c.fail=0; self.resetSpeed(c); self.save()
            let pr=c.p.totalSize>0 ? Double(c.p.downloaded)/Double(c.p.totalSize) : 0
            self.emit(id:id,st:RStatus.running.rawValue,pr:pr,sp:self.currentSpeed(c),exp:c.p.totalSize,code:nil)
            if(c.ranges.isEmpty && c.p.chunkCount==1){self.single(ctx:c)}else{self.sched(c)}
            DispatchQueue.main.async{r(nil)}
        }
    }
    private func remove(id:String,force:Bool,r:@escaping FlutterResult){
        q.async{
            guard let c=self.tasks[id] else{DispatchQueue.main.async{r(nil)};return}
            c.canceled=true; c.paused=true; self.resetSpeed(c)
            for task in c.activeTasks{task.cancel()}; c.activeTasks.removeAll()
            if(force){try?FileManager.default.removeItem(atPath:c.p.targetPath)}
            try?FileManager.default.removeItem(atPath:c.p.tempDir)
            self.tasks.removeValue(forKey:id); self.save()
            self.emit(id:id,st:RStatus.error.rawValue,pr:0,sp:0,exp:0,code:nil)
            DispatchQueue.main.async{r(nil)}
        }
    }
    private func removeAll(ids:[String]?,r:@escaping FlutterResult){
        q.async{
            let t=ids ?? Array(self.tasks.keys)
            for id in t{if let c=self.tasks[id]{c.canceled=true; for task in c.activeTasks{task.cancel()}; c.activeTasks.removeAll(); try?FileManager.default.removeItem(atPath:c.p.targetPath); try?FileManager.default.removeItem(atPath:c.p.tempDir); self.tasks.removeValue(forKey:id)}}
            self.save(); DispatchQueue.main.async{r(nil)}
        }
    }
    private func pauseAll(ids:[String]?,r:@escaping FlutterResult){
        q.async{
            let t=ids ?? Array(self.tasks.keys)
            for id in t{if let c=self.tasks[id]{c.paused=true; c.p.status=RStatus.pause.rawValue; self.resetSpeed(c)}}
            self.save(); DispatchQueue.main.async{r(nil)}
        }
    }
    private func list(r:@escaping FlutterResult){
        q.async{
            let arr:[[String:Any]]=self.tasks.values.map{ctx in
                let speed=self.currentSpeed(ctx)
                let p=ctx.p; let pr:Double=p.totalSize>0 ? Double(p.downloaded)/Double(p.totalSize) : (p.status==RStatus.done.rawValue ? 1:0)
                return["id":p.id,"name":p.fileName,"status":p.status,"size":p.totalSize,"downloaded":p.downloaded,"speed":speed,"createdAt":p.createdAt,"targetPath":p.targetPath,"tempDir":p.tempDir,"chunkCount":p.chunkCount,"completedChunks":p.completed,"currentWindow":p.window,"progress":pr]
            }
            DispatchQueue.main.async{r(arr)}
        }
    }
    private func save(){
        let a=tasks.values.map{$0.p}
        if let d=try?JSONEncoder().encode(a){try?d.write(to:URL(fileURLWithPath:persistPath()))}
    }
    private func persistPath()->String{
        let d=NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory,.userDomainMask,true).first ?? NSTemporaryDirectory()
        try?FileManager.default.createDirectory(atPath:d,withIntermediateDirectories:true)
        return (d as NSString).appendingPathComponent(kPersist)
    }
    private func load(){
        let p=persistPath()
        guard let d=try?Data(contentsOf:URL(fileURLWithPath:p)),let a=try?JSONDecoder().decode([PTask].self,from:d) else{return}
        for v in a{
            if(v.status==RStatus.done.rawValue){continue}
            var m=v; if(m.status==RStatus.running.rawValue){m.status=RStatus.wait.rawValue}
            let c=RContext(p:m)
            if(m.chunkCount>1 && m.totalSize>0){
                let b=m.totalSize/Int64(m.chunkCount)
                for i in 0..<m.chunkCount{let s=Int64(i)*b; let e:Int64=(i==m.chunkCount-1 ? m.totalSize-1 : s+b-1); c.ranges.append((s,e))}
                var dl:Int64=0
                for i in 0..<m.chunkCount{let pp=(m.tempDir as NSString).appendingPathComponent("chunk_\(i).dat"); if let at=try?FileManager.default.attributesOfItem(atPath:pp),let s=at[.size] as?UInt64{dl += Int64(truncatingIfNeeded:s)}}
                c.bytes=dl; c.p.downloaded=dl
            }
            tasks[v.id]=c
        }
    }
}
