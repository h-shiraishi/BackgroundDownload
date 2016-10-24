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
            resumeData = try Data(contentsOf: fileUrl)
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
}
