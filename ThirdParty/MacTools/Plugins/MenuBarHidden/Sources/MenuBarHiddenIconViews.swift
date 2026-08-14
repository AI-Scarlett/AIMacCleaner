import AppKit
import SwiftUI
import MacToolsPluginKit

// MARK: - MenuBarHiddenIconView

/// Displays the captured screenshot for a menu bar item.
struct MenuBarHiddenIconView: View {
    let item: MenuBarItem
    let size: CGFloat
    @ObservedObject var iconCache: MenuBarHiddenIconCache

    var body: some View {
        Group {
            if let image = iconCache.image(for: item.tag)?.nsImage {
                Image(nsImage: image)
                    .interpolation(.high)
                    .antialiased(true)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .help(item.displayName)
    }
}
