#if os(iOS)
import Foundation
import MetagrafCore

@MainActor
@Observable
final class RefinementAvailabilityModel {
    enum State: Equatable {
        case checking
        case available
        case unavailable(String)
    }

    private(set) var state: State

    private let check: @Sendable (Locale) async -> RefinerAvailability
    private var requestID = UUID()

    init(
        state: State = .checking,
        check: @escaping @Sendable (Locale) async -> RefinerAvailability = { locale in
            await RefinerRegistry().languageModelAvailability(for: locale)
        }
    ) {
        self.state = state
        self.check = check
    }

    var allowsLanguageModel: Bool {
        state == .available
    }

    func refresh(settings: SettingsStore) async {
        let id = UUID()
        requestID = id
        let locale = settings.effectiveLocale
        state = .checking

        let availability = await check(locale)
        guard requestID == id, settings.effectiveLocale.identifier == locale.identifier else { return }

        switch availability {
        case .available:
            state = .available
        case .unavailable(let reason):
            state = .unavailable(reason)
            if settings.refinementStyle.needsLanguageModel {
                settings.refinementStyle = .raw
            }
        }
    }
}
#endif
