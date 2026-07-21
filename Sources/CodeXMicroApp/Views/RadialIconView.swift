import SwiftUI

struct RadialIconView: View {
    let value: String
    let size: CGFloat
    var systemColor: Color = .primary

    var body: some View {
        switch RadialIconReference(rawValue: value) {
        case let .system(symbol):
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(systemColor)
        case let .emoji(emoji):
            Text(emoji)
                .font(.system(size: size))
                .lineLimit(1)
        case let .local(filename):
            if let image = RadialCustomIconStore.image(for: .local(filename)) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
