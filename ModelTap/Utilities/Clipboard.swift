import AppKit

@MainActor
enum Clipboard {
    private static let concealedType = NSPasteboard.PasteboardType(
        "org.nspasteboard.ConcealedType"
    )
    private static let transientType = NSPasteboard.PasteboardType(
        "org.nspasteboard.TransientType"
    )
    private static var clearTask: Task<Void, Never>?

    static func copy(_ text: String, sensitive: Bool = false) {
        clearTask?.cancel()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if sensitive {
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            item.setData(Data(), forType: concealedType)
            item.setData(Data(), forType: transientType)
            pasteboard.writeObjects([item])
            scheduleClear(changeCount: pasteboard.changeCount)
        } else {
            pasteboard.setString(text, forType: .string)
        }
    }

    private static func scheduleClear(changeCount: Int) {
        clearTask = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled,
                  NSPasteboard.general.changeCount == changeCount else {
                return
            }
            NSPasteboard.general.clearContents()
        }
    }
}
