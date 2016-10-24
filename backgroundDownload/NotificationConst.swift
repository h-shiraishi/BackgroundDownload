//
//  NotificationConst.swift
//  backgroundDownload
//
//  Created by Edelweiss on 2016/10/20.
//  Copyright © 2016年 Edelweiss. All rights reserved.
//

import UIKit

public enum NotificationConst : String {
    case DownloadProgress = "DownloadProgress"
    case DownloadCompleted = "DownloadCompleted"
    
    func toNotificationName() -> Notification.Name {
        return Notification.Name(self.rawValue)
    }
}
