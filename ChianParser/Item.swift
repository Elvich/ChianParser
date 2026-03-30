//
//  Item.swift
//  ChianParser
//
//  Created by Maksim on 30.03.2026.
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
