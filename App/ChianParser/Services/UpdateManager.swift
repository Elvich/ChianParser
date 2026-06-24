import Combine
import Sparkle
import SwiftUI

// UpdateManager holds the Sparkle controller for the app's lifetime.
// Kept outside AppContainer because SPUStandardUpdaterController must be
// instantiated before the SwiftUI environment is built.
final class AppcastDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        return "https://flipping.elvi4.tech/api/v1/updates/appcast.xml"
    }
}

final class UpdateManager {
    let updaterController: SPUStandardUpdaterController
    private let updaterDelegate = AppcastDelegate()

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
    }
}

// Uses ObservableObject + Combine (not @Observable) because canCheckForUpdates
// is a KVO property on SPUUpdater — Combine's publisher(for:) is the correct bridge.
final class CheckForUpdatesViewModel: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    private var cancellable: AnyCancellable?

    init(updater: SPUUpdater) {
        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .assign(to: \.canCheckForUpdates, on: self)
    }
}

struct CheckForUpdatesView: View {
    @StateObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        _viewModel = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}
