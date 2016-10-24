//
//  TableViewCell.swift
//  backgroundDownload
//
//  Created by Edelweiss on 2016/10/20.
//  Copyright © 2016年 Edelweiss. All rights reserved.
//

import UIKit

/**
テーブルセルのデータ構造体
*/
public struct TableViewCellData {
    public var id : Int!
    public var title : String?
    public var url : String?
    public var progress : Float = 0.0
    public var state : DownloadState = .Waiting
}

public class TableViewCell: UITableViewCell {
    private static let percentFormat : String = "%d％"

    @IBOutlet private weak var titleLabel : UILabel!
    @IBOutlet private weak var progressView : UIProgressView!
    @IBOutlet private weak var progressLabel : UILabel!
    @IBOutlet private weak var performBtn : UIButton!

    private var id : Int!
    
    public var tappedClosure : ((Int) -> Void)?

    override public func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override public func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

    /**
    データをセットする
    */
    public func setData(data : TableViewCellData) {
        self.id = data.id
        self.titleLabel.text = data.title
        self.progressView.setProgress(data.progress, animated: false)
        self.progressLabel.text = String(format: TableViewCell.percentFormat, Int(ceilf(data.progress * 100.0)))
        self.performBtn.setTitle(data.state.toBtnTitle(), for: .normal)
        if data.state == .Completed {
            self.performBtn.isEnabled = false
        }else {
            self.performBtn.isEnabled = true
        }
    }

    /**
    進捗を更新する
    */
    public func updateProgress(val : Float) {
        self.progressView.progress = val
        self.progressLabel.text = String(format: TableViewCell.percentFormat, Int(ceilf(val * 100.0)))
    }
    
    public func receiveCompletedNotification(notification : Notification) {
        guard let userInfo = notification.userInfo else {
            return
        }
        
        let targetId = userInfo["id"] as! Int
        
        if targetId == self.id {
            self.performBtn.isEnabled = false
        }
    }
    
    @IBAction func tappedBtn(sender : UIButton) {
        if let tappedClosure = tappedClosure {
            tappedClosure(self.id)
        }
    }
}
