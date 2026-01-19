//
//  Item.swift
//  ticca
//
//  Created by lss on 2025/11/15.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
