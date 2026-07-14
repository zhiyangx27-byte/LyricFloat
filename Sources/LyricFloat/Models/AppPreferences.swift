import AppKit
import Combine
import Foundation
import SwiftUI

enum LyricsTextAlignment: String, CaseIterable, Identifiable {
    case leading
    case center
    case trailing

    var id: String { rawValue }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var label: String {
        switch self {
        case .leading: L10n.text("左对齐")
        case .center: L10n.text("居中")
        case .trailing: L10n.text("右对齐")
        }
    }
}

enum LyricsDisplayMode: String, CaseIterable, Identifiable {
    case currentLine
    case surroundingLines

    var id: String { rawValue }

    var label: String {
        switch self {
        case .currentLine: L10n.text("仅当前句")
        case .surroundingLines: L10n.text("当前句与前后句")
        }
    }
}

enum GlobalHotKeyLetter: String, CaseIterable, Identifiable {
    case a, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

enum LyricsColorPreset: String, CaseIterable, Identifiable {
    case white = "#FFFFFF"
    case warmWhite = "#FFF2D6"
    case yellow = "#FFD60A"
    case orange = "#FF9F0A"
    case coral = "#FF6961"
    case pink = "#FF65AD"
    case violet = "#BF5AF2"
    case cyan = "#64D2FF"
    case mint = "#63E6BE"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .white: L10n.text("纯白")
        case .warmWhite: L10n.text("暖白")
        case .yellow: L10n.text("亮黄")
        case .orange: L10n.text("橙色")
        case .coral: L10n.text("珊瑚红")
        case .pink: L10n.text("粉色")
        case .violet: L10n.text("紫色")
        case .cyan: L10n.text("青蓝")
        case .mint: L10n.text("薄荷绿")
        }
    }
}

@MainActor
enum LyricsFontCatalog {
    static let systemFamily = ""
    static let systemDisplayName = L10n.text("系统默认（圆体）")

    static let availableFamilies: [String] = {
        NSFontManager.shared.availableFontFamilies
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }()

    static func resolvedFamily(
        _ requestedFamily: String,
        availableFamilies: [String]? = nil
    ) -> String {
        let requestedFamily = requestedFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestedFamily.isEmpty else { return systemFamily }

        let families = availableFamilies ?? self.availableFamilies
        return families.first {
            $0.caseInsensitiveCompare(requestedFamily) == .orderedSame
        } ?? systemFamily
    }

    static func font(family: String, size: CGFloat, weight: Font.Weight) -> Font {
        let family = resolvedFamily(family)
        guard !family.isEmpty else {
            return .system(size: size, weight: weight, design: .rounded)
        }
        return .custom(family, size: size).weight(weight)
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    private let defaults: UserDefaults
    var onWindowingChange: (() -> Void)?
    var onHotKeyChange: (() -> Void)?

    @Published var overlayVisible: Bool { didSet { persist("overlayVisible", overlayVisible) } }
    @Published var locked: Bool { didSet { persist("locked", locked) } }
    @Published var allSpaces: Bool { didSet { persist("allSpaces", allSpaces) } }
    @Published var autoShow: Bool { didSet { persist("autoShow", autoShow) } }
    @Published var fontFamily: String { didSet { persist("fontFamily", fontFamily) } }
    @Published var fontSize: Double { didSet { persist("fontSize", fontSize) } }
    @Published var lineSpacing: Double { didSet { persist("lineSpacing", lineSpacing) } }
    @Published var backgroundOpacity: Double { didSet { persist("backgroundOpacity", backgroundOpacity) } }
    @Published var inactiveOpacity: Double { didSet { persist("inactiveOpacity", inactiveOpacity) } }
    @Published var activeColorHex: String { didSet { persist("activeColorHex", activeColorHex) } }
    @Published var inactiveColorHex: String { didSet { persist("inactiveColorHex", inactiveColorHex) } }
    @Published var alignmentRaw: String { didSet { persist("alignmentRaw", alignmentRaw) } }
    @Published var displayModeRaw: String { didSet { persist("displayModeRaw", displayModeRaw) } }
    @Published var useShadow: Bool { didSet { persist("useShadow", useShadow) } }
    @Published var showBackground: Bool { didSet { persist("showBackground", showBackground) } }
    @Published var hotKeyLetterRaw: String { didSet { persist("hotKeyLetterRaw", hotKeyLetterRaw) } }
    @Published var hotKeyUsesControl: Bool { didSet { persist("hotKeyUsesControl", hotKeyUsesControl) } }
    @Published var hotKeyUsesOption: Bool { didSet { persist("hotKeyUsesOption", hotKeyUsesOption) } }
    @Published var hotKeyUsesShift: Bool { didSet { persist("hotKeyUsesShift", hotKeyUsesShift) } }
    @Published var hotKeyUsesCommand: Bool { didSet { persist("hotKeyUsesCommand", hotKeyUsesCommand) } }

    var alignment: LyricsTextAlignment {
        get { LyricsTextAlignment(rawValue: alignmentRaw) ?? .center }
        set { alignmentRaw = newValue.rawValue }
    }

    var displayMode: LyricsDisplayMode {
        get { LyricsDisplayMode(rawValue: displayModeRaw) ?? .surroundingLines }
        set { displayModeRaw = newValue.rawValue }
    }

    var hotKeyLetter: GlobalHotKeyLetter {
        get { GlobalHotKeyLetter(rawValue: hotKeyLetterRaw) ?? .l }
        set { hotKeyLetterRaw = newValue.rawValue }
    }

    var isHotKeyValid: Bool {
        hotKeyUsesControl || hotKeyUsesOption || hotKeyUsesShift || hotKeyUsesCommand
    }

    var hotKeyShortcutLabel: String {
        let modifiers = [
            hotKeyUsesControl ? "⌃" : "",
            hotKeyUsesOption ? "⌥" : "",
            hotKeyUsesShift ? "⇧" : "",
            hotKeyUsesCommand ? "⌘" : ""
        ].joined()
        return modifiers + hotKeyLetter.label
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "overlayVisible": true,
            "locked": false,
            "allSpaces": true,
            "autoShow": true,
            "fontFamily": LyricsFontCatalog.systemFamily,
            "fontSize": 30.0,
            "lineSpacing": 12.0,
            "backgroundOpacity": 0.38,
            "inactiveOpacity": 0.34,
            "activeColorHex": "#FFFFFF",
            "inactiveColorHex": "#FFFFFF",
            "alignmentRaw": LyricsTextAlignment.center.rawValue,
            "displayModeRaw": LyricsDisplayMode.surroundingLines.rawValue,
            "useShadow": true,
            "showBackground": false,
            "hotKeyLetterRaw": GlobalHotKeyLetter.l.rawValue,
            "hotKeyUsesControl": true,
            "hotKeyUsesOption": true,
            "hotKeyUsesShift": false,
            "hotKeyUsesCommand": true
        ])

        if !defaults.bool(forKey: "didEnableFollowCurrentDesktop") {
            defaults.set(true, forKey: "allSpaces")
            defaults.set(true, forKey: "didEnableFollowCurrentDesktop")
        }
        if !defaults.bool(forKey: "didDisableOverlayDecoration") {
            defaults.set(false, forKey: "showBackground")
            defaults.set(true, forKey: "didDisableOverlayDecoration")
        }

        overlayVisible = defaults.bool(forKey: "overlayVisible")
        locked = defaults.bool(forKey: "locked")
        allSpaces = defaults.bool(forKey: "allSpaces")
        autoShow = defaults.bool(forKey: "autoShow")
        let requestedFontFamily = defaults.string(forKey: "fontFamily") ?? LyricsFontCatalog.systemFamily
        fontFamily = LyricsFontCatalog.resolvedFamily(requestedFontFamily)
        fontSize = defaults.double(forKey: "fontSize")
        lineSpacing = defaults.double(forKey: "lineSpacing")
        backgroundOpacity = defaults.double(forKey: "backgroundOpacity")
        inactiveOpacity = defaults.double(forKey: "inactiveOpacity")
        activeColorHex = defaults.string(forKey: "activeColorHex") ?? "#FFFFFF"
        inactiveColorHex = defaults.string(forKey: "inactiveColorHex") ?? "#FFFFFF"
        alignmentRaw = defaults.string(forKey: "alignmentRaw") ?? LyricsTextAlignment.center.rawValue
        displayModeRaw = defaults.string(forKey: "displayModeRaw") ?? LyricsDisplayMode.surroundingLines.rawValue
        useShadow = defaults.bool(forKey: "useShadow")
        showBackground = defaults.bool(forKey: "showBackground")
        hotKeyLetterRaw = defaults.string(forKey: "hotKeyLetterRaw") ?? GlobalHotKeyLetter.l.rawValue
        hotKeyUsesControl = defaults.bool(forKey: "hotKeyUsesControl")
        hotKeyUsesOption = defaults.bool(forKey: "hotKeyUsesOption")
        hotKeyUsesShift = defaults.bool(forKey: "hotKeyUsesShift")
        hotKeyUsesCommand = defaults.bool(forKey: "hotKeyUsesCommand")

        if requestedFontFamily != fontFamily {
            defaults.set(fontFamily, forKey: "fontFamily")
        }
    }

    private func persist(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
        switch key {
        case "overlayVisible", "locked", "allSpaces":
            onWindowingChange?()
        case "hotKeyLetterRaw", "hotKeyUsesControl", "hotKeyUsesOption",
             "hotKeyUsesShift", "hotKeyUsesCommand":
            onHotKeyChange?()
        default:
            break
        }
    }
}

extension Color {
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex) ?? .white)
    }

    var hexRGB: String? {
        NSColor(self).hexRGB
    }

    static func lyricContrast(for hex: String) -> Color {
        guard let color = NSColor(hex: hex)?.usingColorSpace(.deviceRGB) else {
            return .black
        }
        let luminance = 0.2126 * color.redComponent
            + 0.7152 * color.greenComponent
            + 0.0722 * color.blueComponent
        return luminance > 0.52 ? .black : .white
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }

        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexRGB: String? {
        usingColorSpace(.deviceRGB).map {
            String(
                format: "#%02X%02X%02X",
                Int(round($0.redComponent * 255)),
                Int(round($0.greenComponent * 255)),
                Int(round($0.blueComponent * 255))
            )
        }
    }
}
