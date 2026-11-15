import SwiftUI

struct CategoryIcon: View {
    let category: LedgerCategory?
    let tint: Color
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.14))
            Image(systemName: category?.symbolName ?? "tag.fill")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
