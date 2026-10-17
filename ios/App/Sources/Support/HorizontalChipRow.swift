import SwiftUI

/// Horizontal chip row that keeps its proposed width and scrolls instead of clipping.
struct HorizontalChipRow<Content: View>: View {
    var minHeight: CGFloat
    private let content: Content

    init(minHeight: CGFloat = 44, @ViewBuilder content: () -> Content) {
        self.minHeight = minHeight
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
    }
}
