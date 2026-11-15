import SwiftUI

struct CategoryTints {
    private let paletteIndexByKey: [String: Int]

    init(names: [String]) {
        let keys = Set(names.map(Self.key(for:)))
            .filter { !$0.isEmpty }
            .sorted {
                let left = Self.stableHash($0)
                let right = Self.stableHash($1)
                return left == right ? $0 < $1 : left < right
            }

        var assignments: [String: Int] = [:]
        var occupied: Set<Int> = []

        for key in keys {
            let preferredIndex = Int(Self.stableHash(key) % UInt64(Self.palette.count))
            let availableIndex = (0..<Self.palette.count)
                .map { (preferredIndex + $0) % Self.palette.count }
                .first { !occupied.contains($0) }
                ?? preferredIndex
            assignments[key] = availableIndex
            occupied.insert(availableIndex)
        }

        paletteIndexByKey = assignments
    }

    func tint(for categoryName: String) -> Color {
        let key = Self.key(for: categoryName)
        let index = paletteIndexByKey[key]
            ?? Int(Self.stableHash(key) % UInt64(Self.palette.count))
        return Self.palette[index]
    }

    private static let palette: [Color] = [
        .blue,
        .orange,
        .green,
        .purple,
        .pink,
        .teal,
        .indigo,
        .brown,
        .cyan,
        .mint,
        .red,
        .yellow
    ]

    private static func stableHash(_ key: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
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
