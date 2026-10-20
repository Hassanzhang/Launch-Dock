import Foundation

public struct UpdateVersion: Comparable, Equatable {
    public let version: String
    public let build: String
    private let numbers: [Int]
    public init(version: String, build: String) throws {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        let builds = build.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, (1...3).contains(builds.count),
              (parts + builds).allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) && Int($0) != nil }) else {
            throw DockError("Invalid version: \(version) (\(build))\n更新包需要有效的数字版本和 build。")
        }
        self.version = version; self.build = build
        numbers = parts.map { Int($0)! } + builds.map { Int($0)! } + Array(repeating: 0, count: 3 - builds.count)
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.numbers == rhs.numbers }
}

public enum LocalUpdate {
    public static let identifier = "local.launchdock.app"
    public static let destination = URL(fileURLWithPath: "/Applications/LaunchDock.app")

    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> Data {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe; process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DockError(String(decoding: output, as: UTF8.self) + "\n安装包检查或磁盘操作失败，原应用未被直接覆盖。")
        }
        return output
    }

    @discardableResult
    public static func validate(_ app: URL, newerThan current: UpdateVersion? = nil) throws -> UpdateVersion {
        let fm = FileManager.default
        guard app.pathExtension.lowercased() == "app", try app.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false else {
            throw DockError("Invalid application bundle\n请选择应用本体，不能选择符号链接。")
        }
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["CFBundleIdentifier"] as? String == identifier,
              plist["CFBundlePackageType"] as? String == "APPL",
              let version = plist["CFBundleShortVersionString"] as? String,
              let build = plist["CFBundleVersion"] as? String,
              let executable = plist["CFBundleExecutable"] as? String,
              !executable.isEmpty, !executable.contains("/"), executable != ".", executable != ".." else {
            throw DockError("Invalid LaunchDock bundle\n应用标识、版本或主程序信息不正确。")
        }
        if let minimum = plist["LSMinimumSystemVersion"] as? String {
            let system = ProcessInfo.processInfo.operatingSystemVersion
            let installed = "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"
            guard minimum.split(separator: ".").allSatisfy({ Int($0) != nil }),
                  minimum.compare(installed, options: .numeric) != .orderedDescending else {
                throw DockError("Unsupported macOS version\n更新包要求更高的 macOS 版本。")
            }
        }
        let next = try UpdateVersion(version: version, build: build)
        if let current, next <= current { throw DockError("Update is not newer: \(version) (\(build))\n请选择比当前版本更新的安装包。") }
        let binary = app.appendingPathComponent("Contents/MacOS/" + executable)
        guard fm.isExecutableFile(atPath: binary.path), try binary.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false else {
            throw DockError("Missing executable\n更新包缺少有效的主程序。")
        }
        let architectures = String(decoding: try run("/usr/bin/lipo", ["-archs", binary.path]), as: UTF8.self).split(whereSeparator: { $0.isWhitespace })
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        guard architectures.contains(Substring(architecture)) else { throw DockError("Incompatible architecture\n更新包不支持本机架构。") }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        return next
    }

    /// Returns an owned workspace; callers remove it on cancellation or after helper completion.
    public static func prepare(_ source: URL, current: UpdateVersion) throws -> URL {
        let fm = FileManager.default
        let workspace = fm.temporaryDirectory.appendingPathComponent("LaunchDock-update-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var mounted = false
        do {
            let staged = workspace.appendingPathComponent("LaunchDock.app")
            if source.pathExtension.lowercased() == "dmg" {
                let mount = workspace.appendingPathComponent("mount", isDirectory: true)
                try fm.createDirectory(at: mount, withIntermediateDirectories: false)
                do {
                    try run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, source.path])
                    mounted = true
                } catch {
                    let mountDevice = (try? fm.attributesOfFileSystem(forPath: mount.path))?[.systemNumber] as? NSNumber
                    let parentDevice = (try? fm.attributesOfFileSystem(forPath: workspace.path))?[.systemNumber] as? NSNumber
                    // On uncertain or partial attachment, preserve rather than recurse into a mounted volume.
                    mounted = mountDevice == nil || parentDevice == nil || mountDevice != parentDevice
                    throw error
                }
                do {
                    let apps = try fm.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil).filter { $0.pathExtension.lowercased() == "app" }
                    guard apps.count == 1 else { throw DockError("Ambiguous disk image\n镜像根目录必须只包含一个 LaunchDock.app。") }
                    try validate(apps[0], newerThan: current)
                    try fm.copyItem(at: apps[0], to: staged)
                } catch {
                    // Never delete a workspace that may still contain a mounted filesystem.
                    do { try run("/usr/bin/hdiutil", ["detach", mount.path]); mounted = false }
                    catch { throw DockError("Unmount failed: \(mount.path)\n镜像卸载失败，临时目录保留，请先推出磁盘。") }
                    throw error
                }
                do { try run("/usr/bin/hdiutil", ["detach", mount.path]); mounted = false }
                catch { throw DockError("Unmount failed: \(mount.path)\n镜像卸载失败，临时目录保留，请先推出磁盘。") }
                try fm.removeItem(at: mount)
            } else {
                try validate(source, newerThan: current)
                try fm.copyItem(at: source, to: staged)
            }
            try validate(staged, newerThan: current)
            return workspace
        } catch {
            // Retain workspaces if a disk may still be mounted.
            if !mounted { try? fm.removeItem(at: workspace) }
            throw error
        }
    }

    /// Uses same-volume renames; target injection is only for isolated filesystem checks.
    public static func install(_ staged: URL, target: URL, launch: (URL) throws -> Void) throws {
        let fm = FileManager.default
        try validate(staged)
        let parent = target.deletingLastPathComponent(), token = UUID().uuidString
        let pending = parent.appendingPathComponent(".LaunchDock-new-" + token + ".app")
        let backup = parent.appendingPathComponent(".LaunchDock-backup-" + token + ".app")
        var backedUp = false, placed = false
        defer { try? fm.removeItem(at: pending) }
        do {
            if fm.fileExists(atPath: target.path) {
                let previous = try validate(target)
                guard try validate(staged) > previous else { throw DockError("Installed version is newer or equal\n安装目录已有相同或更新版本，未替换。") }
            }
            try fm.copyItem(at: staged, to: pending)
            try validate(pending)
            if fm.fileExists(atPath: target.path) { try fm.moveItem(at: target, to: backup); backedUp = true }
            try fm.moveItem(at: pending, to: target); placed = true
            try launch(target)
        } catch {
            do {
                if placed { try fm.removeItem(at: target) }
                if backedUp { try fm.moveItem(at: backup, to: target) }
            } catch let rollbackError {
                throw DockError("Rollback failed: \(rollbackError.localizedDescription)\n恢复失败，旧应用备份保留在：\(backup.path)")
            }
            throw DockError(error.localizedDescription + "\n更新失败，已恢复安装前的应用状态。")
        }
        if backedUp { try? fm.removeItem(at: backup) }
    }
}
