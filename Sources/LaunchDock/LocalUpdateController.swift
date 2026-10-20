import AppKit
import UniformTypeIdentifiers
import LaunchDockCore

extension AppModel {
    func installLocalUpdate() {
        guard !busy else { return }
        guard !runner.hasActiveServices else { error = "请先停止所有服务，再安装本地更新。"; return }
        let panel = NSOpenPanel()
        panel.title = "选择 LaunchDock 更新包"
        panel.allowedContentTypes = [.applicationBundle, UTType(filenameExtension: "dmg")!]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        busy = true
        preparingUpdate = true
        Task {
            var ownedWorkspace: URL?
            defer {
                busy = false
                preparingUpdate = false
                if let ownedWorkspace { try? FileManager.default.removeItem(at: ownedWorkspace) }
            }
            do {
                let current = try UpdateVersion(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0", build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0")
                let workspace = try await Task.detached { try LocalUpdate.prepare(source, current: current) }.value
                ownedWorkspace = workspace
                let next = try LocalUpdate.validate(workspace.appendingPathComponent("LaunchDock.app"), newerThan: current)
                let target = LocalUpdate.destination
                if FileManager.default.fileExists(atPath: target.path) {
                    guard next > (try LocalUpdate.validate(target)) else { throw DockError("安装目录已有相同或更新版本。") }
                }
                let probe = target.deletingLastPathComponent().appendingPathComponent(".LaunchDock-write-check-" + UUID().uuidString)
                try Data().write(to: probe, options: .withoutOverwriting)
                try FileManager.default.removeItem(at: probe)
                guard !runner.hasActiveServices else { throw DockError("请先停止所有服务，再安装本地更新。") }
                guard !NSWorkspace.shared.runningApplications.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && $0.bundleURL?.standardizedFileURL == target }) else {
                    throw DockError("请先退出安装目录中的其他 LaunchDock 实例。")
                }
                let alert = NSAlert()
                alert.messageText = "安装更新并重新打开？"
                alert.informativeText = "当前：\(current.version)（\(current.build)）\n更新：\(next.version)（\(next.build)）\n位置：\(target.path)\n应用将正常退出。项目配置保留，安装失败时恢复旧应用。"
                alert.addButton(withTitle: "安装并重新打开")
                alert.addButton(withTitle: "取消")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                let bundledHelper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/LaunchDockUpdateHelper")
                let helper = workspace.appendingPathComponent("LaunchDockUpdateHelper")
                try FileManager.default.copyItem(at: bundledHelper, to: helper)
                let process = Process()
                process.executableURL = helper
                process.arguments = [String(ProcessInfo.processInfo.processIdentifier), workspace.path]
                try process.run()
                ownedWorkspace = nil // The helper owns cleanup after the current app exits.
                preparingUpdate = false
                NSApp.terminate(nil)
            } catch {
                self.error = error.localizedDescription + "\n未安装更新，当前应用保持可用。"
            }
        }
    }
}
