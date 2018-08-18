//
//  ViewController.swift
//  backgroundDownload
//
//  Created by Edelweiss on 2016/10/20.
//  Copyright © 2016年 Edelweiss. All rights reserved.
//

import UIKit

class ViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    private static let tableCellIdentifier = "downloadTableCell"
    
    @IBOutlet private weak var tableView : UITableView!
    
    private var downloadList : [TableViewCellData] = [TableViewCellData]()
    
    var downloadService : DownloadService!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        self.downloadService = DownloadService()
        self.downloadService.initManager()
        
        //DLが進行中の場合
        self.downloadService.progressClosure = {[weak self] id, progress in
            guard let wself = self else {
                return
            }
            
            //対象を探す
            let index = wself.searchTarget(id: id)
            
            //進捗を更新する
            if wself.downloadList[index].state == .Progressing {
                wself.downloadList[index].progress = Float(progress)
                wself.tableView.reloadData()
            }
        }
        
        //DLが完了した場合
        self.downloadService.completedClosure = {[weak self] id in
            guard let wself = self else {
                return
            }
            
            //対象を探す
            let index = wself.searchTarget(id: id)
            
            //進捗を更新する
            if wself.downloadList[index].state == .Progressing {
                wself.downloadList[index].state = .Completed
                wself.downloadList[index].progress = 1.0
                wself.tableView.reloadData()
            }
        }
        
        //DLが一時停止になった場合
        self.downloadService.pauseClosure = {[weak self] id in
            guard let wself = self else {
                return
            }
            
            //対象を探す
            let index = wself.searchTarget(id: id)
            
            //一時停止する
            if wself.downloadList[index].state == .Progressing {
                wself.downloadList[index].state = .Pausing
                wself.tableView.reloadData()
            }
        }
        
        //エラーが発生した場合
        self.downloadService.errorClosure = {[weak self] error in
            guard let wself = self else {
                return
            }
            
            //アラートの表示
            let alertViewController = UIAlertController(title: "エラー", message: "ダウンロードに失敗しました", preferredStyle: .alert)
            let cancelAction: UIAlertAction = UIAlertAction(title: "キャンセル", style: .cancel, handler: nil)
            alertViewController.addAction(cancelAction)
            
            wself.present(alertViewController, animated: true, completion: nil)
        }
        
        //前回のダウンロード情報が残っていた場合
        self.downloadService.prevDownloadClosure = {[weak self] id in
            guard let wself = self else {
                return
            }
            
            //対象を探す
            let index = wself.searchTarget(id: id)
            
            //進捗を更新する
            if wself.downloadList[index].state == .Waiting {
                wself.downloadList[index].state = .Progressing
                wself.tableView.reloadData()
            }
        }
        
        self.downloadList.append(TableViewCellData(id: 1, title: "テスト01", url: "http://ipv4.download.thinkbroadband.com/10MB.zip", progress: 0.0, state: .Waiting))
        self.downloadList.append(TableViewCellData(id: 2, title: "テスト02", url: "http://ipv4.download.thinkbroadband.com/200MB.zip", progress: 0.0, state: .Waiting))
        self.downloadList.append(TableViewCellData(id: 3, title: "テスト03", url: "http://ipv4.download.thinkbroadband.com/200MB.zip", progress: 0.0, state: .Waiting))
        
        self.tableView.contentInset = UIEdgeInsets.init(top: 20.0, left: 0.0, bottom: 0.0, right: 0.0)
        self.tableView.tableFooterView = UIView()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.downloadList.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60.0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: ViewController.tableCellIdentifier) else {
            return UITableViewCell(frame: CGRect(x: 0.0, y: 0.0, width: UIScreen.main.bounds.size.width, height: 60.0))
        }
        
        (cell as! TableViewCell).setData(data: self.downloadList[indexPath.row])
        (cell as! TableViewCell).tappedClosure = {[weak self](id) -> Void in
            guard let wself = self else {
                return
            }
            
            //対象を探す
            let index = wself.searchTarget(id: id)
            
            //待機中からダウンロード中に更新
            if wself.downloadList[index].state == .Waiting {
                wself.downloadService.addDownload(id: id, url: wself.downloadList[index].url!)
                wself.downloadList[index].state = .Progressing
                wself.tableView.reloadData()
            //進行中から一時停止に更新
            }else if wself.downloadList[index].state == .Progressing {
                if wself.downloadService.pauseDownload(id: id) {
                    wself.downloadList[index].state = .Pausing
                    wself.tableView.reloadData()
                }
            //一時停止から進行中に更新
            }else if wself.downloadList[index].state == .Pausing {
                wself.downloadService.resumeDownload(id: id, url: wself.downloadList[index].url!)
                wself.downloadList[index].state = .Progressing
                wself.tableView.reloadData()
            }
        }
        
        return cell
    }
    
    private func searchTarget(id : Int) -> Int {
        //対象を探す
        var index = -1
        for i in 0 ..< self.downloadList.count {
            if self.downloadList[i].id == id {
                index = i
                break
            }
        }
        
        return index
    }
}

