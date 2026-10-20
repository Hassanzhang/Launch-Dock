import AppKit
import SwiftUI

@main
struct LaunchDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    @StateObject private var updates = OnlineUpdateController()
    var body: some Scene {
        Window("LaunchDock", id: "main") {
            ContentView(model: model, runner: model.runner)
                .frame(minWidth: 980, minHeight: 600)
                .background(WindowReader { window in
                    window.isReleasedWhenClosed = false
                    delegate.window = window
                    delegate.model = model
                })
        }
        .defaultSize(width: 1100, height: 750)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("检查更新…") { updates.checkForUpdates(model: model) }
                    .disabled(model.busy)
            }
            CommandGroup(replacing: .newItem) {
                Button("添加项目…") { model.edit(nil) }
                    .keyboardShortcut("n")
                    .disabled(model.loadFailed || model.busy)
            }
        }
    }
}

private struct WindowReader: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView { WindowProbe(onWindow: onWindow) }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowProbe: NSView {
    let onWindow: (NSWindow) -> Void
    init(onWindow: @escaping (NSWindow) -> Void) {
        self.onWindow = onWindow
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { onWindow(window) }
    }
}
