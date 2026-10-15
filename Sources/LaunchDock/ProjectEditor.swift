import AppKit
import SwiftUI
import LaunchDockCore

struct ProjectEditor: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var project: Project
    @State private var enabled: Set<ServiceRole>
    @State private var drafts: [ServiceRole: Service]
    init(model: AppModel, project: Project) {
        self.model = model
        _project = State(initialValue: project)
        _enabled = State(initialValue: Set(project.services.map(\.role)))
        _drafts = State(initialValue: Dictionary(uniqueKeysWithValues: ServiceRole.allCases.map { role in
            (role, project.services.first { $0.role == role } ?? Service(role: role, workingDirectory: project.directory, command: ""))
        }))
    }
    private var candidate: Project {
        var next = project
        next.name = next.name.trimmingCharacters(in: .whitespacesAndNewlines)
        next.services = ServiceRole.allCases.filter { enabled.contains($0) }.compactMap { drafts[$0] }
        return next
    }
    private var valid: Bool { (try? candidate.validate()) != nil }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(model.editing == nil ? "添加项目" : "编辑项目").font(.title2.bold()); Spacer() }.padding(20)
            Form {
                Section("项目") {
                    TextField("项目名称", text: $project.name)
                    if project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { hint("请输入项目名称。") }
                    directoryField("项目目录", path: $project.directory)
                    if project.directory.isEmpty { hint("请选择项目目录。") }
                }
                ForEach(ServiceRole.allCases) { role in
                    Section(role.title) {
                        Toggle("配置\(role.title)", isOn: Binding(get: { enabled.contains(role) }, set: { if $0 { enabled.insert(role) } else { enabled.remove(role) } }))
                        if enabled.contains(role) {
                            directoryField("工作目录", path: draftBinding(role, \.workingDirectory))
                            if drafts[role]?.workingDirectory.isEmpty != false { hint("请选择\(role.title)工作目录。") }
                            TextField("启动命令", text: draftBinding(role, \.command), prompt: Text("python app.py"))
                                .font(.system(.body, design: .monospaced))
                            if drafts[role]?.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { hint("请输入\(role.title)启动命令。") }
                        }
                    }
                }
                if enabled.isEmpty { hint("至少配置一个服务才能保存。") }
                Text("请提前在服务工作目录或项目根目录准备 .venv 或 venv，并安装依赖。仅支持前台非交互命令，请勿使用 &、nohup 或 daemon 模式。")
                    .font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { if model.save(candidate) { dismiss() } }.keyboardShortcut(.defaultAction).disabled(!valid || model.busy || model.loadFailed)
            }.padding(16)
        }.frame(width: 650, height: 650)
    }
    private func hint(_ text: String) -> some View { Text(text).font(.caption).foregroundStyle(.red) }
    private func draftBinding(_ role: ServiceRole, _ key: WritableKeyPath<Service, String>) -> Binding<String> {
        Binding(get: { drafts[role]?[keyPath: key] ?? "" }, set: { drafts[role]?[keyPath: key] = $0 })
    }
    private func directoryField(_ title: String, path: Binding<String>) -> some View {
        LabeledContent(title) {
            HStack {
                Text(path.wrappedValue.isEmpty ? "尚未选择" : path.wrappedValue)
                    .font(.system(.caption, design: .monospaced)).lineLimit(2).textSelection(.enabled)
                Spacer()
                Button("选择…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
                    if !path.wrappedValue.isEmpty { panel.directoryURL = URL(fileURLWithPath: path.wrappedValue) }
                    if panel.runModal() == .OK, let url = panel.url {
                        path.wrappedValue = url.path
                        if title == "项目目录" {
                            for role in ServiceRole.allCases where drafts[role]?.workingDirectory.isEmpty == true { drafts[role]?.workingDirectory = url.path }
                        }
                    }
                }.accessibilityLabel("选择\(title)")
            }
        }
    }
}
