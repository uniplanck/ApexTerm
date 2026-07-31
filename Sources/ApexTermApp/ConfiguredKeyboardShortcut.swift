import ApexTermCore
import SwiftUI

private struct ApexKeyboardShortcutModifier: ViewModifier {
    let chord: ApexKeyChord?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let chord,
           let keyEquivalent = chord.swiftUIKeyEquivalent {
            content.keyboardShortcut(
                keyEquivalent,
                modifiers: chord.swiftUIEventModifiers
            )
        } else {
            content
        }
    }
}

extension View {
    func apexKeyboardShortcut(_ chord: ApexKeyChord?) -> some View {
        modifier(ApexKeyboardShortcutModifier(chord: chord))
    }
}

private extension ApexKeyChord {
    var swiftUIKeyEquivalent: KeyEquivalent? {
        guard !modifiers.contains(.function) else { return nil }
        switch key {
        case "return", "enter":
            return KeyEquivalent.return
        case "left":
            return KeyEquivalent.leftArrow
        case "right":
            return KeyEquivalent.rightArrow
        case "up":
            return KeyEquivalent.upArrow
        case "down":
            return KeyEquivalent.downArrow
        case "space":
            return KeyEquivalent.space
        case "tab":
            return KeyEquivalent.tab
        case "escape", "esc":
            return KeyEquivalent.escape
        case "backtick":
            return KeyEquivalent("`")
        default:
            guard key.count == 1,
                  let character = key.first else {
                return nil
            }
            return KeyEquivalent(character)
        }
    }

    var swiftUIEventModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        return result
    }
}
