import Foundation
import Combine
import SwiftUI

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    enum RAMDisplayFormat: String, CaseIterable, Identifiable {
        case percent = "Percent (e.g. 76%)"
        case values = "Values (e.g. 12GB/16GB)"
        
        var id: String { self.rawValue }
    }
    
    @AppStorage("menuBarRAMFormat") var menuBarRAMFormat: RAMDisplayFormat = .percent
    
    private init() {}
}
