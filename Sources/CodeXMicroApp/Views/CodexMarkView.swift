import AppKit
import SwiftUI

struct CodexMarkView: View {
    @Environment(\.microLayoutScale) private var layoutScale

    var body: some View {
        if let image = referenceImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: scaled(78), height: scaled(78))
        } else {
            fallbackMark
        }
    }

    private var referenceImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "CodexMarkReference", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    private var fallbackMark: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Circle()
                    .frame(width: scaled(31), height: scaled(31))
                    .offset(y: -scaled(13))
                    .rotationEffect(.degrees(Double(index) * 45))
            }
            Circle().frame(width: scaled(40), height: scaled(40))
            HStack(spacing: scaled(2)) {
                Image(systemName: "chevron.right")
                    .font(.system(size: scaled(22), weight: .heavy))
                Image(systemName: "minus")
                    .font(.system(size: scaled(20), weight: .heavy))
                    .offset(y: scaled(7))
            }
                .foregroundStyle(.white)
                .offset(x: scaled(1))
        }
        .foregroundStyle(
            LinearGradient(
                colors: [Color(red: 0.68, green: 0.45, blue: 1), Color(red: 0.19, green: 0.22, blue: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .shadow(color: .indigo.opacity(0.45), radius: scaled(8), y: scaled(4))
    }

    private func scaled(_ value: CGFloat) -> CGFloat { value * layoutScale }
}
