import AppKit

@main
struct LogOutputChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let view = LogScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        let frontend = UUID(), backend = UUID()
        var failures = 0
        func expect(_ condition: Bool, _ label: String) {
            if !condition { failures += 1; print("FAIL: " + label) }
        }
        func show(_ text: String, id: UUID? = nil, follow: Bool = false) {
            view.display(text: text, serviceID: id ?? frontend, following: follow)
            view.layoutSubtreeIfNeeded()
        }
        show("")
        expect(view.output.string == "本次运行暂无日志", "empty placeholder")
        expect(view.output.isFlipped, "document origin starts at the top")
        expect(view.output.textContainerOrigin == NSPoint(x: 16, y: 12), "16 x 12 text insets")
        expect(view.contentView.bounds.origin == .zero, "empty content at top-left")
        expect(view.output.frame.width >= view.contentView.bounds.width, "document fills viewport width")
        let multi = "first line\n    indented\tcolumn\n\nlast line\n"
        show(multi)
        expect(view.output.string == multi, "whitespace and newlines are unchanged")
        let attributes = view.output.textStorage!.attributes(at: 0, effectiveRange: nil)
        let font = attributes[.font] as! NSFont
        let paragraph = attributes[.paragraphStyle] as! NSParagraphStyle
        expect(font.pointSize == 12, "12pt font")
        expect(abs(paragraph.minimumLineHeight - 19.2) < 0.01 && abs(paragraph.maximumLineHeight - 19.2) < 0.01, "exact 1.6 line height")
        expect((attributes[.foregroundColor] as? NSColor) == NSColor.textColor, "system primary text color")
        expect(!NSFontManager.shared.traits(of: font).contains(.boldFontMask), "regular font weight")
        let multilineManager = view.output.layoutManager!
        multilineManager.ensureLayout(for: view.output.textContainer!)
        let firstLine = multilineManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let secondLine = multilineManager.lineFragmentRect(forGlyphAt: 11, effectiveRange: nil)
        expect(abs(secondLine.minY - firstLine.minY - 19.2) < 0.01, "measured native line spacing is 19.2pt")
        let longLine = String(repeating: "0123456789", count: 300)
        show(longLine)
        expect(view.output.frame.width > view.contentView.bounds.width, "long line scrolls horizontally")
        let manager = view.output.layoutManager!, container = view.output.textContainer!
        manager.ensureLayout(for: container)
        var lines = 0
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { _, _, _, _, _ in lines += 1 }
        expect(lines == 1, "long line is not wrapped")
        expect(view.output.frame.height <= view.contentView.bounds.height + 1, "long line does not increase panel height")
        let many = (0..<2000).map { "line \($0)    \(longLine.prefix(80))" }.joined(separator: "\n")
        show(many)
        expect(view.output.frame.height > view.contentView.bounds.height, "long document scrolls vertically")
        view.contentView.scroll(to: NSPoint(x: 80, y: 160))
        view.reflectScrolledClipView(view.contentView)
        let paused = view.contentView.bounds.origin
        show(many + "\ncontinuous output")
        expect(view.contentView.bounds.origin == paused, "paused updates preserve both scroll coordinates")
        for i in 0..<20 { show(many + "\n" + String(repeating: "stream \(i)\n", count: i + 1), follow: true) }
        let maximumY = view.output.frame.height - view.contentView.bounds.height
        expect(abs(view.contentView.bounds.minY - maximumY) < 1, "following reaches the bottom")
        expect(abs(view.contentView.bounds.minX - paused.x) < 1, "following preserves horizontal scroll")
        show(many, follow: false)
        let position = view.contentView.bounds.origin
        show(many + "\npaused again", follow: false)
        expect(view.contentView.bounds.origin == position, "disabling follow does not jump")
        show("backend output\n", id: backend)
        expect(view.output.string == "backend output\n", "service switch displays corresponding text")
        expect(view.contentView.bounds.origin == .zero, "paused service switch starts at top-left")
        show(longLine + "\n" + many, follow: true)
        view.setFrameSize(NSSize(width: 420, height: 240))
        view.tile(); view.needsLayout = true; view.layoutSubtreeIfNeeded()
        expect(view.output.string == longLine + "\n" + many, "resize preserves terminal text")
        expect(view.output.frame.width > view.contentView.bounds.width, "narrow resize keeps horizontal overflow")
        expect(abs(view.contentView.bounds.maxY - view.output.frame.height) < 1, "resize retains follow at bottom")
        view.setFrameSize(NSSize(width: 1000, height: 600))
        view.tile(); view.needsLayout = true; view.layoutSubtreeIfNeeded()
        expect(view.output.frame.width >= view.contentView.bounds.width, "wide resize still fills viewport")
        show("")
        expect(view.contentView.bounds.origin == .zero, "clearing restores top-left")
        guard failures == 0 else { print("FAIL \(failures) log layout checks"); exit(1) }
        print("PASS native AppKit log layout: empty, multiline, whitespace, font, contrast, long line, 2000 lines, continuous output, follow/pause, service switch, clear and resize")
    }
}
