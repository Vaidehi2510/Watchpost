#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Thin UIKit / AppKit layer for the few things SwiftUI doesn't cover directly.
@MainActor
enum PlatformBridge {
    static func copyToPasteboard(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }

    static func notifySuccess() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}
