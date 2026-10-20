import AppKit
import Sparkle
import SwiftUI

@MainActor
final class OnlineUpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?
    private weak var model: AppModel?

    func checkForUpdates(model: AppModel) {
        guard !model.busy else { return }
        guard !model.runner.hasActiveServices else {
            model.error = "请先停止所有服务，再检查和安装更新。"
            return
        }
        self.model = model
        do {
            if controller == nil {
                let candidate = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
                try candidate.updater.start()
                candidate.updater.automaticallyChecksForUpdates = false
                candidate.updater.automaticallyDownloadsUpdates = false
                controller = candidate
            }
            guard let controller, controller.updater.canCheckForUpdates else {
                model.error = "更新器正在处理其他请求，请稍后重试。"
                return
            }
            controller.checkForUpdates(nil)
        } catch {
            model.error = error.localizedDescription + "\n无法启动更新检查，请确认正在运行完整的 LaunchDock.app。"
        }
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard let model, !model.busy, !model.runner.hasActiveServices else {
            throw NSError(domain: "LaunchDock.Update", code: 1, userInfo: [NSLocalizedDescriptionKey: "请先停止所有服务并完成当前操作，再检查更新。"])
        }
        model.busy = true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        model?.busy = false
    }
}
