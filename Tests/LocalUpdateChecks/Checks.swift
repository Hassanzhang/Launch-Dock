import Foundation
import LaunchDockCore

@main
struct Checks {
    static func main() throws {
        func expect(_ condition: Bool) { precondition(condition) }
        let fm = FileManager.default
        guard CommandLine.arguments.count == 2 else { fatalError("Pass a built LaunchDock.app fixture") }
        let original = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = fm.temporaryDirectory.appendingPathComponent("LaunchDock-update-checks-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        func command(_ name: String, _ args: [String]) throws {
            let p = Process(); p.executableURL = URL(fileURLWithPath: name); p.arguments = args
            try p.run(); p.waitUntilExit(); expect(p.terminationStatus == 0)
        }
        func expectFailure(_ label: String, _ block: () throws -> Void) {
            do { try block(); fatalError("Expected failure: " + label) }
            catch { print("PASS rejected " + label) }
        }
        func fixture(_ name: String, version: String, build: String, id: String = LocalUpdate.identifier) throws -> URL {
            let app = root.appendingPathComponent(name + ".app")
            try fm.copyItem(at: original, to: app)
            let url = app.appendingPathComponent("Contents/Info.plist")
            var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as! [String: Any]
            plist["CFBundleShortVersionString"] = version; plist["CFBundleVersion"] = build; plist["CFBundleIdentifier"] = id
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
            try command("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
            return app
        }
        let oldVersion = try UpdateVersion(version: "0.1.2", build: "3")
        expect(try UpdateVersion(version: "0.1.10", build: "1") > oldVersion)
        expect(try UpdateVersion(version: "0.1.2", build: "4") > oldVersion)
        let brokenImage = root.appendingPathComponent("broken.dmg")
        try Data("not a disk image".utf8).write(to: brokenImage)
        let before = Set(try fm.contentsOfDirectory(atPath: fm.temporaryDirectory.path).filter { $0.hasPrefix("LaunchDock-update-") })
        expectFailure("invalid DMG") { _ = try LocalUpdate.prepare(brokenImage, current: oldVersion) }
        let after = Set(try fm.contentsOfDirectory(atPath: fm.temporaryDirectory.path).filter { $0.hasPrefix("LaunchDock-update-") })
        expect(before == after)
        let next = try fixture("新版本 空格", version: "0.1.3", build: "4")
        let old = try fixture("旧版本", version: "0.1.2", build: "3")
        expectFailure("same version") { _ = try LocalUpdate.validate(old, newerThan: oldVersion) }
        let wrong = try fixture("wrong", version: "0.1.3", build: "4", id: "different.app")
        expectFailure("wrong identity") { _ = try LocalUpdate.validate(wrong) }
        expectFailure("invalid version") { _ = try UpdateVersion(version: "v0.1.3", build: "4") }
        let bad = try fixture("damaged", version: "0.1.3", build: "4")
        try Data("tampered".utf8).write(to: bad.appendingPathComponent("Contents/Resources/AppIcon.icns"))
        expectFailure("tampered signature") { _ = try LocalUpdate.validate(bad) }
        let link = root.appendingPathComponent("link.app")
        try fm.createSymbolicLink(at: link, withDestinationURL: next)
        expectFailure("symlink application") { _ = try LocalUpdate.validate(link) }
        let workspace = try LocalUpdate.prepare(next, current: oldVersion)
        defer { try? fm.removeItem(at: workspace) }
        let staged = workspace.appendingPathComponent("LaunchDock.app")
        let target = root.appendingPathComponent("Installed.app")
        try fm.copyItem(at: old, to: target)
        let config = root.appendingPathComponent("projects.json")
        try Data("preserve configuration".utf8).write(to: config)
        expectFailure("launch failure with rollback") {
            try LocalUpdate.install(staged, target: target) { _ in throw DockError("Injected launch failure") }
        }
        expect(try LocalUpdate.validate(target) == oldVersion)
        try LocalUpdate.install(staged, target: target) { installed in
            expect(try LocalUpdate.validate(installed) > oldVersion)
        }
        expectFailure("equal installed version") { try LocalUpdate.install(staged, target: target) { _ in fatalError("Must not launch") } }
        let firstInstall = root.appendingPathComponent("FirstInstall.app")
        expectFailure("first install launch failure") {
            try LocalUpdate.install(staged, target: firstInstall) { _ in throw DockError("Injected first launch failure") }
        }
        expect(!fm.fileExists(atPath: firstInstall.path))
        try LocalUpdate.install(staged, target: firstInstall) { _ in }
        let readOnly = root.appendingPathComponent("read-only")
        try fm.createDirectory(at: readOnly, withIntermediateDirectories: false)
        let protected = readOnly.appendingPathComponent("Protected.app")
        try fm.copyItem(at: old, to: protected)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.path)
        expectFailure("unwritable installation directory") { try LocalUpdate.install(staged, target: protected) { _ in fatalError("Must not launch") } }
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnly.path)
        expect(try LocalUpdate.validate(protected) == oldVersion)
        expect(try String(contentsOf: config) == "preserve configuration")
        expect(!(try fm.contentsOfDirectory(atPath: root.path)).contains { $0.hasPrefix(".LaunchDock-") })
        print("PASS installation, rollback, configuration preservation and cleanup")
        let image = root.appendingPathComponent("update.dmg")
        let contents = root.appendingPathComponent("image")
        try fm.createDirectory(at: contents, withIntermediateDirectories: false)
        try fm.copyItem(at: next, to: contents.appendingPathComponent("LaunchDock.app"))
        try command("/usr/bin/hdiutil", ["create", "-srcfolder", contents.path, "-format", "UDZO", image.path])
        let dmgWorkspace = try LocalUpdate.prepare(image, current: oldVersion)
        try fm.removeItem(at: dmgWorkspace)
        print("PASS read-only DMG preparation and unmount")
        try fm.copyItem(at: old, to: contents.appendingPathComponent("Other.app"))
        let ambiguousImage = root.appendingPathComponent("ambiguous.dmg")
        try command("/usr/bin/hdiutil", ["create", "-srcfolder", contents.path, "-format", "UDZO", ambiguousImage.path])
        expectFailure("ambiguous DMG") { _ = try LocalUpdate.prepare(ambiguousImage, current: oldVersion) }
        let final = Set(try fm.contentsOfDirectory(atPath: fm.temporaryDirectory.path).filter { $0.hasPrefix("LaunchDock-update-") })
        expect(final == before.union([workspace.lastPathComponent]))
        print("PASS rejected images leave no workspace or mounted volume")
    }
}
