import AppKit
import SwiftUI

struct LogOutputView: NSViewRepresentable {
    let text: String
    let serviceID: UUID
    let following: Bool

    func makeNSView(context: Context) -> LogScrollView { LogScrollView() }
    func updateNSView(_ view: LogScrollView, context: Context) {
        view.display(text: text, serviceID: serviceID, following: following)
    }
}

/// Presentation only: the runner and its log buffer remain the source of truth.
final class LogScrollView: NSScrollView {
    let output = NSTextView(frame: .zero)
    private var displayedText: String?
    private var serviceID: UUID?
    private var following = true
    private var updatingLayout = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        output.isEditable = false
        output.isSelectable = true
        output.isRichText = false
        output.drawsBackground = false
        output.isHorizontallyResizable = true
        output.isVerticallyResizable = true
        output.minSize = .zero
        output.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        output.textContainerInset = NSSize(width: 16, height: 12)
        output.textContainer?.lineFragmentPadding = 0
        output.textContainer?.widthTracksTextView = false
        output.textContainer?.heightTracksTextView = false
        output.textContainer?.containerSize = output.maxSize
        output.setAccessibilityLabel("服务日志输出")
        documentView = output
    }
    required init?(coder: NSCoder) { nil }

    func display(text: String, serviceID: UUID, following: Bool) {
        let switched = self.serviceID != serviceID
        let origin = switched ? NSPoint.zero : contentView.bounds.origin
        self.serviceID = serviceID
        self.following = following
        if text != displayedText {
            let font = ["SFMono-Regular", "Menlo", "Monaco", "Consolas"]
                .compactMap { NSFont(name: $0, size: 12) }.first
                ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = 12 * 1.6
            paragraph.maximumLineHeight = 12 * 1.6
            paragraph.lineBreakMode = .byClipping
            paragraph.tabStops = []
            paragraph.defaultTabInterval = (" " as NSString).size(withAttributes: [.font: font]).width * 8
            output.textStorage?.setAttributedString(NSAttributedString(
                string: text.isEmpty ? "本次运行暂无日志" : text,
                attributes: [.font: font, .paragraphStyle: paragraph,
                             .foregroundColor: text.isEmpty ? NSColor.secondaryLabelColor : NSColor.textColor]
            ))
            displayedText = text
        }
        fitOutput(origin: origin)
    }

    override func layout() {
        super.layout()
        fitOutput(origin: contentView.bounds.origin)
    }
    private func fitOutput(origin: NSPoint) {
        guard !updatingLayout, let container = output.textContainer, let manager = output.layoutManager else { return }
        updatingLayout = true
        defer { updatingLayout = false }
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        let viewport = contentView.bounds.size
        let size = NSSize(width: max(viewport.width, ceil(used.maxX) + 32),
                          height: max(viewport.height, ceil(max(used.maxY, manager.extraLineFragmentRect.maxY)) + 24))
        if output.frame.size != size { output.setFrameSize(size) }
        let visible = contentView.bounds.size
        let maximumX = max(0, output.frame.width - visible.width)
        let maximumY = max(0, output.frame.height - visible.height)
        let target = NSPoint(x: min(max(0, origin.x), maximumX),
                             y: following ? maximumY : min(max(0, origin.y), maximumY))
        contentView.scroll(to: target)
        reflectScrolledClipView(contentView)
    }
}
