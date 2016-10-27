//
//  DownloadService.swift
//  backgroundDownload
//
//  Created by Edelweiss on 2016/10/20.
//  Copyright © 2016年 Edelweiss. All rights reserved.
//

import UIKit
import Alamofire

/**
ダウンロードの状態
*/
public enum DownloadState : Int {
    case Waiting
    case Progressing
    case Pausing
    case Completed

    func toBtnTitle() -> String {
        switch self {
        case .Waiting:
            return "開始"
        case .Progressing:
            return "一時停止"
        case .Pausing:
            return "再開"
        case .Completed:
            return "完了"
        }
    }
}

public class DownloadService: NSObject {
    private static let key : String = "sessionId"
    private static let requestFormat : String = "%@?tag=%d"
    private static let resumeFileFormat : String = "%d.plist"

    private var manager : SessionManager!
    
    private var requests : [String : DownloadRequest] = [String : DownloadRequest]()
    
    public var progressClosure : ((Int, Double) -> Void)?
    
    public var completedClosure : ((Int) -> Void)?
    
    public var pauseClosure : ((Int) -> Void)?
    
    public var errorClosure : ((Error) -> Void)?
    
    public var prevDownloadClosure : ((Int) -> Void)?

    public func initManager() {
        let configuration = URLSessionConfiguration.background(withIdentifier: DownloadService.key)
        self.manager = Alamofire.SessionManager(configuration: configuration)
        
        //アプリケーションを閉じたときに途中から再開する
        self.manager.session.getAllTasks(completionHandler: {[weak self] tasks in
            guard let wself = self else {
                return
            }
            
            for task in tasks {
                guard let error = task.error else {
                    continue
                }
                
                if (error as NSError).code == NSURLErrorCancelled {
                    let query = task.originalRequest!.url!.query!
                    let queryAr = query.components(separatedBy: "&")
                    for keyParam in queryAr {
                        let keyParamAr = keyParam.components(separatedBy: "=")
                        if keyParamAr[0] == "tag" {
                            let id = Int(keyParamAr[1])!
                            do {
                                //plistを保存する
                                let plist = try PropertyListSerialization.propertyList(from: (((error as NSError).userInfo) as NSDictionary)["NSURLSessionDownloadTaskResumeData"] as! Data, options: [.mutableContainersAndLeaves], format: nil)
                                let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                                let fileUrl = cacheURL.appendingPathComponent(String(format : DownloadService.resumeFileFormat, id))
                                if !(plist as! NSDictionary).write(to: fileUrl, atomically: true) {
                                    print("plist write error")
                                    return
                                }
                                
                                if let prevDownloadClosure = wself.prevDownloadClosure {
                                    prevDownloadClosure(id)
                                }
                                
                                wself.resumeDownload(id: id, url: task.originalRequest!.url!.path)
                            } catch {
                                print("plist read error")
                                continue
                            }
                        }
                    }
                }
            }
        })
    }

    /**
     ダウンロードのリクエストを追加する
    */
    public func addDownload(id : Int, url : String) {
        let destination: DownloadRequest.DownloadFileDestination = { _, _ in
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

            let splitUrl = url.components(separatedBy: "/")
            let fileURL = documentsURL.appendingPathComponent(splitUrl[splitUrl.count - 1])

            return (fileURL, [.removePreviousFile, .createIntermediateDirectories])
        }
        
        let request = self.manager
            .download(String(format : DownloadService.requestFormat, url, id), to: destination)
            .downloadProgress(closure: {[weak self] progress  in
                guard let wself = self else {
                    return
                }
                
                if let progressClosure = wself.progressClosure {
                    progressClosure(id, progress.fractionCompleted)
                }
            })
            .response(completionHandler: {[weak self] response in
                guard let wself = self else {
                    return
                }
                
                guard let error = response.error else {
                    if let completedClosure = wself.completedClosure {
                        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                        let fileUrl = cacheURL.appendingPathComponent(String(format : DownloadService.resumeFileFormat, id))
                        if FileManager.default.fileExists(atPath: fileUrl.path) {
                            do {
                                try FileManager.default.removeItem(at: fileUrl)
                            } catch {
                                print("file delete error")
                            }
                        }
                        
                        completedClosure(id)
                    }
                    return
                }
                
                //キャンセルの場合もエラーが返ってくる
                guard let resumeData = response.resumeData else {
                    if let errorClosure = wself.errorClosure {
                        errorClosure(error)
                    }
                    return
                }
                
                do {
                    //plistを保存する
                    let plist = try PropertyListSerialization.propertyList(from: resumeData, options: [.mutableContainersAndLeaves], format: nil)
                    let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    let fileUrl = cacheURL.appendingPathComponent(String(format : DownloadService.resumeFileFormat, id))
                    if !(plist as! NSDictionary).write(to: fileUrl, atomically: true) {
                        print("plist write error")
                        return
                    }
                    
                    if let pauseClosure = wself.pauseClosure {
                        pauseClosure(id)
                    }
                } catch {
                    print("plist read error")
                    return
                }
                
                return
            })
        
        self.requests[String(id)] = request
    }
    
    /**
     ダウンロードを一時停止する
    */
    public func pauseDownload(id : Int) -> Bool {
        guard let request = self.requests[String(id)] else {
            return false
        }
        
        request.cancel()
        self.requests.removeValue(forKey: String(id))
        
        return true
    }
    
    /**
     ダウンロードを再開する
    */
    public func resumeDownload(id : Int, url : String){
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let fileUrl = cacheURL.appendingPathComponent(String(format : DownloadService.resumeFileFormat, id))
        
        //再開データが存在するか確認する
        if !FileManager.default.fileExists(atPath: fileUrl.path) {
            self.addDownload(id: id, url: url)
            return
        }
        
        //再開データを読み込む
        var resumeData : Data?
        do {
            resumeData = self.correctResumeData(try Data(contentsOf: fileUrl))
        } catch {
            self.addDownload(id: id, url: url)
            return
        }
        
        let destination: DownloadRequest.DownloadFileDestination = { _, _ in
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            
            let splitUrl = url.components(separatedBy: "/")
            let fileURL = documentsURL.appendingPathComponent(splitUrl[splitUrl.count - 1])
            
            return (fileURL, [.removePreviousFile, .createIntermediateDirectories])
        }
        
        let request = self.manager
            .download(resumingWith: resumeData!, to: destination)
            .downloadProgress(closure: {[weak self] progress  in
                guard let wself = self else {
                    return
                }
                
                if let progressClosure = wself.progressClosure {
                    progressClosure(id, progress.fractionCompleted)
                }
                })
            .response(completionHandler: {[weak self] response in
                guard let wself = self else {
                    return
                }
                
                guard let error = response.error else {
                    if let completedClosure = wself.completedClosure {
                        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                        let fileUrl = cacheURL.appendingPathComponent(String(format : DownloadService.resumeFileFormat, id))
                        if FileManager.default.fileExists(atPath: fileUrl.path) {
                            do {
                                try FileManager.default.removeItem(at: fileUrl)
                            } catch {
                                print("file delete error")
                            }
                        }
                        
                        completedClosure(id)
                    }
                    return
                }
                
                guard let resumeData = response.resumeData else {
                    if let errorClosure = wself.errorClosure {
                        errorClosure(error)
                    }
                    return
                }
                
                do {
                    //plistを保存する
                    let plist = try PropertyListSerialization.propertyList(from: resumeData, options: [.mutableContainersAndLeaves], format: nil)
                    let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    let fileUrl = cacheURL.appendingPathComponent(String(format : DownloadService.resumeFileFormat, id))
                    if !(plist as! NSDictionary).write(to: fileUrl, atomically: true) {
                        print("plist write error")
                        return
                    }
                    
                    if let pauseClosure = wself.pauseClosure {
                        pauseClosure(id)
                    }
                } catch {
                    print("plist read error")
                    return
                }
                
                return
                })
        
        self.requests[String(id)] = request
    }
    
    private func correct(requestData data: Data?) -> Data? {
        guard let data = data else {
            return nil
        }
        if NSKeyedUnarchiver.unarchiveObject(with: data) != nil {
            return data
        }
        guard let archive = (try? PropertyListSerialization.propertyList(from: data, options: [.mutableContainersAndLeaves], format: nil)) as? NSMutableDictionary else {
            return nil
        }
        // Rectify weird __nsurlrequest_proto_props objects to $number pattern
        var k = 0
        while ((archive["$objects"] as? NSArray)?[1] as? NSDictionary)?.object(forKey: "$\(k)") != nil {
            k += 1
        }
        var i = 0
        while ((archive["$objects"] as? NSArray)?[1] as? NSDictionary)?.object(forKey: "__nsurlrequest_proto_prop_obj_\(i)") != nil {
            let arr = archive["$objects"] as? NSMutableArray
            if let dic = arr?[1] as? NSMutableDictionary, let obj = dic["__nsurlrequest_proto_prop_obj_\(i)"] {
                dic.setObject(obj, forKey: "$\(i + k)" as NSString)
                dic.removeObject(forKey: "__nsurlrequest_proto_prop_obj_\(i)")
                arr?[1] = dic
                archive["$objects"] = arr
            }
            i += 1
        }
        if ((archive["$objects"] as? NSArray)?[1] as? NSDictionary)?.object(forKey: "__nsurlrequest_proto_props") != nil {
            let arr = archive["$objects"] as? NSMutableArray
            if let dic = arr?[1] as? NSMutableDictionary, let obj = dic["__nsurlrequest_proto_props"] {
                dic.setObject(obj, forKey: "$\(i + k)" as NSString)
                dic.removeObject(forKey: "__nsurlrequest_proto_props")
                arr?[1] = dic
                archive["$objects"] = arr
            }
        }
        /* I think we have no reason to keep this section in effect
         for item in (archive["$objects"] as? NSMutableArray) ?? [] {
         if let cls = item as? NSMutableDictionary, cls["$classname"] as? NSString == "NSURLRequest" {
         cls["$classname"] = NSString(string: "NSMutableURLRequest")
         (cls["$classes"] as? NSMutableArray)?.insert(NSString(string: "NSMutableURLRequest"), at: 0)
         }
         }*/
        // Rectify weird "NSKeyedArchiveRootObjectKey" top key to NSKeyedArchiveRootObjectKey = "root"
        if let obj = (archive["$top"] as? NSMutableDictionary)?.object(forKey: "NSKeyedArchiveRootObjectKey") as AnyObject? {
            (archive["$top"] as? NSMutableDictionary)?.setObject(obj, forKey: NSKeyedArchiveRootObjectKey as NSString)
            (archive["$top"] as? NSMutableDictionary)?.removeObject(forKey: "NSKeyedArchiveRootObjectKey")
        }
        // Reencode archived object
        let result = try? PropertyListSerialization.data(fromPropertyList: archive, format: PropertyListSerialization.PropertyListFormat.binary, options: PropertyListSerialization.WriteOptions())
        return result
    }
    
    private func getResumeDictionary(_ data: Data) -> NSMutableDictionary? {
        // In beta versions, resumeData is NSKeyedArchive encoded instead of plist
        var iresumeDictionary: NSMutableDictionary? = nil
        if #available(iOS 10.0, OSX 10.12, *) {
            var root : AnyObject? = nil
            let keyedUnarchiver = NSKeyedUnarchiver(forReadingWith: data)
            
            do {
                root = try keyedUnarchiver.decodeTopLevelObject(forKey: "NSKeyedArchiveRootObjectKey") ?? nil
                if root == nil {
                    root = try keyedUnarchiver.decodeTopLevelObject(forKey: NSKeyedArchiveRootObjectKey)
                }
            } catch {}
            keyedUnarchiver.finishDecoding()
            iresumeDictionary = root as? NSMutableDictionary
            
        }
        
        if iresumeDictionary == nil {
            do {
                iresumeDictionary = try PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions(), format: nil) as? NSMutableDictionary;
            } catch {}
        }
        
        return iresumeDictionary
    }
    
    private func correctResumeData(_ data: Data?) -> Data? {
        //データの修正はiOS10以上で行う
        if !self.laterThanEqualOS(version: 10.0) {
            return data
        }
        
        let kResumeCurrentRequest = "NSURLSessionResumeCurrentRequest"
        let kResumeOriginalRequest = "NSURLSessionResumeOriginalRequest"
        
        guard let data = data, let resumeDictionary = getResumeDictionary(data) else {
            return nil
        }
        
        resumeDictionary[kResumeCurrentRequest] = correct(requestData: resumeDictionary[kResumeCurrentRequest] as? Data)
        resumeDictionary[kResumeOriginalRequest] = correct(requestData: resumeDictionary[kResumeOriginalRequest] as? Data)
        
        let result = try? PropertyListSerialization.data(fromPropertyList: resumeDictionary, format: PropertyListSerialization.PropertyListFormat.xml, options: PropertyListSerialization.WriteOptions())
        return result
    }
    
    /**
     @param version 指定したバージョン
     指定したバージョン以上の場合にtrue
    */
    private func laterThanEqualOS(version : Float) -> Bool {
        let systemVersion = UIDevice.current.systemVersion
        return (systemVersion as NSString).floatValue >= version
    }
}
