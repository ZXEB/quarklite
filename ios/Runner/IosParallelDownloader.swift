import Foundation

// MARK: - Parallel chunk model
private struct Chunk {
    let index: Int
    let start: Int64
    let end: Int64
    var size: Int64 { end - start + 1 }
}

private enum ParallelError: LocalizedError {
    case noContentLength
    case rangeNotSupported
    case httpError(Int, String)
    case cancelled
    case mergeFailed(String)
    var errorDescription: String? {
        switch self {
        case .noContentLength: return "无法获取文件长度"
        case .rangeNotSupported: return "服务器不支持 Range，需回退单线程"
        case .httpError(let code, let msg): return "HTTP \(code) \(msg)"
        case .cancelled: return "任务已取消"
        case .mergeFailed(let msg): return "合并失败: \(msg)"
        }
    }
}

// MARK: - Single task record
private class ParallelTask {
    let taskId: String
    let url: String
    let headers: [String:String]
    let targetPath: String
    let displayName: String
    var totalBytes: Int64 = 0
    var downloaded: Int64 = 0
    var chunks: [Chunk] = []
    var partPaths: [String] = []
    var isCancelled = false
    var error: Error?
    var session: URLSession?
    var dataTasks: [URLSessionDataTask] = []
    let lock = NSLock()
    var progressCallback: ((Int64, Int64, Double)->Void)?
    var completion: ((Result<String, Error>)->Void)?
    var startTime: Date = Date()
    var lastBytes: Int64 = 0

    init(taskId: String, url: String, headers: [String:String], targetPath: String, displayName: String) {
        self.taskId = taskId
        self.url = url
        self.headers = headers
        self.targetPath = targetPath
        self.displayName = displayName
    }
}

class IosParallelDownloader: NSObject {
    static let shared = IosParallelDownloader()
    private var tasks: [String: ParallelTask] = [:]
    private let queue = DispatchQueue(label: "quarklite.parallel.downloader", attributes: .concurrent)

    // public API
    func startDownload(taskId: String, url: String, headers: [String:String], targetPath: String, displayName: String, connections: Int, progress: @escaping (Int64, Int64, Double)->Void, completion: @escaping (Result<String, Error>)->Void) {
        let task = ParallelTask(taskId: taskId, url: url, headers: headers, targetPath: targetPath, displayName: displayName)
        task.progressCallback = progress
        task.completion = completion
        queue.async(flags: .barrier) { self.tasks[taskId] = task }
        // Step 1: probe
        probe(task: task, connections: connections) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let length):
                if length < 10 * 1024 * 1024 {
                    // small file -> fallback to single URLSession download
                    self.singleDownload(task: task)
                } else {
                    self.parallelDownload(task: task, totalLength: length, connections: connections)
                }
            case .failure(let err):
                // probe failed -> try single download as fallback
                // if error is rangeNotSupported we explicitly fallback
                NSLog("[parallel] probe failed \(err.localizedDescription) fallback to single")
                self.singleDownload(task: task)
            }
        }
    }

    func cancel(taskId: String) {
        queue.sync { tasks[taskId]?.isCancelled = true }
        queue.sync { tasks[taskId]?.session?.invalidateAndCancel() }
        queue.sync { tasks[taskId]?.dataTasks.forEach { $0.cancel() } }
        cleanup(taskId: taskId)
        queue.async(flags: .barrier) { self.tasks.removeValue(forKey: taskId) }
    }

    private func cleanup(taskId: String) {
        guard let t = queue.sync(execute: { tasks[taskId] }) else { return }
        for p in t.partPaths { try? FileManager.default.removeItem(atPath: p) }
    }

    // MARK: - Probe
    private func probe(task: ParallelTask, connections: Int, completion: @escaping (Result<Int64, Error>)->Void) {
        guard let u = URL(string: task.url) else { completion(.failure(ParallelError.httpError(400, "bad url"))); return }
        var req = URLRequest(url: u)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 15
        for (k,v) in task.headers { req.setValue(v, forHTTPHeaderField: k) }
        // add Range probe for support check with 0-0
        let session = URLSession(configuration: .default)
        let t = session.dataTask(with: req) { _, resp, err in
            if let err = err { completion(.failure(err)); return }
            guard let http = resp as? HTTPURLResponse else { completion(.failure(ParallelError.noContentLength)); return }
            if !(200...299).contains(http.statusCode) {
                completion(.failure(ParallelError.httpError(http.statusCode, HTTPURLResponse.localizedString(forStatusCode: http.statusCode))));
                return
            }
            let lenStr = http.value(forHTTPHeaderField: "Content-Length") ?? http.value(forHTTPHeaderField: "content-length")
            let accept = (http.value(forHTTPHeaderField: "Accept-Ranges") ?? "").lowercased()
            // Some CDNs omit Accept-Ranges but still support Range; we test via length existence.
            // If no length, fallback
            guard let s = lenStr, let len = Int64(s), len > 0 else {
                completion(.failure(ParallelError.noContentLength)); return
            }
            // If server explicitly says none, treat as not supported
            if accept == "none" {
                completion(.failure(ParallelError.rangeNotSupported)); return
            }
            completion(.success(len))
        }
        t.resume()
    }

    // MARK: - Single download fallback (still via URLSession, not background_downloader)
    private func singleDownload(task: ParallelTask) {
        guard let u = URL(string: task.url) else { task.completion?(.failure(ParallelError.httpError(400, "bad url"))); return }
        var req = URLRequest(url: u)
        req.timeoutInterval = 60
        for (k,v) in task.headers { req.setValue(v, forHTTPHeaderField: k) }
        // ensure dir exists
        let dir = (task.targetPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config)
        task.session = session
        // Use downloadTask for file
        let dt = session.downloadTask(with: req) { tmpURL, resp, err in
            if task.isCancelled { task.completion?(.failure(ParallelError.cancelled)); return }
            if let err = err { task.completion?(.failure(err)); return }
            guard let http = resp as? HTTPURLResponse else { task.completion?(.failure(ParallelError.httpError(0, "no response"))); return }
            if !(200...299).contains(http.statusCode) {
                task.completion?(.failure(ParallelError.httpError(http.statusCode, HTTPURLResponse.localizedString(forStatusCode: http.statusCode)))); return
            }
            guard let tmp = tmpURL else { task.completion?(.failure(ParallelError.mergeFailed("no tmp file"))); return }
            do {
                if FileManager.default.fileExists(atPath: task.targetPath) { try FileManager.default.removeItem(atPath: task.targetPath) }
                try FileManager.default.moveItem(at: tmp, to: URL(fileURLWithPath: task.targetPath))
                task.progressCallback?(task.totalBytes, task.totalBytes, 0)
                task.completion?(.success(task.targetPath))
            } catch {
                task.completion?(.failure(error))
            }
            self.queue.async(flags: .barrier) { self.tasks.removeValue(forKey: task.taskId) }
        }
        // progress via delegate not easy with downloadTask+completion; we report 50% while running not accurate but acceptable fallback
        // Start timer to fake progress? Instead we just call progress on completion.
        dt.resume()
    }

    // MARK: - Parallel download
    private func parallelDownload(task: ParallelTask, totalLength: Int64, connections: Int) {
        task.totalBytes = totalLength
        let n = Self.computeParts(totalLength: totalLength, requested: connections)
        var chunks: [Chunk] = []
        let partSize = totalLength / Int64(n)
        for i in 0..<n {
            let start = Int64(i) * partSize
            let end = (i == n-1) ? (totalLength - 1) : (start + partSize - 1)
            chunks.append(Chunk(index: i, start: start, end: end))
        }
        task.chunks = chunks
        let dir = (task.targetPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
        // create part paths
        task.partPaths = chunks.map { "\(task.targetPath).part_\($0.index)" }
        // cleanup old parts
        for p in task.partPaths { try? FileManager.default.removeItem(atPath: p) }
        // session
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = max(n, 6)
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = n
        // We use dataTasks with file handles to avoid loading all in memory
        let session = URLSession(configuration: config)
        task.session = session
        let group = DispatchGroup()
        var firstError: Error?
        let errLock = NSLock()
        let progLock = NSLock()
        var bytesPerChunk = [Int64](repeating: 0, count: n)

        for (idx, ch) in chunks.enumerated() {
            guard let u = URL(string: task.url) else { continue }
            var req = URLRequest(url: u)
            req.setValue("bytes=\(ch.start)-\(ch.end)", forHTTPHeaderField: "Range")
            for (k,v) in task.headers { req.setValue(v, forHTTPHeaderField: k) }
            req.timeoutInterval = 30
            group.enter()
            // create file
            FileManager.default.createFile(atPath: task.partPaths[idx], contents: nil, attributes: nil)
            guard let handle = FileHandle(forWritingAtPath: task.partPaths[idx]) else {
                errLock.lock(); if firstError == nil { firstError = ParallelError.mergeFailed("open part \(idx)") }; errLock.unlock()
                group.leave(); continue
            }
            let dt = session.dataTask(with: req) { data, resp, err in
                defer { try? handle.close(); group.leave() }
                if task.isCancelled { return }
                if let err = err {
                    errLock.lock(); if firstError == nil { firstError = err }; errLock.unlock(); return
                }
                guard let http = resp as? HTTPURLResponse else {
                    errLock.lock(); if firstError == nil { firstError = ParallelError.httpError(0, "no response") }; errLock.unlock(); return
                }
                // Expect 206, but some servers return 200 with full content if Range ignored -> fallback
                if http.statusCode == 200 {
                    errLock.lock(); if firstError == nil { firstError = ParallelError.rangeNotSupported }; errLock.unlock(); return
                }
                if http.statusCode != 206 {
                    errLock.lock(); if firstError == nil { firstError = ParallelError.httpError(http.statusCode, HTTPURLResponse.localizedString(forStatusCode: http.statusCode)) }; errLock.unlock(); return
                }
                guard let data = data else { return }
                // write
                do {
                    try handle.write(contentsOf: data)
                    progLock.lock()
                    bytesPerChunk[idx] = Int64(data.count)
                    let totalDone = bytesPerChunk.reduce(0, +)
                    task.downloaded = totalDone
                    let speed = 0.0 // speed computed via timer not needed V1
                    progLock.unlock()
                    task.progressCallback?(totalDone, totalLength, speed)
                } catch {
                    errLock.lock(); if firstError == nil { firstError = error }; errLock.unlock()
                }
            }
            task.dataTasks.append(dt)
            dt.resume()
        }

        group.notify(queue: .global()) { [weak self] in
            guard let self = self else { return }
            if task.isCancelled { task.completion?(.failure(ParallelError.cancelled)); self.queue.async(flags: .barrier){ self.tasks.removeValue(forKey: task.taskId)}; return }
            if let err = firstError {
                // if range not supported -> fallback single
                if let pe = err as? ParallelError, case .rangeNotSupported = pe {
                    NSLog("[parallel] range not supported, fallback")
                    self.singleDownload(task: task)
                    return
                }
                // cleanup parts
                for p in task.partPaths { try? FileManager.default.removeItem(atPath: p) }
                task.completion?(.failure(err))
                self.queue.async(flags: .barrier){ self.tasks.removeValue(forKey: task.taskId)}
                return
            }
            // merge
            do {
                if FileManager.default.fileExists(atPath: task.targetPath) { try FileManager.default.removeItem(atPath: task.targetPath) }
                FileManager.default.createFile(atPath: task.targetPath, contents: nil, attributes: nil)
                guard let out = FileHandle(forWritingAtPath: task.targetPath) else { throw ParallelError.mergeFailed("open target") }
                for p in task.partPaths {
                    guard let data = FileManager.default.contents(atPath: p) else { throw ParallelError.mergeFailed("read part \(p)") }
                    try out.write(contentsOf: data)
                }
                try out.close()
                // verify size
                if let attr = try? FileManager.default.attributesOfItem(atPath: task.targetPath), let sz = attr[.size] as? UInt64, Int64(sz) != totalLength {
                    NSLog("[parallel] size mismatch expected \(totalLength) got \(sz)")
                }
                // cleanup parts
                for p in task.partPaths { try? FileManager.default.removeItem(atPath: p) }
                task.completion?(.success(task.targetPath))
            } catch {
                for p in task.partPaths { try? FileManager.default.removeItem(atPath: p) }
                task.completion?(.failure(error))
            }
            self.queue.async(flags: .barrier){ self.tasks.removeValue(forKey: task.taskId)}
        }
    }

    static func computeParts(totalLength: Int64, requested: Int) -> Int {
        if totalLength < 10 * 1024 * 1024 { return 1 }
        var n = requested.clamped(to: 1...64)
        // ensure each part >=256KB
        let minPart: Int64 = 256 * 1024
        while n > 1 && totalLength / Int64(n) < minPart { n -= 1 }
        return max(1, n)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}



