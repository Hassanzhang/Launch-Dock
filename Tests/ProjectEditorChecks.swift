import AppKit
import SwiftUI
import LaunchDockCore

@main
struct ProjectEditorChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        guard ProcessInfo.processInfo.environment["LAUNCHDOCK_CONFIG_PATH"] != nil else { fatalError("Use scripts/check-project-editor.sh") }
        let model = AppModel()
        var heights: [CGFloat] = []
        for count in 0...2 {
            let services = ServiceRole.allCases.prefix(count).map {
                Service(role: $0, workingDirectory: "/tmp", command: "python app.py")
            }
            let project = Project(name: "布局检查", directory: "/tmp", services: services)
            let host = NSHostingView(rootView: ProjectEditor(model: model, project: project))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 650), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            let size = host.fittingSize
            print("Editor with \(count) services: \(size.width)x\(size.height)")
            precondition(abs(size.width - 650) < 1, "editor width is stable")
            precondition(size.height >= 300 && size.height <= 750, "useful form height without clipping or excess space")
            heights.append(size.height)
            window.close()
        }
        precondition(heights[0] < heights[1] && heights[1] < heights[2], "sheet grows with actual expanded service content")
        print("PASS native SwiftUI editor sizing: collapsed, one service, two services")
    }
}
