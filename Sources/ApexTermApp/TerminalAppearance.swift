import AppKit
import SwiftUI

struct TerminalAppearance: Equatable {
    static let defaultInputColorHex = "#A7D7FF"
    static let defaultOutputColorHex = "#E6E8EB"

    static var persisted: TerminalAppearance {
        TerminalAppearance(
            inputColorHex: UserDefaults.standard.string(
                forKey: "apexterm.terminal.inputColor"
            ) ?? defaultInputColorHex,
            outputColorHex: UserDefaults.standard.string(
                forKey: "apexterm.terminal.outputColor"
            ) ?? defaultOutputColorHex
        )
    }

    var inputColorHex: String
    var outputColorHex: String

    var inputNSColor: NSColor {
        NSColor(apexHex: inputColorHex)
            ?? NSColor(calibratedRed: 0.655, green: 0.843, blue: 1, alpha: 1)
    }

    var outputNSColor: NSColor {
        NSColor(apexHex: outputColorHex)
            ?? NSColor(calibratedWhite: 0.90, alpha: 1)
    }

    var inputColor: Color {
        Color(nsColor: inputNSColor)
    }

    var outputColor: Color {
        Color(nsColor: outputNSColor)
    }

    var inputANSI: String {
        inputNSColor.apexForegroundANSI
    }

    var outputANSI: String {
        outputNSColor.apexForegroundANSI
    }
}

extension NSColor {
    convenience init?(apexHex value: String) {
        let hex = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard hex.count == 6, let raw = UInt64(hex, radix: 16) else { return nil }
        self.init(
            calibratedRed: CGFloat((raw >> 16) & 0xFF) / 255,
            green: CGFloat((raw >> 8) & 0xFF) / 255,
            blue: CGFloat(raw & 0xFF) / 255,
            alpha: 1
        )
    }

    var apexHex: String {
        guard let rgb = usingColorSpace(.deviceRGB) else {
            return TerminalAppearance.defaultOutputColorHex
        }
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
    }

    var apexForegroundANSI: String {
        guard let rgb = usingColorSpace(.deviceRGB) else { return "\u{001B}[39m" }
        let red = Int((rgb.redComponent * 255).rounded())
        let green = Int((rgb.greenComponent * 255).rounded())
        let blue = Int((rgb.blueComponent * 255).rounded())
        return "\u{001B}[38;2;\(red);\(green);\(blue)m"
    }
}
