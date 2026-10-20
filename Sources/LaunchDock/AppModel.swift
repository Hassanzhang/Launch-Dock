import AppKit
import SwiftUI
import LaunchDockCore

@MainActor
final class AppModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var selection: UUID?
    @Published var error: String?
    @Published var editing: Project?
    @Published var showingEditor = false
    @Published var busy = false
    @Published var preparingUpdate = false
    let runner = ServiceRunner()
    let store: ConfigurationStore
    private(set) var loadFailed = false
    init() {
        let override = ProcessInfo.processInfo.environment["LAUNCHDOCK_CONFIG_PATH"]
        store = ConfigurationStore(url: override.map { URL(fileURLWithPath: $0) })
        do { projects = try store.load(); selection = projects.first?.id }
        catch { loadFailed = true; self.error = error.localizedDescription + "\n配置读取失败，原文件已保留；本次禁止修改配置。" }
    }
    func persist(_ next: [Project]) -> Bool {
        guard !loadFailed else { return false }
        do { try store.save(next); projects = next; return true }
        catch { self.error = error.localizedDescription + "\n保存失败，当前配置未更改。"; return false }
    }
    func save(_ project: Project) -> Bool {
        guard !busy else { return false }
        if let old = projects.first(where: { $0.id == project.id }), old.services.contains(where: { runner.isActive($0.id) }) {
            error = "项目仍有运行中的服务，请先停止后编辑。"; return false
        }
        var next = projects
        if let index = next.firstIndex(where: { $0.id == project.id }) { next[index] = project }
        else { next.append(project) }
        guard persist(next) else { return false }
        selection = project.id
        return true
    }
    func edit(_ project: Project?) { editing = project; showingEditor = true }
    func delete(_ project: Project) async {
        busy = true; defer { busy = false }
        guard await runner.stopServices(project.services.map(\.id)) else { error = "服务清理失败，项目未删除。"; return }
        guard persist(projects.filter { $0.id != project.id }) else { return }
        project.services.forEach { runner.forget($0.id) }
        if selection == project.id { selection = projects.first?.id }
    }
    func move(from: IndexSet, to: Int) {
        var next = projects; next.move(fromOffsets: from, toOffset: to); _ = persist(next)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    var window: NSWindow?
    var quitting = false
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model?.preparingUpdate == true {
            model?.error = "正在检查并暂存更新包，请等待完成后再退出。"
            return .terminateCancel
        }
        guard let model, model.runner.hasActiveServices else { return .terminateNow }
        guard !quitting else { return .terminateLater }
        quitting = true; model.busy = true
        Task {
            let stopped = await model.runner.stopAll()
            if !stopped { model.error = "退出前服务清理失败，应用继续保留，请检查后重试。"; window?.makeKeyAndOrderFront(nil) }
            quitting = false; model.busy = false
            sender.reply(toApplicationShouldTerminate: stopped)
        }
        return .terminateLater
    }
}
