//
//  Item.swift
//  TestEVM-2
//
//  Created by Hao Fu on 21/3/2024.
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
