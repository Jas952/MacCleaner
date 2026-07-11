import Foundation
import Sparkle

@MainActor
final class UpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdateService()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case installed
        case failed(String)

        var footerText: String {
            switch self {
            case .available: return "Update available"
            case .checking: return "Checking for updates…"
            case .failed: return "Unable to check for updates"
            case .idle, .upToDate, .installed: return "No updates available"
            }
        }

        var detailText: String {
            switch self {
            case .idle: return "Updates are checked automatically."
            case .checking: return "Checking for updates…"
            case .upToDate: return "No updates available."
            case .available(let version): return "MacCleaner \(version) is available."
            case .installed: return "Update installed successfully."
            case .failed(let message): return message
            }
        }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var canCheckForUpdates = false

    private static let automaticUpdatesKey = "MacCleanerAutomaticUpdatesEnabled"
    private static let pendingVersionKey = "MacCleanerPendingUpdateVersion"
    private var updaterObservation: NSKeyValueObservation?

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    var automaticallyUpdates: Bool {
        get { UserDefaults.standard.object(forKey: Self.automaticUpdatesKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.automaticUpdatesKey)
            controller.updater.automaticallyChecksForUpdates = newValue
            controller.updater.automaticallyDownloadsUpdates = newValue
            objectWillChange.send()
        }
    }

    override private init() {
        super.init()
        let updater = controller.updater
        updater.automaticallyChecksForUpdates = automaticallyUpdates
        updater.automaticallyDownloadsUpdates = automaticallyUpdates
        updaterObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            Task { @MainActor in self?.canCheckForUpdates = updater.canCheckForUpdates }
        }

        if let pending = UserDefaults.standard.string(forKey: Self.pendingVersionKey),
           Self.compareVersions(currentVersion, pending) != .orderedAscending {
            status = .installed
            UserDefaults.standard.removeObject(forKey: Self.pendingVersionKey)
        }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    func checkForUpdates() {
        status = .checking
        controller.checkForUpdates(nil)
    }

    func checkInBackground() {
        guard automaticallyUpdates else { return }
        status = .checking
        controller.updater.checkForUpdatesInBackground()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        status = .available(version)
        UserDefaults.standard.set(version, forKey: Self.pendingVersionKey)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        status = .upToDate
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        status = .failed(error.localizedDescription)
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: .numeric)
    }
}
