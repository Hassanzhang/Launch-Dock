import Foundation
import Darwin
import LaunchDockCore


private var failures = 0
private func expect(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    if !value { failures += 1; print("FAIL \(file):\(line): expected true") }
}
private func expectFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) { expect(!value, file: file, line: line) }
private func expectEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) {
    if a != b { failures += 1; print("FAIL \(file):\(line): \(a) != \(b)") }
}
private func expectNotEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { expect(a != b, file: file, line: line) }
private func expectAtMost<T: Comparable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { expect(a <= b, file: file, line: line) }
private func expectThrows<T>(_ body: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) {
    do { _ = try body(); expect(false, file: file, line: line) } catch {}
}
private func unwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw DockError("Expected non-nil value") }; return value
}

@main
struct Checks {
    @MainActor static func main() async {
        setbuf(stdout, nil)
        do { try await run() }
        catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
    }
    @MainActor static func run() async throws {
        let config = ConfigurationChecks()
        try config.testConfigurationRoundTripAndCorruptionPreservation()
        try config.testRejectsInvalidAndDuplicateConfiguration()
        config.testLogUTF8AndBounds()
        config.testFrontendURLs()
        print("PASS configuration, corruption, validation, UTF-8 and log bounds")
        let process = ProcessChecks()
        try process.testEnvironmentPriorityMissingAndBroken()
        try await process.testProjectRootEnvironmentFallback()
        try await process.testFrontendLinkLifecycle()
        try await process.testHomebrewCommandsWithMinimalPath()
        try await process.testActualEnvironmentLogsAndNormalExit()
        try await process.testNonzeroAndMissingEnvironment()
        try await process.testSignalAndLargeOutput()
        print("PASS virtual environments, actual interpreter, logs, large output and exit status")
        try await process.testConcurrentServicesDuplicateStartAndRestart()
        print("PASS concurrent services, duplicate start, restart and stopAll")
        try await process.testProcessGroupForcedCleanupAndUnrelatedProcess()
        print("PASS process group, forced child cleanup and unrelated process safety")
        try await process.testLeaderExitCleansSurvivingChild()
        guard failures == 0 else { throw DockError("\(failures) checks failed") }
        if let path = ProcessInfo.processInfo.environment["LAUNCHDOCK_UVICORN_FIXTURE"] {
            try await process.testUvicornReload(URL(fileURLWithPath: path))
            print("PASS real uvicorn --reload and worker cleanup")
        } else {
            print("SKIP real uvicorn: set LAUNCHDOCK_UVICORN_FIXTURE to a prepared project")
        }
        guard failures == 0 else { throw DockError("\(failures) checks failed") }
        print("PASS all behavioral checks")
    }
}

final class ConfigurationChecks {
    func testConfigurationRoundTripAndCorruptionPreservation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigurationStore(url: root.appendingPathComponent("projects.json"))
        let service = Service(role: .backend, workingDirectory: "/tmp/中文 项目", command: "python app.py")
        let first = Project(name: "甲", directory: "/tmp/中文 项目", services: [service])
        let second = Project(name: "乙", directory: "/tmp/乙", services: [Service(role: .frontend, workingDirectory: "/tmp/乙", command: "python main.py")])
        try store.save([second, first])
        expectEqual(try store.load(), [second, first])
        let damaged = Data("{broken".utf8)
        try damaged.write(to: store.url)
        expectThrows(try store.load())
        expectEqual(try Data(contentsOf: store.url), damaged)
    }
    func testRejectsInvalidAndDuplicateConfiguration() throws {
        expectThrows(try Project(name: "empty", directory: "/tmp").validate())
        let service = Service(role: .backend, workingDirectory: "/tmp", command: "python app.py")
        expectThrows(try Project(name: "dup", directory: "/tmp", services: [service, service]).validate())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigurationStore(url: root.appendingPathComponent("projects.json"))
        let first = Project(name: "one", directory: "/tmp", services: [service])
        expectThrows(try store.save([first, first]))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{\"schemaVersion\":2,\"projects\":[]}".utf8).write(to: store.url)
        expectThrows(try store.load())
    }
    func testFrontendURLs() {
        expectEqual(frontendURL(in: "Local: http://localhost:5173/\n")?.absoluteString, "http://localhost:5173/")
        expectEqual(frontendURL(in: "\u{001B}[32m➜ Local: \u{001B}[36mhttp://localhost:5174/\u{001B}[0m\n")?.port, 5174)
        expectEqual(frontendURL(in: "Ready: https://127.0.0.1:8443/app?q=1\n")?.scheme, "https")
        expectEqual(frontendURL(in: "Ready: http://[::1]:3000/\n")?.port, 3000)
        expectEqual(frontendURL(in: "Ready: http://0.0.0.0:3000/\n")?.host, "localhost")
        expectEqual(frontendURL(in: "Ready: http://[::]:3000/\n")?.host, "localhost")
        expect(frontendURL(in: "Local: http://localhost:5") == nil)
        for text in ["https://example.com/", "http://localhost.evil:5173/", "http://user:pass@localhost:5173/", "file:///tmp/test", "http://localhost:99999/"] {
            expect(frontendURL(in: text + "\n") == nil)
        }
        expectEqual(frontendURL(in: "Docs: https://vite.dev/\nLocal: http://localhost:5173/\n")?.host, "localhost")
    }
    func testLogUTF8AndBounds() {
        var log = LogBuffer()
        let bytes = Array("中文🙂\n".utf8)
        for byte in bytes { log.append(Data([byte])) }
        expectEqual(log.text, "中文🙂\n")
        log.append(Data(String(repeating: "行\n", count: 3_000).utf8))
        expectAtMost(log.text.split(separator: "\n", omittingEmptySubsequences: false).count, 2_000)
        log.append(Data(String(repeating: "文", count: 400_000).utf8))
        expectAtMost(log.text.utf8.count, 1_048_576)
        expectFalse(log.text.contains("�"))
        log.clear(); expectEqual(log.text, "")
    }
}

@MainActor
final class ProcessChecks {
    private func fixture(name: String = ".venv") throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LaunchDock 中文 \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "venv", "--without-pip", root.appendingPathComponent(name).path]
        try process.run(); process.waitUntilExit()
        expectEqual(process.terminationStatus, 0)
        return root
    }
    private func service(_ root: URL, command: String = "python app.py") -> Service {
        Service(role: .backend, workingDirectory: root.path, command: command)
    }
    private func write(_ text: String, to root: URL) throws { try text.write(to: root.appendingPathComponent("app.py"), atomically: true, encoding: .utf8) }
    private func wait(_ condition: @escaping () -> Bool, seconds: Double = 10) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while !condition() && Date() < end { try? await Task.sleep(nanoseconds: 50_000_000) }
        return condition()
    }
    func testEnvironmentPriorityMissingAndBroken() throws {
        let root = try fixture(name: "venv"); defer { try? FileManager.default.removeItem(at: root) }
        expect(try PythonEnvironment.resolve(at: root.path).directory.hasSuffix("/venv"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(".venv"), withDestinationURL: root.appendingPathComponent("venv"))
        expect(try PythonEnvironment.resolve(at: root.path).directory.hasSuffix("/.venv"))
        try FileManager.default.removeItem(at: root.appendingPathComponent(".venv"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".venv"), withIntermediateDirectories: true)
        expectThrows(try PythonEnvironment.resolve(at: root.path))
        expectThrows(try PythonEnvironment.resolve(at: root.appendingPathComponent("missing").path))
        let empty = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        expectThrows(try PythonEnvironment.resolve(at: empty.path))
    }
    func testProjectRootEnvironmentFallback() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let frontend = root.appendingPathComponent("frontend")
        let backend = root.appendingPathComponent("backend")
        for directory in [frontend, backend] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try write("import os,sys\nprint(sys.executable)\nprint(os.getcwd())\nprint(os.environ['VIRTUAL_ENV'])", to: directory)
        }
        let runner = ServiceRunner()
        let services = [service(frontend), service(backend)]
        for s in services { runner.start(s, projectDirectory: root.path) }
        let completed = await wait { services.allSatisfy { !runner.isActive($0.id) } }
        expect(completed)
        for s in services {
            let state = runner.snapshot(for: s.id)
            expectEqual(state.state, .stopped)
            expectEqual(state.environmentPath, root.appendingPathComponent(".venv").path)
            expect(state.log.text.contains(root.appendingPathComponent(".venv/bin/python").path))
            expect(state.log.text.contains(URL(fileURLWithPath: s.workingDirectory).resolvingSymlinksInPath().path))
        }
        // A configured project root is required; do not search arbitrary ancestors.
        expectThrows(try PythonEnvironment.resolve(at: backend.path))
        // A service-local venv wins even when a root .venv exists.
        let local = frontend.appendingPathComponent("venv")
        try FileManager.default.createSymbolicLink(at: local, withDestinationURL: root.appendingPathComponent(".venv"))
        expectEqual(try PythonEnvironment.resolve(at: frontend.path, projectDirectory: root.path).directory, local.path)
        try FileManager.default.removeItem(at: local)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        expectThrows(try PythonEnvironment.resolve(at: frontend.path, projectDirectory: root.path))
        try FileManager.default.removeItem(at: local)
        try FileManager.default.moveItem(at: root.appendingPathComponent(".venv"), to: root.appendingPathComponent("venv"))
        expectEqual(try PythonEnvironment.resolve(at: frontend.path, projectDirectory: root.path).directory, root.appendingPathComponent("venv").path)
        try FileManager.default.removeItem(at: root.appendingPathComponent("venv"))
        do {
            _ = try PythonEnvironment.resolve(at: frontend.path, projectDirectory: root.path)
            expect(false)
        } catch {
            for base in [frontend, root] {
                for name in [".venv", "venv"] { expect(error.localizedDescription.contains(base.appendingPathComponent(name).path)) }
            }
        }
    }

    func testHomebrewCommandsWithMinimalPath() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let environment = try PythonEnvironment.resolve(at: root.path)
        let paths = environment.variables["PATH"]!.split(separator: ":").map(String.init)
        expectEqual(paths.first, root.appendingPathComponent(".venv/bin").path)
        for path in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] { expect(paths.contains(path)) }
        let installed = ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard installed != nil else { print("SKIP real npm: Homebrew npm is not installed"); return }
        let runner = ServiceRunner()
        let s = service(root, command: "command -v npm && npm --version && node --version && python -c 'import sys; print(sys.executable)'")
        runner.start(s)
        let completed = await wait { !runner.isActive(s.id) }
        expect(completed)
        let state = runner.snapshot(for: s.id)
        expectEqual(state.state, .stopped)
        expect(state.log.text.contains("/bin/npm"))
        expect(state.log.text.contains(root.appendingPathComponent(".venv/bin/python").path))
        print("Checked real npm/node lookup with PATH=" + (ProcessInfo.processInfo.environment["PATH"] ?? "<unset>"))
    }

    func testFrontendLinkLifecycle() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("import sys,time\nsys.stdout.write('Local: http://localhost:5'); sys.stdout.flush()\ntime.sleep(0.5)\nprint('173/',flush=True)\ntime.sleep(120)", to: root)
        let runner = ServiceRunner()
        let frontend = Service(role: .frontend, workingDirectory: root.path, command: "python app.py")
        runner.start(frontend)
        let partial = await wait { runner.snapshot(for: frontend.id).log.text.contains("http://localhost:5") }
        expect(partial)
        expect(runner.snapshot(for: frontend.id).browserURL == nil)
        let found = await wait { runner.snapshot(for: frontend.id).browserURL != nil }
        expect(found)
        expectEqual(runner.snapshot(for: frontend.id).browserURL?.absoluteString, "http://localhost:5173/")
        runner.clearLog(frontend.id)
        expect(runner.snapshot(for: frontend.id).browserURL != nil)
        runner.stop(frontend.id)
        expect(runner.snapshot(for: frontend.id).browserURL == nil)
        let stopped = await wait { !runner.isActive(frontend.id) }; expect(stopped)
        let backend = service(root)
        runner.start(backend)
        let backendPrinted = await wait { runner.snapshot(for: backend.id).log.text.contains("5173") }
        expect(backendPrinted)
        expect(runner.snapshot(for: backend.id).browserURL == nil)
        let clean = await runner.stopAll(); expect(clean)
        try write("import time\ntime.sleep(120)", to: root)
        runner.start(frontend)
        expect(runner.snapshot(for: frontend.id).browserURL == nil)
        let restarted = await runner.stopAll(); expect(restarted)
        try write("print('Local: http://localhost:5173/',flush=True)\nraise RuntimeError('test failure')", to: root)
        runner.start(frontend)
        let failed = await wait { !runner.isActive(frontend.id) }; expect(failed)
        expectEqual(runner.snapshot(for: frontend.id).state, .failed)
        expect(runner.snapshot(for: frontend.id).browserURL == nil)
        print("PASS frontend link parsing, partial output, log clearing, stop, restart and failure")
    }

    func testActualEnvironmentLogsAndNormalExit() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("import sys, os\nprint(sys.executable)\nprint(os.environ['VIRTUAL_ENV'])\nprint('中文🙂', file=sys.stderr)\n", to: root)
        let runner = ServiceRunner(); let s = service(root)
        runner.start(s)
        let completed = await wait { !runner.isActive(s.id) }
        expect(completed)
        let state = runner.snapshot(for: s.id)
        expectEqual(state.state, .stopped)
        expect(state.log.text.contains(root.appendingPathComponent(".venv/bin/python").path))
        expect(state.log.text.contains("中文🙂"))
        expectEqual(state.environmentPath, root.appendingPathComponent(".venv").path)
    }
    func testNonzeroAndMissingEnvironment() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("raise RuntimeError('test failure')", to: root)
        let runner = ServiceRunner(); let s = service(root)
        runner.start(s)
        let completed = await wait { !runner.isActive(s.id) }; expect(completed)
        expectEqual(runner.snapshot(for: s.id).state, .failed)
        expect(runner.snapshot(for: s.id).log.text.contains("RuntimeError: test failure"))
        let missing = Service(role: .frontend, workingDirectory: root.appendingPathComponent("missing").path, command: "python app.py")
        runner.start(missing)
        expectEqual(runner.snapshot(for: missing.id).state, .failed)
        expectFalse(runner.isActive(missing.id))
    }
    func testConcurrentServicesDuplicateStartAndRestart() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("import time\nprint('ready', flush=True)\ntime.sleep(120)", to: root)
        let runner = ServiceRunner(); let a = service(root); let b = service(root)
        runner.start(a); let pid = runner.snapshot(for: a.id).pid
        runner.start(a); runner.start(b)
        expectEqual(pid, runner.snapshot(for: a.id).pid)
        expectNotEqual(pid, runner.snapshot(for: b.id).pid)
        let ready = await wait { runner.snapshot(for: a.id).log.text.contains("ready") }; expect(ready)
        runner.stop(a.id)
        let stopped = await wait { !runner.isActive(a.id) }; expect(stopped)
        expect(runner.isActive(b.id))
        expectEqual(runner.snapshot(for: a.id).state, .stopped)
        try write("print('new run')", to: root)
        runner.start(a)
        let restarted = await wait { !runner.isActive(a.id) }; expect(restarted)
        expectEqual(runner.snapshot(for: a.id).log.text, "new run\n")
        let allStopped = await runner.stopAll(); expect(allStopped)
    }
    func testSignalAndLargeOutput() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let runner = ServiceRunner()
        let signaled = service(root, command: "kill -TERM $$")
        runner.start(signaled)
        let exited = await wait { !runner.isActive(signaled.id) }; expect(exited)
        expectEqual(runner.snapshot(for: signaled.id).state, .failed)
        expect(runner.snapshot(for: signaled.id).error != nil)
        try write("import sys\nprint('x'*2200000)\nprint('END',file=sys.stderr)", to: root)
        let noisy = service(root)
        runner.start(noisy)
        let drained = await wait { !runner.isActive(noisy.id) }; expect(drained)
        expect(runner.snapshot(for: noisy.id).log.text.contains("END"))
        expectAtMost(runner.snapshot(for: noisy.id).log.text.utf8.count, 1_048_576)
    }

    func testProcessGroupForcedCleanupAndUnrelatedProcess() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("""
        import subprocess, signal, time
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        child = subprocess.Popen(['python', '-c', 'import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(120)'])
        time.sleep(0.2)
        print('child=' + str(child.pid), flush=True)
        time.sleep(120)
        """, to: root)
        let unrelated = Process(); unrelated.executableURL = URL(fileURLWithPath: "/bin/sleep"); unrelated.arguments = ["120"]
        try unrelated.run(); defer { if unrelated.isRunning { unrelated.terminate(); unrelated.waitUntilExit() } }
        let runner = ServiceRunner(); let s = service(root); runner.start(s)
        let ready = await wait { runner.snapshot(for: s.id).log.text.contains("child=") }; expect(ready)
        let child = Int32(runner.snapshot(for: s.id).log.text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "child=", with: ""))!
        let pid = runner.snapshot(for: s.id).pid!
        expectEqual(getpgid(pid), pid)
        expectEqual(getpgid(child), pid)
        runner.stop(s.id)
        let stopped = await wait({ !runner.isActive(s.id) }, seconds: 12); expect(stopped)
        expectEqual(kill(pid, 0), -1)
        expectEqual(kill(child, 0), -1)
        expect(unrelated.isRunning)
    }

    func testUvicornReload(_ root: URL) async throws {
        let runner = ServiceRunner()
        let s = service(root, command: "python -m uvicorn web:app --reload --port 0")
        runner.start(s)
        let ready = await wait { runner.snapshot(for: s.id).log.text.contains("Application startup complete") }
        expect(ready)
        let leader = try unwrap(runner.snapshot(for: s.id).pid)
        let output = runner.snapshot(for: s.id).log.text
        let pattern = try NSRegularExpression(pattern: "Started server process \\[([0-9]+)\\]")
        let range = NSRange(output.startIndex..., in: output)
        let match = try unwrap(pattern.firstMatch(in: output, range: range))
        let workerRange = try unwrap(Range(match.range(at: 1), in: output))
        var worker = try unwrap(Int32(output[workerRange]))
        let originalWorker = worker
        let web = root.appendingPathComponent("web.py")
        let original = try String(contentsOf: web, encoding: .utf8)
        // StatReload must record its initial mtime before this test changes the source.
        try await Task.sleep(nanoseconds: 1_000_000_000)
        try (original + "\n# reload check \(UUID().uuidString)\n").write(to: web, atomically: true, encoding: .utf8)
        let reloaded = await wait { runner.snapshot(for: s.id).log.text.components(separatedBy: "Application startup complete").count >= 3 }
        expect(reloaded)
        let updated = runner.snapshot(for: s.id).log.text
        let matches = pattern.matches(in: updated, range: NSRange(updated.startIndex..., in: updated))
        let latest = try unwrap(matches.last)
        worker = try unwrap(Int32(updated[try unwrap(Range(latest.range(at: 1), in: updated))]))
        expectNotEqual(worker, originalWorker)
        expectEqual(kill(originalWorker, 0), -1)
        expectEqual(getpgid(worker), leader)
        runner.stop(s.id)
        let done = await wait({ !runner.isActive(s.id) }, seconds: 12)
        expect(done)
        expectEqual(kill(leader, 0), -1)
        expectEqual(kill(worker, 0), -1)
    }

    func testLeaderExitCleansSurvivingChild() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("import subprocess,time\nc=subprocess.Popen(['python','-c','import time;time.sleep(120)'])\nprint('child='+str(c.pid),flush=True)", to: root)
        let runner = ServiceRunner(); let s = service(root); runner.start(s)
        let done = await wait { !runner.isActive(s.id) }; expect(done)
        let text = runner.snapshot(for: s.id).log.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let child = try unwrap(Int32(text.replacingOccurrences(of: "child=", with: "")))
        expectEqual(kill(child, 0), -1)
    }
}
