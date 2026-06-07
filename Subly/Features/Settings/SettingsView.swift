import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject var viewModel: SettingsViewModel
    var categories: CategoryRepository?
    var subscriptions: SubscriptionRepository?
    var events: AppEventCenter?
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var pendingRestoreData: Data?
    @State private var isShowingRestorePreview = false
    @State private var isShowingOverwriteWarning = false

    var body: some View {
        List {
            Section("显示") {
                Picker("主显示货币", selection: Binding(
                    get: { viewModel.settings.primaryDisplayCurrency },
                    set: { viewModel.setPrimaryCurrency($0) }
                )) {
                    Text("CNY").tag(CurrencyCode.CNY)
                    Text("USD").tag(CurrencyCode.USD)
                }
                Toggle("跟随系统外观", isOn: Binding(
                    get: { viewModel.settings.followSystemAppearance },
                    set: { viewModel.setFollowSystemAppearance($0) }
                ))
            }
            Section("提醒") {
                LabeledContent("通知权限", value: notificationStatusText)
                if viewModel.notificationPermissionStatus != .authorized && viewModel.notificationPermissionStatus != .provisional {
                    Button {
                        viewModel.requestNotificationPermission()
                    } label: {
                        Label("请求通知权限", systemImage: "bell.badge")
                    }
                }
                Toggle("默认提醒", isOn: Binding(
                    get: { viewModel.settings.defaultReminderConfig.isEnabled },
                    set: { viewModel.setDefaultReminder(enabled: $0, daysBefore: viewModel.settings.defaultReminderConfig.daysBefore) }
                ))
                Stepper("提前 \(viewModel.settings.defaultReminderConfig.daysBefore) 天", value: Binding(
                    get: { viewModel.settings.defaultReminderConfig.daysBefore },
                    set: { viewModel.setDefaultReminder(enabled: viewModel.settings.defaultReminderConfig.isEnabled, daysBefore: $0) }
                ), in: 0...30)
            }
            Section("分类") {
                if let categories, let subscriptions {
                    NavigationLink {
                        CategoryManagementView(viewModel: CategoryManagementViewModel(
                            categories: categories,
                            subscriptions: subscriptions,
                            events: events
                        ))
                    } label: {
                        Label("分类管理", systemImage: "square.grid.2x2")
                    }
                }
            }
            Section("数据") {
                Button {
                    isExportingBackup = viewModel.prepareBackup()
                } label: {
                    Label("备份到 iCloud Drive", systemImage: "square.and.arrow.up")
                }
                Button {
                    isImportingBackup = true
                } label: {
                    Label("从备份恢复", systemImage: "arrow.clockwise.icloud")
                }
                if let lastBackupAt = viewModel.settings.lastBackupAt {
                    LabeledContent("最后备份", value: lastBackupAt.formatted(date: .abbreviated, time: .shortened))
                }
                NavigationLink {
                    DataManagementPlaceholderView()
                } label: {
                    Label("数据管理", systemImage: "externaldrive.badge.gearshape")
                }
            }
            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(SublyColor.danger)
                }
            }
        }
        .navigationTitle("设置")
        .task {
            viewModel.load()
        }
        .onReceive(events?.publisher ?? NotificationCenter.default.publisher(for: Notification.Name("SublyUnusedSettingsEvent"))) { _ in
            viewModel.load()
        }
        .fileExporter(
            isPresented: $isExportingBackup,
            document: BackupJSONDocument(data: viewModel.backupData ?? Data()),
            contentType: .json,
            defaultFilename: "Subly-Backup-\(Date().formatted(.iso8601.year().month().day()))"
        ) { result in
            if case .failure(let error) = result {
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $isImportingBackup, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    let shouldStopAccessing = url.startAccessingSecurityScopedResource()
                    defer {
                        if shouldStopAccessing { url.stopAccessingSecurityScopedResource() }
                    }
                    let data = try Data(contentsOf: url)
                    if viewModel.previewRestore(data: data) {
                        pendingRestoreData = data
                        isShowingRestorePreview = true
                    }
                } catch {
                    viewModel.errorMessage = error.localizedDescription
                }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog("恢复备份", isPresented: $isShowingRestorePreview, titleVisibility: .visible) {
            Button("合并恢复") {
                if let pendingRestoreData {
                    viewModel.restore(data: pendingRestoreData, mode: .merge)
                }
                pendingRestoreData = nil
            }
            Button("覆盖恢复", role: .destructive) {
                isShowingOverwriteWarning = true
            }
            Button("取消", role: .cancel) {
                pendingRestoreData = nil
            }
        } message: {
            if let preview = viewModel.restorePreview {
                Text("备份时间：\(preview.createdAt.formatted(date: .abbreviated, time: .shortened))；记录数：\(preview.recordCount)；数据版本：\(preview.dataVersion)。默认建议使用合并恢复。")
            }
        }
        .alert("确认覆盖恢复", isPresented: $isShowingOverwriteWarning) {
            Button("确认覆盖", role: .destructive) {
                if let pendingRestoreData {
                    viewModel.restore(data: pendingRestoreData, mode: .overwrite)
                }
                pendingRestoreData = nil
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("覆盖恢复会在校验通过后替换当前核心数据。写入失败时会尝试回滚到恢复前数据。")
        }
    }

    private var notificationStatusText: String {
        switch viewModel.notificationPermissionStatus {
        case .notDetermined: "未请求"
        case .authorized: "已开启"
        case .denied: "已拒绝"
        case .provisional: "临时允许"
        case .unknown: "未知"
        }
    }
}

struct CategoryManagementView: View {
    @StateObject var viewModel: CategoryManagementViewModel
    @State private var isShowingEditor = false
    @State private var archiveCandidate: CategoryManagementRowState?

    var body: some View {
        List {
            Section {
                ForEach(viewModel.rows) { row in
                    HStack(spacing: SublySpacing.md) {
                        Image(systemName: row.iconName)
                            .frame(width: 32, height: 32)
                            .background(SublyColor.surface, in: RoundedRectangle(cornerRadius: SublyCornerRadius.card))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.name)
                                .font(.body.weight(.medium))
                            Text(categorySubtitle(row))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if row.isArchived {
                            Text("已归档")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.beginEditing(row)
                        isShowingEditor = true
                    }
                    .swipeActions {
                        if !row.isArchived {
                            Button("归档", role: .destructive) {
                                archiveCandidate = row
                            }
                        }
                    }
                }
                .onMove(perform: viewModel.move)
            } footer: {
                Text("已用于订阅的分类会保留历史展示；不再使用时可归档。")
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(SublyColor.danger)
                }
            }
        }
        .navigationTitle("分类管理")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.resetEditor()
                    isShowingEditor = true
                } label: {
                    Label("新增分类", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            NavigationStack {
                CategoryEditorView(viewModel: viewModel) {
                    isShowingEditor = false
                }
            }
        }
        .confirmationDialog("归档分类", isPresented: Binding(
            get: { archiveCandidate != nil },
            set: { if !$0 { archiveCandidate = nil } }
        ), titleVisibility: .visible) {
            if let archiveCandidate {
                Button("确认归档", role: .destructive) {
                    viewModel.archive(id: archiveCandidate.id)
                    self.archiveCandidate = nil
                }
            }
            Button("取消", role: .cancel) {
                archiveCandidate = nil
            }
        } message: {
            Text(archiveCandidate.map { $0.usageCount > 0 ? "该分类已有 \($0.usageCount) 条订阅使用。归档后不会出现在新增订阅默认列表，但历史记录仍可展示。" : "归档后不会出现在新增订阅默认列表。" } ?? "")
        }
        .task {
            viewModel.load()
        }
    }

    private func categorySubtitle(_ row: CategoryManagementRowState) -> String {
        var parts: [String] = []
        parts.append(row.isSystem ? "系统分类" : "自定义分类")
        parts.append("使用 \(row.usageCount) 条")
        parts.append(row.colorToken)
        return parts.joined(separator: " · ")
    }
}

struct CategoryEditorView: View {
    @ObservedObject var viewModel: CategoryManagementViewModel
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("分类") {
                TextField("名称", text: $viewModel.editor.name)
                Picker("图标", selection: $viewModel.editor.iconName) {
                    ForEach(categoryIconChoices, id: \.self) { icon in
                        Label(icon, systemImage: icon).tag(icon)
                    }
                }
                Picker("颜色", selection: $viewModel.editor.colorToken) {
                    ForEach(categoryColorChoices, id: \.self) { color in
                        Text(color).tag(color)
                    }
                }
            }
        }
        .navigationTitle(viewModel.editingCategoryId == nil ? "新增分类" : "编辑分类")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                    onDone()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    viewModel.saveEditor()
                    dismiss()
                    onDone()
                }
            }
        }
    }
}

struct DataManagementPlaceholderView: View {
    var body: some View {
        List {
            Section {
                Label("删除记录和清空数据会在后续版本集中放在这里", systemImage: "externaldrive.badge.gearshape")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("数据管理")
    }
}

private let categoryIconChoices = [
    "sparkles",
    "play.tv",
    "gamecontroller",
    "wrench.and.screwdriver",
    "icloud",
    "book",
    "music.note.tv",
    "leaf",
    "creditcard",
    "square.grid.2x2"
]

private let categoryColorChoices = [
    "custom",
    "category0",
    "category1",
    "category2",
    "category3",
    "category4",
    "category5",
    "category6",
    "category7",
    "category8",
    "category9"
]

struct BackupJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
