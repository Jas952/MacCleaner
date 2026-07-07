import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        Form {
            Section(header: Text("Menu Bar")) {
                Picker("RAM Display Format", selection: $settings.menuBarRAMFormat) {
                    ForEach(SettingsManager.RAMDisplayFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
            }
        }
        .padding()
        .frame(width: 300, height: 150)
    }
}
