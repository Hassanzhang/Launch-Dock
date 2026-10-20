import AppKit
import Darwin
import LaunchDockCore

@main
struct UpdateHelper {
    @MainActor static func main() async {
        let args = CommandLine.arguments
        guard args.count == 3, let parent = Int32(args[1]), parent > 1 else { return }
        let workspace = URL(fileURLWithPath: args[2])
        guard workspace.lastPathComponent.hasPrefix("LaunchDock-update-") else { return }
        let target = LocalUpdate.destination
        do {
            var exited = false
            for _ in 0..<600 {
                if kill(parent, 0) != 0 && errno == ESRCH { exited = true; break }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            guard exited else { throw DockError("Application did not quit\n应用未正常退出，更新已取消。") }
            guard !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL?.standardizedFileURL == target }) else {
                throw DockError("Another instance is running\n请退出安装目录中其他 LaunchDock 实例后重试。")
            }
            // install is synchronous; the run loop below waits for AppKit's launch completion.
            try LocalUpdate.install(workspace.appendingPathComponent("LaunchDock.app"), target: target) { url in
                var result: Result<NSRunningApplication, Error>?
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.createsNewApplicationInstance = true
                if let override = ProcessInfo.processInfo.environment["LAUNCHDOCK_CONFIG_PATH"] {
                    configuration.environment = ["LAUNCHDOCK_CONFIG_PATH": override]
                }
                NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
                    if let error { result = .failure(error) }
                    else if let app { result = .success(app) }
                    else { result = .failure(DockError("Launch failed\n系统未返回启动结果。")) }
                }
                let deadline = Date().addingTimeInterval(60)
                while result == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
                guard result != nil else { throw DockError("Launch timed out\n重新打开超时，将恢复原应用。") }
                _ = try result!.get()
            }
            try? FileManager.default.removeItem(at: workspace)
        } catch {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "安装更新失败"
            alert.informativeText = error.localizedDescription + "\n项目配置保持不变。可以重新打开原应用后重试。"
            alert.runModal()
            try? FileManager.default.removeItem(at: workspace)
        }
    }
}
