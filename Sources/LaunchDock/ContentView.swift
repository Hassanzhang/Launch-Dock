import AppKit
import SwiftUI
import LaunchDockCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var runner: ServiceRunner
    @State private var deleting: Project?
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $model.selection) {
                    ForEach(model.projects) { project in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(project.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                .foregroundStyle(Color(nsColor: .labelColor))
                            summary(project)
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                        .listRowBackground(RoundedRectangle(cornerRadius: 8).fill(model.selection == project.id ? Color(nsColor: ServiceStatusPresentation.selectionBackground) : .clear))
                        .tag(project.id)
                        .contextMenu {
                            Button("编辑…") { model.edit(project) }
                                .disabled(project.services.contains { runner.isActive($0.id) } || model.busy)
                            Button("删除项目…", role: .destructive) { deleting = project }
                                .disabled(model.busy || model.loadFailed)
                            Button("上移") {
                                if let i = model.projects.firstIndex(where: { $0.id == project.id }), i > 0 { model.move(from: IndexSet(integer: i), to: i - 1) }
                            }.disabled(model.projects.first?.id == project.id || model.loadFailed || model.busy)
                            Button("下移") {
                                if let i = model.projects.firstIndex(where: { $0.id == project.id }), i < model.projects.count - 1 { model.move(from: IndexSet(integer: i), to: i + 2) }
                            }.disabled(model.projects.last?.id == project.id || model.loadFailed || model.busy)
                        }
                    }
                    .onMove { from, to in if !model.busy { model.move(from: from, to: to) } }
                }
                .overlay {
                    if model.projects.isEmpty { Text("还没有项目\n点击下方按钮添加").multilineTextAlignment(.center).foregroundStyle(.secondary) }
                }
                Divider()
                Button { model.edit(nil) } label: { Label("添加项目", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(.borderless).padding(16).disabled(model.loadFailed || model.busy)
            }
            .navigationTitle("项目")
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            if let project = model.projects.first(where: { $0.id == model.selection }) {
                ProjectDetail(project: project, model: model, runner: runner, delete: { deleting = project })
                    .id(project.id)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "terminal").font(.system(size: 42)).foregroundStyle(.secondary).accessibilityHidden(true)
                    Text("选择或添加一个项目").font(.title2)
                    Text("准备好 Python 虚拟环境，填写命令，即可独立启停服务。") .foregroundStyle(.secondary)
                    Button("添加项目…") { model.edit(nil) }.disabled(model.loadFailed || model.busy)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $model.showingEditor) {
            ProjectEditor(model: model, project: model.editing ?? Project())
        }
        .alert("LaunchDock", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("好") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .confirmationDialog("删除项目？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("停止服务并删除配置", role: .destructive) {
                if let project = deleting { Task { await model.delete(project) } }
                deleting = nil
            }
            Button("取消", role: .cancel) { deleting = nil }
        } message: { Text("将先停止该项目的服务，只删除 LaunchDock 配置，不删除项目文件。") }
    }
    private func summary(_ project: Project) -> some View {
        HStack(spacing: 12) {
            ForEach(ServiceRole.allCases) { role in
                if let service = project.services.first(where: { $0.role == role }) {
                    let status = ServiceStatusPresentation(state: runner.snapshot(for: service.id).state)
                    HStack(spacing: 6) {
                        Circle().fill(status.color).frame(width: 7, height: 7)
                        Text(role.title).font(.system(size: 12)).foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(role.title)：\(status.title)")
                }
            }
        }
    }
}

struct ProjectDetail: View {
    let project: Project
    @ObservedObject var model: AppModel
    @ObservedObject var runner: ServiceRunner
    var delete: () -> Void
    @State private var logSelection: UUID?
    private var selectedService: Service? { project.services.first { $0.id == logSelection } ?? project.services.first }
    @State private var cardsHeight: CGFloat = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(project.name).font(.title2.bold())
                    Text(project.directory).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2)
                }
                Spacer()
                Button("编辑…") { model.edit(project) }
                    .disabled(model.busy || model.loadFailed || project.services.contains { runner.isActive($0.id) })
                    .help("运行中的服务需要先停止才能编辑")
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                    .accessibilityLabel("删除项目").disabled(model.busy || model.loadFailed)
            }
            GeometryReader { geometry in
                Group {
                    if geometry.size.width >= 552 {
                        HStack(alignment: .top, spacing: 12) { cards(minimum: 270) }
                    } else {
                        VStack(spacing: 12) { cards(minimum: 0) }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { content in
                    Color.clear.preference(key: ServiceCardsHeight.self, value: content.size.height)
                })
            }
            .frame(height: cardsHeight)
            .onPreferenceChange(ServiceCardsHeight.self) { cardsHeight = $0 }
            if let service = selectedService {
                LogPanel(services: project.services, selection: Binding(get: { selectedService?.id ?? service.id }, set: { logSelection = $0 }), snapshot: runner.snapshot(for: service.id), clear: { runner.clearLog(service.id) })
            }
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    @ViewBuilder private func cards(minimum: CGFloat) -> some View {
        ForEach(ServiceRole.allCases) { role in
            if let service = project.services.first(where: { $0.role == role }) {
                ServiceCard(service: service, snapshot: runner.snapshot(for: service.id), active: runner.isActive(service.id), busy: model.busy) {
                    if runner.isActive(service.id) { runner.stop(service.id) } else { runner.start(service, projectDirectory: project.directory) }
                }.frame(minWidth: minimum, maxWidth: .infinity)
            } else {
                GroupBox(role.title) {
                    Button("添加\(role.title)…") { model.edit(project) }
                        .disabled(model.busy || model.loadFailed || project.services.contains { runner.isActive($0.id) })
                        .frame(maxWidth: .infinity, minHeight: 100)
                }.frame(minWidth: minimum, maxWidth: .infinity)
            }
        }
    }
}

private struct ServiceCardsHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Shared UI mapping keeps each service's sidebar dot and card status consistent.
struct ServiceStatusPresentation {
    let state: ServiceState
    var title: String {
        switch state {
        case .stopped: return "已停止"
        case .starting: return "正在启动"
        case .running: return "运行中"
        case .failed: return "启动失败"
        case .stopping: return "正在停止"
        }
    }
    var color: Color {
        switch state {
        case .stopped: return Color(red: 0.61, green: 0.64, blue: 0.69)
        case .running: return Color(red: 0.16, green: 0.62, blue: 0.44)
        case .starting, .stopping: return Color(red: 0.87, green: 0.63, blue: 0.26)
        case .failed: return Color(red: 0.85, green: 0.35, blue: 0.38)
        }
    }
    static let selectionBackground = NSColor(name: NSColor.Name("LaunchDockSidebarSelection")) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? NSColor(white: 0.23, alpha: 1) : NSColor(red: 0.88, green: 0.884, blue: 0.894, alpha: 1)
    }
}

private struct ServiceCard: View {
    let service: Service
    let snapshot: ServiceSnapshot
    let active: Bool
    let busy: Bool
    var action: () -> Void
    private var status: ServiceStatusPresentation { ServiceStatusPresentation(state: snapshot.state) }
    var body: some View {
        GroupBox(service.role.title) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(status.title, systemImage: "circle.fill").foregroundStyle(status.color)
                    if let pid = snapshot.pid { Text("PID \(pid)").font(.caption.monospaced()).foregroundStyle(.secondary) }
                    Spacer(minLength: 0)
                    if snapshot.state == .starting || snapshot.state == .stopping { ProgressView().controlSize(.small) }
                    Button(active ? "停止" : "启动", action: action)
                        .disabled(busy || snapshot.state == .starting || snapshot.state == .stopping)
                        .accessibilityLabel("\(service.role.title)\(active ? "停止" : "启动")")
                }
                Text(service.command).font(.system(.body, design: .monospaced)).lineLimit(1).help(service.command).textSelection(.enabled)
                Text(service.workingDirectory).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).help(service.workingDirectory)
                if let path = snapshot.environmentPath {
                    Text("环境：\(path)").font(.system(.caption, design: .monospaced)).lineLimit(1).help(path)
                }
                if service.role == .frontend, snapshot.state == .running, let url = snapshot.browserURL {
                    Link(destination: url) {
                        Label("打开前端 · \(url.absoluteString)", systemImage: "arrow.up.right.square")
                            .lineLimit(1).truncationMode(.middle)
                    }.help(url.absoluteString)
                        .accessibilityLabel("在浏览器打开前端：\(url.absoluteString)")
                }
                if let error = snapshot.error {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LogPanel: View {
    let services: [Service]
    @Binding var selection: UUID
    let snapshot: ServiceSnapshot
    var clear: () -> Void
    @State private var following = true
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("服务日志", selection: $selection) {
                    ForEach(services) { Text("\($0.role.title)日志").tag($0.id) }
                }.pickerStyle(.segmented).frame(maxWidth: 230)
                Spacer(minLength: 8)
                Toggle("跟随", isOn: $following).toggleStyle(.checkbox).help("取消勾选后暂停自动滚动")
                Button("复制") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(snapshot.log.text, forType: .string) }.disabled(snapshot.log.text.isEmpty)
                Button("清空", action: clear).disabled(snapshot.log.text.isEmpty)
            }.font(.system(size: 13))
                .padding(10)
                .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            LogOutputView(text: snapshot.log.text, serviceID: selection, following: following)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
