//
//  Item.swift
//  DualCast
//
//  Created by Scotty on 3/26/26.
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
