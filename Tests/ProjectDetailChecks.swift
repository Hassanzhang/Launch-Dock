import AppKit
import SwiftUI
import LaunchDockCore

@main
struct ProjectDetailChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        guard ProcessInfo.processInfo.environment["LAUNCHDOCK_CONFIG_PATH"] != nil else {
            print("Run scripts/check-project-detail.sh to isolate configuration"); exit(1)
        }
        let model = AppModel()
        let directory = "/tmp/" + String(repeating: "very-long-project-directory/", count: 10)
        let frontend = Service(role: .frontend, workingDirectory: directory + "/frontend", command: "npm run dev")
        let backend = Service(role: .backend, workingDirectory: directory, command: "python app.py")
        let project = Project(name: "布局检查", directory: directory, services: [frontend, backend])
        let host = NSHostingView(rootView: ProjectDetail(project: project, model: model, runner: model.runner, delete: {}))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        var failures = 0
        func expect(_ condition: Bool, _ label: String) {
            if !condition { failures += 1; print("FAIL: " + label) }
        }
        func findLog(_ view: NSView) -> LogScrollView? {
            if let log = view as? LogScrollView { return log }
            for child in view.subviews { if let log = findLog(child) { return log } }
            return nil
        }
        for size in [NSSize(width: 640, height: 600), NSSize(width: 1000, height: 900), NSSize(width: 500, height: 800)] {
            window.setContentSize(size)
            host.frame.size = size
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            host.layoutSubtreeIfNeeded()
            guard let log = findLog(host) else { print("FAIL: missing native log view"); exit(1) }
            let rect = log.convert(log.bounds, to: host)
            let top = host.isFlipped ? rect.minY : host.bounds.height - rect.maxY
            let bottom = host.isFlipped ? host.bounds.height - rect.maxY : rect.minY
            expect(abs(rect.minX - 20) < 1, "original 20pt left page margin")
            expect(abs(host.bounds.width - rect.maxX - 20) < 1, "original 20pt right page margin")
            expect(abs(bottom - 20) < 1, "log fills remaining height to the original bottom margin")
            let stacked = size.width < 592
            expect(top < (stacked ? 480 : 320), "content-height card region has no elastic blank area")
            expect(rect.height > 250, "log keeps useful viewport height")
            print("Checked detail \(Int(size.width))x\(Int(size.height)): log top=\(top), height=\(rect.height), bottom=\(bottom)")
        }
        for (state, title) in [
            (ServiceState.stopped, "已停止"), (.running, "运行中"),
            (.starting, "正在启动"), (.failed, "启动失败"), (.stopping, "正在停止")
        ] {
            let status = ServiceStatusPresentation(state: state)
            expect(status.title == title, "independent service status: " + title)
            let color = NSColor(status.color).usingColorSpace(.deviceRGB)!
            let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
            switch state {
            case .stopped: expect(max(r, g, b) - min(r, g, b) < 0.12, "stopped is gray")
            case .starting, .stopping: expect(r > 0.7 && g > 0.45 && b < 0.4, "transition is yellow")
            case .running: expect(g > r * 1.5 && g > b * 1.2, "running is green")
            case .failed: expect(r > g * 1.5 && r > b * 1.5, "failure is red")
            }
        }
        window.close()
        guard failures == 0 else { print("FAIL \(failures) detail checks"); exit(1) }
        print("PASS actual SwiftUI detail layout: original cards/toolbar, compact spacing, flexible log, long paths, narrow stacking and independent front/back status mapping")
    }
}
