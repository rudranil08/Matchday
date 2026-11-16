import WidgetKit
import SwiftUI
import AppIntents

@main
struct MatchdayWidgets: WidgetBundle {
    init() { AppFont.registerAll() }

    var body: some Widget {
        TableWidget()
        FormWidget()
    }
}

// MARK: shared widget helpers

extension View {
    /// Palette for the current light / dark appearance.
    func widgetPalette(_ scheme: ColorScheme) -> Palette { scheme == .dark ? .dark : .light }
}
