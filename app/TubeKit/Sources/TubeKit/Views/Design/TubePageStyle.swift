import SwiftUI

enum TubePageLayout {
    static let horizontalPadding: CGFloat = 20
    static let settingsMaxWidth: CGFloat = 760

    static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? RegularShellLayout.cinemaBackground : Color(white: 0.96)
    }
}

private struct TubePageStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TubePageLayout.background(for: colorScheme).ignoresSafeArea())
    }
}

extension View {
    func tubePageStyle() -> some View {
        modifier(TubePageStyle())
    }

    func tubeSettingsFormStyle() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: TubePageLayout.settingsMaxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tubePageStyle()
    }
}
