import SwiftUI

/// Render SGR colors as text attributes; terminal escape sequences never become executable content.
enum CollectorTerminalText {
    static func render(_ source: String) -> AttributedString {
        let regex = try? NSRegularExpression(pattern: "\u{001B}\\[[0-?]*[ -/]*[@-~]")
        let input = source as NSString
        let matches = regex?.matches(in: source, range: NSRange(location: 0, length: input.length)) ?? []
        var result = AttributedString()
        var color: Color = DS.Palette.hex("9fd4a0")
        var offset = 0
        func append(_ string: String) {
            var piece = AttributedString(string)
            piece.foregroundColor = color
            result.append(piece)
        }
        for match in matches {
            append(input.substring(with: NSRange(location: offset, length: match.range.location - offset)))
            let escape = input.substring(with: match.range)
            if escape.hasSuffix("m") {
                let codes = escape.dropFirst(2).dropLast().split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
                var index = 0
                while index < codes.count {
                    let code = codes[index]
                    if code == 0 || code == 39 { color = DS.Palette.hex("9fd4a0") }
                    else if (30...37).contains(code) { color = indexed(code - 30) }
                    else if (90...97).contains(code) { color = indexed(code - 90 + 8) }
                    else if code == 38, index + 2 < codes.count, codes[index + 1] == 5 {
                        color = indexed(codes[index + 2]); index += 2
                    } else if code == 38, index + 4 < codes.count, codes[index + 1] == 2 {
                        color = Color(.sRGB, red: component(codes[index + 2]), green: component(codes[index + 3]), blue: component(codes[index + 4]), opacity: 1)
                        index += 4
                    }
                    index += 1
                }
            }
            offset = NSMaxRange(match.range)
        }
        append(input.substring(from: offset))
        return result
    }
    private static func component(_ value: Int) -> Double { Double(min(255, max(0, value))) / 255 }
    private static func indexed(_ value: Int) -> Color {
        let palette = ["666666", "e06c6c", "6ec89a", "e0a84c", "6ea8dc", "b48ead", "6ec8c8", "d6d6d6", "909090", "ff9090", "8ee8ba", "ffd080", "9ac8fc", "d4aecd", "90e8e8", "eeeeee"]
        let index = min(255, max(0, value))
        if index < 16 { return DS.Palette.hex(palette[index]) }
        if index >= 232 {
            let gray = Double(8 + (index - 232) * 10) / 255
            return Color(.sRGB, red: gray, green: gray, blue: gray, opacity: 1)
        }
        let cube = index - 16
        let levels = [0, 95, 135, 175, 215, 255]
        return Color(.sRGB, red: component(levels[cube / 36]), green: component(levels[(cube / 6) % 6]), blue: component(levels[cube % 6]), opacity: 1)
    }
}
