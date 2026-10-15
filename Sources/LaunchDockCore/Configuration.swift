import Foundation

public enum ServiceRole: String, Codable, CaseIterable, Identifiable {
    case frontend, backend
    public var id: String { rawValue }
    public var title: String { self == .frontend ? "前端" : "后端" }
}

public struct Service: Codable, Identifiable, Equatable {
    public var id: UUID
    public var role: ServiceRole
    public var workingDirectory: String
    public var command: String
    public init(id: UUID = UUID(), role: ServiceRole, workingDirectory: String, command: String) {
        self.id = id; self.role = role; self.workingDirectory = workingDirectory; self.command = command
    }
}

public struct Project: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var directory: String
    public var services: [Service]
    public init(id: UUID = UUID(), name: String = "", directory: String = "", services: [Service] = []) {
        self.id = id; self.name = name; self.directory = directory; self.services = services
    }
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DockError("项目名称不能为空。") }
        guard directory.hasPrefix("/") else { throw DockError("请选择项目目录（绝对路径）。") }
        guard !services.isEmpty, services.count <= 2, Set(services.map(\.role)).count == services.count else {
            throw DockError("至少配置一个服务，每种角色最多配置一个。")
        }
        for service in services {
            guard service.workingDirectory.hasPrefix("/"), !service.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DockError("\(service.role.title)需要工作目录和启动命令。")
            }
        }
    }
}

public struct DockError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct Configuration: Codable {
    public var schemaVersion = 1
    public var projects: [Project]
    public init(projects: [Project] = []) { self.projects = projects }
}

public struct ConfigurationStore {
    public let url: URL
    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LaunchDock/projects.json")
    }
    public func load() throws -> [Project] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
        guard config.schemaVersion == 1 else { throw DockError("Unsupported schemaVersion: \(config.schemaVersion)\n配置版本不受支持，已保留原文件。") }
        try validate(config.projects)
        return config.projects
    }
    public func save(_ projects: [Project]) throws {
        try validate(projects)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Configuration(projects: projects)).write(to: url, options: .atomic)
    }
    private func validate(_ projects: [Project]) throws {
        guard Set(projects.map(\.id)).count == projects.count else { throw DockError("Duplicate project IDs\n项目标识重复，配置未写入。") }
        let services = projects.flatMap(\.services)
        guard Set(services.map(\.id)).count == services.count else { throw DockError("Duplicate service IDs\n服务标识重复，配置未写入。") }
        try projects.forEach { try $0.validate() }
    }
}

public struct PythonEnvironment {
    public let directory: String
    public let variables: [String: String]
    public static func resolve(at workingDirectory: String, projectDirectory: String? = nil) throws -> PythonEnvironment {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: workingDirectory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw DockError("Working directory not found: \(workingDirectory)\n服务工作目录不存在或不是文件夹。")
        }
        var directories = [URL(fileURLWithPath: workingDirectory).standardizedFileURL]
        if let projectDirectory {
            let root = URL(fileURLWithPath: projectDirectory).standardizedFileURL
            if !directories.contains(root) { directories.append(root) }
        }
        let candidates = directories.flatMap { directory in
            [".venv", "venv"].map { directory.appendingPathComponent($0).path }
        }
        for path in candidates {
            guard fm.fileExists(atPath: path) else { continue }
            guard fm.isExecutableFile(atPath: path + "/bin/python") else {
                throw DockError("Invalid Python environment: \(path)/bin/python\n所选虚拟环境缺少可执行的 Python，请先修复；不会回退到其他环境。")
            }
            var variables = ProcessInfo.processInfo.environment
            variables["VIRTUAL_ENV"] = path
            // Finder launches may only supply system PATH. Keep venv first and inherited tools ahead of fallbacks.
            let inheritedPaths = (variables["PATH"] ?? "").split(separator: ":").map(String.init)
            let standardPaths = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
            variables["PATH"] = ([path + "/bin"] + inheritedPaths + standardPaths).joined(separator: ":")
            variables.removeValue(forKey: "PYTHONHOME")
            variables["PYTHONUNBUFFERED"] = "1"
            return PythonEnvironment(directory: path, variables: variables)
        }
        throw DockError("Python environment not found:\n" + candidates.joined(separator: "\n") + "\n请先在服务工作目录或项目根目录创建 .venv 或 venv 并安装依赖。")
    }
}
