import Foundation
import AppKit

final class HelperManager: ObservableObject {
    static let shared = HelperManager()
    
    @Published var isInstalled: Bool = false
    @Published var isInstalling: Bool = false
    
    private init() {
        checkStatus()
    }
    
    func checkStatus() {
        guard let url = URL(string: "http://127.0.0.1:9099/processes") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        
        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                self.isInstalled = (error == nil && data != nil)
            }
        }
        task.resume()
    }
    
    func installHelper(completion: @escaping (Bool, String?) -> Void) {
        DispatchQueue.main.async { self.isInstalling = true }
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let helperSourceURL = Bundle.main.url(forResource: "MacCleanerDaemon", withExtension: "swift") else {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    completion(false, "Could not find MacCleanerDaemon.swift in bundle.")
                }
                return
            }
            
            let tempSource = FileManager.default.temporaryDirectory.appendingPathComponent("MacCleanerDaemon.swift")
            let tempBin = FileManager.default.temporaryDirectory.appendingPathComponent("MacCleanerDaemon")
            
            do {
                if FileManager.default.fileExists(atPath: tempSource.path) {
                    try FileManager.default.removeItem(at: tempSource)
                }
                try FileManager.default.copyItem(at: helperSourceURL, to: tempSource)
                
                let compileTask = Process()
                compileTask.launchPath = "/usr/bin/swiftc"
                compileTask.arguments = [tempSource.path, "-o", tempBin.path]
                compileTask.launch()
                compileTask.waitUntilExit()
                
                if compileTask.terminationStatus != 0 {
                    DispatchQueue.main.async {
                        self.isInstalling = false
                        completion(false, "Failed to compile the daemon.")
                    }
                    return
                }
                
                let plistStr = """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0">
                <dict>
                    <key>Label</key>
                    <string>com.maccleaner.daemon</string>
                    <key>ProgramArguments</key>
                    <array>
                        <string>/Library/PrivilegedHelperTools/com.maccleaner.daemon</string>
                    </array>
                    <key>RunAtLoad</key>
                    <true/>
                    <key>KeepAlive</key>
                    <true/>
                </dict>
                </plist>
                """
                
                let tempPlist = FileManager.default.temporaryDirectory.appendingPathComponent("com.maccleaner.daemon.plist")
                try plistStr.write(to: tempPlist, atomically: true, encoding: .utf8)
                
                let script = """
                do shell script "mkdir -p /Library/PrivilegedHelperTools && cp \\"\\(tempBin.path)\\" /Library/PrivilegedHelperTools/com.maccleaner.daemon && chmod 755 /Library/PrivilegedHelperTools/com.maccleaner.daemon && cp \\"\\(tempPlist.path)\\" /Library/LaunchDaemons/com.maccleaner.daemon.plist && chmod 644 /Library/LaunchDaemons/com.maccleaner.daemon.plist && launchctl unload /Library/LaunchDaemons/com.maccleaner.daemon.plist 2>/dev/null; launchctl load -w /Library/LaunchDaemons/com.maccleaner.daemon.plist" with administrator privileges
                """
                
                let osaTask = Process()
                osaTask.launchPath = "/usr/bin/osascript"
                osaTask.arguments = ["-e", script]
                osaTask.launch()
                osaTask.waitUntilExit()
                
                DispatchQueue.main.async {
                    self.isInstalling = false
                    if osaTask.terminationStatus == 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            self.checkStatus()
                            completion(true, nil)
                        }
                    } else {
                        completion(false, "Administrator prompt cancelled or failed.")
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    completion(false, error.localizedDescription)
                }
            }
        }
    }
}
