import Flutter
import UIKit

public class IosParallelPlugin: NSObject, FlutterPlugin {
    private static let channelName = "quarklite.com/ios_parallel"
    private var channel: FlutterMethodChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = IosParallelPlugin()
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    static func registerManually(messenger: FlutterBinaryMessenger) {
        let instance = IosParallelPlugin()
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
        instance.channel = channel
        channel.setMethodCallHandler { call, result in
            instance.handleInternal(call, result: result)
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        handleInternal(call, result: result)
    }

    private func handleInternal(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "createParallel":
            guard let args = call.arguments as? [String: Any],
                  let taskId = args["taskId"] as? String,
                  let url = args["url"] as? String,
                  let targetPath = args["targetPath"] as? String else {
                result(FlutterError(code: "BAD_ARGS", message: "missing args", details: nil)); return
            }
            let headers = args["headers"] as? [String:String] ?? [:]
            let displayName = args["displayName"] as? String ?? (targetPath as NSString).lastPathComponent
            let connections: Int
            if let n = args["connections"] as? Int { connections = n }
            else if let n = args["connections"] as? NSNumber { connections = n.intValue }
            else { connections = 32 }
            let channel = self.channel
            IosParallelDownloader.shared.startDownload(taskId: taskId, url: url, headers: headers, targetPath: targetPath, displayName: displayName, connections: connections, progress: { done, total, speed in
                DispatchQueue.main.async {
                    channel?.invokeMethod("onProgress", arguments: ["taskId": taskId, "done": done, "total": total, "speed": speed])
                }
            }, completion: { res in
                DispatchQueue.main.async {
                    switch res {
                    case .success(let path):
                        channel?.invokeMethod("onComplete", arguments: ["taskId": taskId, "path": path])
                        result(["ok": true, "path": path])
                    case .failure(let err):
                        let msg = (err as NSError).localizedDescription
                        let code = (err as? LocalizedError)?.errorDescription ?? msg
                        channel?.invokeMethod("onError", arguments: ["taskId": taskId, "error": code])
                        result(FlutterError(code: "DL_FAILED", message: code, details: msg))
                    }
                }
            })
        case "cancel":
            guard let args = call.arguments as? [String: Any], let taskId = args["taskId"] as? String else {
                result(FlutterError(code: "BAD_ARGS", message: "missing taskId", details: nil)); return
            }
            IosParallelDownloader.shared.cancel(taskId: taskId)
            result(["ok": true])
        case "computeParts":
            var len: Int64 = 0
            var req: Int = 32
            if let args = call.arguments as? [String: Any] {
                if let v = args["totalLength"] as? Int64 { len = v }
                else if let v = args["totalLength"] as? Int { len = Int64(v) }
                else if let v = args["totalLength"] as? NSNumber { len = v.int64Value }
                if let v = args["connections"] as? Int { req = v }
                else if let v = args["connections"] as? NSNumber { req = v.intValue }
            }
            let n = IosParallelDownloader.computeParts(totalLength: len, requested: req)
            result(["parts": n])
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
