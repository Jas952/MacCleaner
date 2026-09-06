import Foundation
import Security
import CryptoKit

enum FanHelperInstaller {
    static let helperIdentifier = "com.maccleaner.fanhelper"
    static let installedPath = "/Library/PrivilegedHelperTools/\(helperIdentifier)"
    static let configPath = installedPath + ".client.plist"
    static var bundledHelper: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/MacCleanerFanHelper")
    }

    /// Pin the actual code, not just a forgeable bundle identifier. Rebuilding
    /// an ad-hoc app intentionally requires administrator approval again.
    static func requirement(for url: URL) throws -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess else {
            throw InstallError("The app or helper signature is invalid. Rebuild and sign the app first.")
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any],
              let hash = values[kSecCodeInfoUnique as String] as? Data else {
            throw InstallError("Could not identify this build’s code signature.")
        }
        return "cdhash H\"\(hash.map { String(format: "%02x", $0) }.joined())\""
    }
    static var isCurrent: Bool {
        guard let config = NSDictionary(contentsOfFile: configPath),
              let expected = try? requirement(for: Bundle.main.bundleURL),
              config["Requirement"] as? String == expected,
              let bundled = try? Data(contentsOf: bundledHelper),
              let installed = try? Data(contentsOf: URL(fileURLWithPath: installedPath)) else { return false }
        return SHA256.hash(data: bundled) == SHA256.hash(data: installed)
    }
    private static func quote(_ value: String) -> String { "\u{27}" + value.replacingOccurrences(of: "\u{27}", with: "\u{27}\\\u{27}\u{27}") + "\u{27}" }

    static func install() -> Result<Void, Error> {
        do {
            let requirement = try requirement(for: Bundle.main.bundleURL)
            _ = try self.requirement(for: bundledHelper)
            let digest = SHA256.hash(data: try Data(contentsOf: bundledHelper)).map { String(format: "%02x", $0) }.joined()
            let config = try PropertyListSerialization.data(fromPropertyList: ["Requirement": requirement], format: .xml, options: 0).base64EncodedString()
            let daemon: [String: Any] = [
                "Label": helperIdentifier, "ProgramArguments": [installedPath],
                "MachServices": [helperIdentifier: true], "RunAtLoad": true,
                "KeepAlive": true, "ThrottleInterval": 5, "ExitTimeOut": 20
            ]
            let plist = try PropertyListSerialization.data(fromPropertyList: daemon, format: .xml, options: 0).base64EncodedString()
            // Only fixed root-owned destinations. Stage and verify the helper
            // before stopping the old service; never execute a writable source.
            let command = """
            set -eu
            /usr/bin/install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools
            stage=$(/usr/bin/mktemp -d /Library/PrivilegedHelperTools/.maccleaner-fan.XXXXXX)
            trap \u{27}/bin/rm -rf "$stage"\u{27} EXIT
            /bin/cp \(quote(bundledHelper.path)) "$stage/helper"
            actual=$(/usr/bin/shasum -a 256 "$stage/helper")
            test "${actual%% *}" = \(quote(digest))
            /usr/bin/codesign --verify --strict "$stage/helper"
            /usr/bin/printf %s \(quote(config)) | /usr/bin/base64 -D > "$stage/client.plist"
            /usr/bin/printf %s \(quote(plist)) | /usr/bin/base64 -D > "$stage/daemon.plist"
            /usr/sbin/chown root:wheel "$stage/helper" "$stage/client.plist" "$stage/daemon.plist"
            /bin/chmod 755 "$stage/helper"
            /bin/chmod 644 "$stage/client.plist" "$stage/daemon.plist"
            /bin/launchctl bootout system/\(helperIdentifier) 2>/dev/null || true
            /bin/mv -f "$stage/helper" \(quote(installedPath))
            /bin/mv -f "$stage/client.plist" \(quote(configPath))
            /bin/mv -f "$stage/daemon.plist" /Library/LaunchDaemons/\(helperIdentifier).plist
            /bin/launchctl bootstrap system /Library/LaunchDaemons/\(helperIdentifier).plist
            """
            let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
            let output = Pipe(); process.standardError = output; process.standardOutput = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw InstallError(String(data: data, encoding: .utf8) ?? "Administrator approval was cancelled.")
            }
            return .success(())
        } catch { return .failure(error) }
    }
    struct InstallError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
