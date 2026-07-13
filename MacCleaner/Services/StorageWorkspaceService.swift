import Combine
import Foundation

/// Owns Storage feature services independently from the currently visible tab.
/// Child services do not relay changes through this container, so background
/// scan progress does not invalidate the entire application root view.
@MainActor
final class StorageWorkspaceService: ObservableObject {
    @Published private(set) var isWorking = false

    let cleanupAdvisor = CleanupAdvisorService()
    let duplicateFinder = DuplicateFinderService()
    let similarPhotos = SimilarPhotoService()
    let cloudReclaim = CloudReclaimService()

    private var cancellables: Set<AnyCancellable> = []

    init() {
        let signals: [AnyPublisher<Void, Never>] = [
            cleanupAdvisor.$isScanning.map { _ in () }.eraseToAnyPublisher(),
            cleanupAdvisor.$isCleaning.map { _ in () }.eraseToAnyPublisher(),
            duplicateFinder.$isScanning.map { _ in () }.eraseToAnyPublisher(),
            duplicateFinder.$isCleaning.map { _ in () }.eraseToAnyPublisher(),
            similarPhotos.$isScanning.map { _ in () }.eraseToAnyPublisher(),
            similarPhotos.$isCleaning.map { _ in () }.eraseToAnyPublisher(),
            cloudReclaim.$isScanning.map { _ in () }.eraseToAnyPublisher(),
            cloudReclaim.$isEvicting.map { _ in () }.eraseToAnyPublisher()
        ]

        Publishers.MergeMany(signals)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refreshWorkingState() }
            .store(in: &cancellables)
    }

    private func refreshWorkingState() {
        isWorking = cleanupAdvisor.isScanning || cleanupAdvisor.isCleaning
            || duplicateFinder.isScanning || duplicateFinder.isCleaning
            || similarPhotos.isScanning || similarPhotos.isCleaning
            || cloudReclaim.isScanning || cloudReclaim.isEvicting
    }

    func resetForNavigation() {
        guard !isWorking else { return }
        cleanupAdvisor.resetForNavigation()
        duplicateFinder.resetForNavigation()
        similarPhotos.resetForNavigation()
        cloudReclaim.resetForNavigation()
    }
}
