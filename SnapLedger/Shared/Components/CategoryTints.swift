import SwiftUI

struct CategoryTints {
    init(names: [String]) {}

    func tint(for categoryName: String) -> Color {
        Self.tint(for: Self.key(for: categoryName))
    }

    private static func tint(for key: String) -> Color {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let hue = Double(hash % 360) / 360
        return Color(hue: hue, saturation: 0.58, brightness: 0.78)
    }

    private static func key(for name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
    }
}
