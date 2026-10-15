import Foundation
import Combine
import Darwin
import ProcessSupport

public enum ServiceState: String {
    case stopped, starting, running, stopping, failed
    public var title: String {
        switch self {
        case .stopped: return "已停止"
        case .starting: return "启动中"
        case .running: return "运行中"
        case .stopping: return "停止中"
        case .failed: return "异常退出"
        }
    }
}

// Bounded by bytes as well as lines, including output without newlines.
public struct LogBuffer {
    public private(set) var text = ""
    private var pending = [UInt8]()
    public init() {}
    public mutating func append(_ bytes: Data, final: Bool = false) {
        pending.append(contentsOf: bytes)
        var count = pending.count
        if !final, let last = pending.last, last >= 0x80 {
            var start = pending.count - 1
            while start > 0 && pending[start] & 0xC0 == 0x80 { start -= 1 }
            let lead = pending[start]
            let expected = lead & 0xF8 == 0xF0 ? 4 : (lead & 0xF0 == 0xE0 ? 3 : (lead & 0xE0 == 0xC0 ? 2 : 1))
            if pending.count - start < expected { count = start }
        }
        if count > 0 {
            text += String(decoding: pending.prefix(count), as: UTF8.self)
            pending.removeFirst(count)
        }
        let suffix = text.utf8.suffix(1_048_576)
        if text.utf8.count > 1_048_576 {
            var bytes = Array(suffix)
            while let first = bytes.first, first & 0xC0 == 0x80 { bytes.removeFirst() }
            text = String(decoding: bytes, as: UTF8.self)
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > 2_000 { text = lines.suffix(2_000).joined(separator: "\n") }
    }
    public mutating func clear() { text = ""; pending.removeAll() }
}

public struct ServiceSnapshot {
    public var state: ServiceState = .stopped
    public var pid: Int32?
    public var environmentPath: String?
    public var error: String?
    public var browserURL: URL?
    public var log = LogBuffer()
    public init() {}
}

@MainActor
public final class ServiceRunner: ObservableObject {
    @Published public private(set) var snapshots: [UUID: ServiceSnapshot] = [:]
    private final class Job {
        let pid: pid_t
        let fd: Int32
        let role: ServiceRole
        var status: Int32?
        var outputEnded = false
        var stopRequested = false
        var deadline: Date?
        var killed = false
        init(pid: pid_t, fd: Int32, role: ServiceRole) { self.pid = pid; self.fd = fd; self.role = role }
    }
    private var jobs: [UUID: Job] = [:]
    private var timer: Timer?
    public init() {}
    public func snapshot(for id: UUID) -> ServiceSnapshot { snapshots[id] ?? ServiceSnapshot() }
    public func isActive(_ id: UUID) -> Bool { jobs[id] != nil }
    public var hasActiveServices: Bool { !jobs.isEmpty }

    public func start(_ service: Service, projectDirectory: String? = nil) {
        guard jobs[service.id] == nil else { return }
        snapshots[service.id] = ServiceSnapshot()
        snapshots[service.id]?.state = .starting
        do {
            guard !service.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DockError("Empty command\n启动命令不能为空。") }
            let environment = try PythonEnvironment.resolve(at: service.workingDirectory, projectDirectory: projectDirectory)
            let strings = environment.variables.sorted { $0.key < $1.key }.map { strdup("\($0.key)=\($0.value)") }
            defer { strings.forEach { free($0) } }
            var envp = strings + [nil]
            var pid: pid_t = 0
            var fd: Int32 = -1
            let result = envp.withUnsafeMutableBufferPointer { buffer in
                ld_spawn(service.workingDirectory, service.command, buffer.baseAddress!, &pid, &fd)
            }
            guard result == 0 else { throw DockError("posix_spawn: \(String(cString: strerror(result)))\n无法启动命令，请检查目录和权限。") }
            jobs[service.id] = Job(pid: pid, fd: fd, role: service.role)
            snapshots[service.id]?.state = .running
            snapshots[service.id]?.pid = pid
            snapshots[service.id]?.environmentPath = environment.directory
            ensureTimer()
        } catch {
            snapshots[service.id]?.state = .failed
            snapshots[service.id]?.error = error.localizedDescription
        }
    }

    public func stop(_ id: UUID) {
        guard let job = jobs[id], job.deadline == nil else { return }
        job.stopRequested = true
        beginStop(id, job)
    }
    public func clearLog(_ id: UUID) { snapshots[id]?.log.clear() }
    public func forget(_ id: UUID) { if jobs[id] == nil { snapshots.removeValue(forKey: id) } }

    public func stopAll() async -> Bool {
        for id in Array(jobs.keys) { stop(id) }
        let end = Date().addingTimeInterval(12)
        while !jobs.isEmpty && Date() < end {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return jobs.isEmpty
    }
    public func stopServices(_ ids: [UUID]) async -> Bool {
        ids.forEach(stop)
        let end = Date().addingTimeInterval(12)
        while ids.contains(where: isActive) && Date() < end {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return !ids.contains(where: isActive)
    }

    private func ensureTimer() {
        guard timer == nil else { return }
        let next = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }
    private func groupExists(_ job: Job) -> Bool {
        guard job.pid > 1, job.pid != getpgrp() else { return false }
        return kill(-job.pid, 0) == 0 || errno == EPERM
    }
    private func signal(_ job: Job, _ value: Int32) {
        guard job.pid > 1, job.pid != getpgrp(), groupExists(job) else { return }
        if kill(-job.pid, value) != 0 && errno != ESRCH {
            // Keep the job owned; the next tick verifies cleanup rather than claiming success.
        }
    }
    private func beginStop(_ id: UUID, _ job: Job) {
        snapshots[id]?.state = .stopping
        snapshots[id]?.browserURL = nil
        job.deadline = Date().addingTimeInterval(5)
        signal(job, SIGTERM)
    }
    private func drain(_ id: UUID, _ job: Job) {
        var buffer = [UInt8](repeating: 0, count: 8192)
        // ponytail: bounded main-run-loop reads; move I/O off-main if many noisy services cause measurable stalls.
        for _ in 0..<8 {
            let count = read(job.fd, &buffer, buffer.count)
            if count > 0 { snapshots[id]?.log.append(Data(buffer.prefix(count))) }
            else {
                if count == 0 { job.outputEnded = true }
                break
            }
        }
    }
    private func tick() {
        for (id, job) in Array(jobs) {
            drain(id, job)
            if job.role == .frontend, snapshots[id]?.state == .running, snapshots[id]?.browserURL == nil {
                snapshots[id]?.browserURL = frontendURL(in: snapshots[id]?.log.text ?? "")
            }
            if job.status == nil {
                var status: Int32 = 0
                let result = waitpid(job.pid, &status, WNOHANG)
                if result == job.pid { job.status = status }
            }
            if let status = job.status {
                if groupExists(job) {
                    if job.deadline == nil { beginStop(id, job) }
                } else if job.outputEnded {
                    finish(id, job, status)
                    continue
                }
            }
            if let deadline = job.deadline, Date() >= deadline {
                if !job.killed {
                    signal(job, SIGKILL)
                    job.killed = true
                    job.deadline = Date().addingTimeInterval(5)
                } else {
                    snapshots[id]?.state = .failed
                    snapshots[id]?.error = "Process group cleanup timed out: \(job.pid)\n进程组清理超时，仍保留管理记录，请重试停止。"
                    job.deadline = nil
                }
            }
        }
        if jobs.isEmpty { timer?.invalidate(); timer = nil }
    }
    private func finish(_ id: UUID, _ job: Job, _ status: Int32) {
        // The leader is reaped, its group is gone, and the output pipe has reached EOF.
        close(job.fd)
        snapshots[id]?.log.append(Data(), final: true)
        snapshots[id]?.browserURL = nil
        snapshots[id]?.pid = nil
        if job.stopRequested || status == 0 {
            snapshots[id]?.state = .stopped
        } else {
            snapshots[id]?.state = .failed
            snapshots[id]?.error = "命令异常结束，请查看日志中的原始错误。"
        }
        jobs.removeValue(forKey: id)
    }
}
