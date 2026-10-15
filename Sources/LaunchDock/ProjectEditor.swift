import AppKit
import SwiftUI
import LaunchDockCore

struct ProjectEditor: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var project: Project
    @State private var enabled: Set<ServiceRole>
    @State private var drafts: [ServiceRole: Service]
    private enum Field: Hashable {
        case name, directory, workingDirectory(ServiceRole), command(ServiceRole)
    }
    @FocusState private var focusedField: Field?
    @State private var previousField: Field?
    @State private var touched: Set<Field> = []
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
    private var saveDisabledReason: String? {
        if model.loadFailed { return "配置读取失败，请先处理原配置文件。" }
        if model.busy { return "正在处理项目，请稍候。" }
        do { try candidate.validate(); return nil }
        catch { return error.localizedDescription }
    }
    var body: some View {
        VStack(spacing: 0) {
            Text(model.editing == nil ? "添加项目" : "编辑项目")
                .font(.headline).frame(maxWidth: .infinity).padding(.top, 20)
            Form {
                Section("项目") {
                    TextField("项目名称", text: $project.name).focused($focusedField, equals: .name)
                    if touched.contains(.name), project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { hint("请输入项目名称。") }
                    directoryField("项目目录", path: $project.directory, field: .directory)
                    if touched.contains(.directory), project.directory.isEmpty { hint("请选择项目目录。") }
                }
                ForEach(ServiceRole.allCases) { role in
                    Section {
                        Toggle("配置\(role.title)", isOn: Binding(get: { enabled.contains(role) }, set: {
                            focusedField = nil
                            if $0 { enabled.insert(role) } else { enabled.remove(role) }
                        }))
                        if enabled.contains(role) {
                            VStack(alignment: .leading, spacing: 10) {
                                directoryField("工作目录", path: draftBinding(role, \.workingDirectory), field: .workingDirectory(role))
                                if touched.contains(.workingDirectory(role)), drafts[role]?.workingDirectory.isEmpty != false { hint("请选择\(role.title)工作目录。") }
                                TextField("启动命令", text: draftBinding(role, \.command), prompt: Text("python app.py"))
                                    .font(.system(size: 13, design: .monospaced))
                                    .focused($focusedField, equals: .command(role))
                                if touched.contains(.command(role)), drafts[role]?.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { hint("请输入\(role.title)启动命令。") }
                            }.padding(.leading, 16).padding(.vertical, 4)
                        }
                    }
                }
            }.formStyle(.grouped).fixedSize(horizontal: false, vertical: true)
            Label {
                Text("请在服务目录或项目根目录准备 .venv / venv 并安装依赖。仅支持前台非交互命令，不支持 &、nohup、daemon。")
            } icon: { Image(systemName: "info.circle") }
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.bottom, 16)
            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    focusedField = nil
                    guard saveDisabledReason == nil else { return }
                    if model.save(candidate) { dismiss() }
                }.keyboardShortcut(.defaultAction)
                    .disabled(saveDisabledReason != nil)
                    .help(saveDisabledReason ?? "保存项目配置")
            }.padding(16)
        }.frame(width: 650)
            .onChange(of: focusedField) { field in
                if let previousField { touched.insert(previousField) }
                previousField = field
            }
    }
    private func hint(_ text: String) -> some View { Text(text).font(.system(size: 11)).foregroundStyle(.red) }
    private func draftBinding(_ role: ServiceRole, _ key: WritableKeyPath<Service, String>) -> Binding<String> {
        Binding(get: { drafts[role]?[keyPath: key] ?? "" }, set: { drafts[role]?[keyPath: key] = $0 })
    }
    private func directoryField(_ title: String, path: Binding<String>, field: Field) -> some View {
        LabeledContent(title) {
            HStack {
                Text(path.wrappedValue.isEmpty ? "尚未选择" : path.wrappedValue)
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(2).help(path.wrappedValue).textSelection(.enabled)
                Spacer()
                Button("选择…") {
                    focusedField = nil
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
                    if !path.wrappedValue.isEmpty { panel.directoryURL = URL(fileURLWithPath: path.wrappedValue) }
                    if panel.runModal() == .OK, let url = panel.url {
                        path.wrappedValue = url.path
                        if field == .directory {
                            for role in ServiceRole.allCases where drafts[role]?.workingDirectory.isEmpty == true { drafts[role]?.workingDirectory = url.path }
                        }
                    }
                    touched.insert(field)
                }.buttonStyle(.borderless).accessibilityLabel("选择\(title)")
            }
        }
    }
}
