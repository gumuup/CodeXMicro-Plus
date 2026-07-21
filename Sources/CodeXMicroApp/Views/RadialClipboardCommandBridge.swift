import AppKit
import SwiftUI

/// Keeps standard text-field copy/paste behavior intact while routing ⌘C/⌘V
/// from the radial settings canvas to its currently selected operation.
struct RadialClipboardCommandBridge: NSViewRepresentable {
    let onCopy: () -> Void
    let onPaste: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCopy: onCopy, onPaste: onPaste)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        context.coordinator.start()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onCopy = onCopy
        context.coordinator.onPaste = onPaste
        context.coordinator.hostView = nsView
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        weak var hostView: NSView?
        var onCopy: () -> Void
        var onPaste: () -> Void
        private var monitor: Any?

        init(onCopy: @escaping () -> Void, onPaste: @escaping () -> Void) {
            self.onCopy = onCopy
            self.onPaste = onPaste
        }

        func start() {
            stop()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      self.hostView?.window?.isKeyWindow == true,
                      Self.isCommandOnly(event),
                      !Self.isEditingText else { return event }

                switch event.charactersIgnoringModifiers?.lowercased() {
                case "c":
                    self.onCopy()
                    return nil
                case "v":
                    self.onPaste()
                    return nil
                default:
                    return event
                }
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private static func isCommandOnly(_ event: NSEvent) -> Bool {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return flags.contains(.command)
                && !flags.contains(.control)
                && !flags.contains(.option)
                && !flags.contains(.shift)
        }

        private static var isEditingText: Bool {
            guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
            return textView.isEditable || textView.isSelectable
        }
    }
}
