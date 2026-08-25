import Foundation
import Security
import ServiceManagement

enum FanHelperInstaller {
    static let helperIdentifier = "com.maccleaner.fanhelper"

    /// Installs the embedded helper using Apple's privileged-helper workflow.
    /// No shell, password capture, or hand-written LaunchDaemon is used.
    @discardableResult
    static func install() -> Result<Void, Error> {
        var authorization: AuthorizationRef?
        let createStatus = AuthorizationCreate(nil, nil, [], &authorization)
        guard createStatus == errAuthorizationSuccess, let authorization else {
            return .failure(InstallerError.authorizationFailed(createStatus))
        }
        defer { AuthorizationFree(authorization, []) }

        var unmanagedError: Unmanaged<CFError>?
        let blessed = SMJobBless(
            kSMDomainSystemLaunchd,
            helperIdentifier as CFString,
            authorization,
            &unmanagedError
        )
        if blessed { return .success(()) }
        let message = unmanagedError?.takeRetainedValue().localizedDescription ?? "SMJobBless failed."
        return .failure(InstallerError.blessFailed(message))
    }

    enum InstallerError: LocalizedError {
        case authorizationFailed(OSStatus)
        case blessFailed(String)

        var errorDescription: String? {
            switch self {
            case .authorizationFailed(let status):
                return "Administrator authorization failed (status \(status))."
            case .blessFailed(let message):
                return message
            }
        }
    }
}
