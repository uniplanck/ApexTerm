import Carbon.HIToolbox
import Foundation

@MainActor
final class SecureKeyboardEntryController {
    static let shared = SecureKeyboardEntryController()

    private var enabledByApexTerm = false

    private init() {}

    var isEnabled: Bool {
        IsSecureEventInputEnabled()
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        if enabled {
            guard !enabledByApexTerm else { return isEnabled }
            let status = EnableSecureEventInput()
            enabledByApexTerm = status == noErr
        } else if enabledByApexTerm {
            _ = DisableSecureEventInput()
            enabledByApexTerm = false
        }
        return isEnabled
    }

    func disableIfOwned() {
        guard enabledByApexTerm else { return }
        _ = DisableSecureEventInput()
        enabledByApexTerm = false
    }
}
