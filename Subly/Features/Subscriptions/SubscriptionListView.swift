import SwiftUI

struct SubscriptionListView: View {
    var repository: SubscriptionRepository
    var categories: CategoryRepository
    var templates: ServiceTemplateRepository
    var exchangeRates: ExchangeRateRepository
    var settings: AppSettingsRepository
    var commandService: SubscriptionCommandService
    var events: AppEventCenter?
    @State private var records: [SubscriptionRecord] = []
    @State private var isShowingAdd = false

    var body: some View {
        List {
            if records.isEmpty {
                EmptyStateView(title: "还没有订阅记录", systemImage: "rectangle.stack.badge.plus")
            } else {
                ForEach(records) { record in
                    NavigationLink {
                        SubscriptionDetailView(
                            viewModel: SubscriptionDetailViewModel(
                                id: record.id,
                                queryService: SubscriptionQueryService(repository: repository),
                                commandService: commandService
                            ),
                            aggregationQuery: ServiceAggregationQueryService(
                                subscriptions: repository,
                                exchangeRates: exchangeRates,
                                settings: settings
                            ),
                            aggregationCommand: ServiceAggregationCommandService(subscriptions: repository),
                            categoryRepository: categories,
                            onChanged: load
                        )
                    } label: {
                        HStack {
                            Text(record.serviceName)
                            Spacer()
                            CurrencyAmountText(money: record.effectiveMoney)
                        }
                    }
                }
            }
        }
        .navigationTitle("订阅")
        .toolbar {
            Button {
                isShowingAdd = true
            } label: {
                Label("新增订阅", systemImage: "plus")
            }
        }
        .sheet(isPresented: $isShowingAdd) {
            NavigationStack {
                SubscriptionFormView(
                    viewModel: SubscriptionFormViewModel(
                        commandService: commandService,
                        categoryRepository: categories,
                        templateRepository: templates
                    )
                ) {
                    isShowingAdd = false
                    load()
                }
            }
        }
        .task {
            load()
        }
        .onReceive(events?.publisher ?? NotificationCenter.default.publisher(for: Notification.Name("SublyUnusedSubscriptionListEvent"))) { _ in
            load()
        }
    }

    private func load() {
        records = ((try? repository.fetchAll()) ?? [])
    }
}

struct SubscriptionDetailView: View {
    @StateObject var viewModel: SubscriptionDetailViewModel
    var aggregationQuery: ServiceAggregationQueryService
    var aggregationCommand: ServiceAggregationCommandService
    var categoryRepository: CategoryRepository
    var onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation: Confirmation?
    @State private var isShowingEdit = false
    @State private var isShowingAggregation = false
    @State private var aggregationDetail: ServiceAggregationDetail?
    @State private var aggregationOptions: [ServiceAggregationOption] = []
    @State private var selectedServiceKey = ""

    var body: some View {
        List {
            if let record = viewModel.state?.record {
                Section("服务") {
                    LabeledContent("名称", value: record.serviceName)
                    LabeledContent("服务分组", value: record.serviceKey)
                    LabeledContent("状态", value: record.status.displayName)
                    LabeledContent("周期", value: record.billingCycle.displayName)
                    LabeledContent("金额") {
                        CurrencyAmountText(money: record.effectiveMoney)
                    }
                }

                Section("日期") {
                    DatePicker("操作日期", selection: $viewModel.actionDate, displayedComponents: .date)
                    LabeledContent("开始日期", value: record.startDate.formatted(date: .abbreviated, time: .omitted))
                    if let endDate = record.endDate {
                        LabeledContent("结束日期", value: endDate.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let nextBillingDate = record.nextBillingDate {
                        LabeledContent("下次扣费", value: nextBillingDate.formatted(date: .abbreviated, time: .omitted))
                    }
                }

                Section("恢复订阅") {
                    TextField("新订阅金额", text: $viewModel.restoreAmount)
                        .keyboardType(.decimalPad)
                    Button("恢复并创建新记录") {
                        confirmation = .restore
                    }
                }

                Section("服务聚合") {
                    if let aggregationDetail {
                        LabeledContent("显示名称", value: aggregationDetail.displayName)
                        LabeledContent("活跃段", value: "\(aggregationDetail.activeSegments.count)")
                        LabeledContent("历史段", value: "\(aggregationDetail.historySegments.count)")
                        if let cumulativeCost = aggregationDetail.cumulativeCost {
                            LabeledContent("累计支出") {
                                CurrencyAmountText(money: cumulativeCost)
                            }
                        } else if aggregationDetail.isIncomplete {
                            Text("累计支出需要补充汇率")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        loadAggregation(for: record)
                        isShowingAggregation = true
                    } label: {
                        Label("调整服务分组", systemImage: "arrow.triangle.branch")
                    }
                }

                Section {
                    Button("暂停订阅", role: .destructive) {
                        confirmation = .pause
                    }
                    Button("取消订阅", role: .destructive) {
                        confirmation = .cancel
                    }
                    Button("删除此条记录", role: .destructive) {
                        confirmation = .delete
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(SublyColor.danger)
                }
            }
        }
        .navigationTitle("订阅详情")
        .toolbar {
            if viewModel.state?.record != nil {
                Button {
                    isShowingEdit = true
                } label: {
                    Label("编辑", systemImage: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $isShowingEdit) {
            if let record = viewModel.state?.record {
                NavigationStack {
                    SubscriptionFormView(
                        viewModel: SubscriptionFormViewModel(
                            commandService: viewModel.commandService,
                            categoryRepository: categoryRepository,
                            existingRecord: record
                        )
                    ) {
                        isShowingEdit = false
                        viewModel.load()
                        onChanged()
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingAggregation) {
            NavigationStack {
                ServiceAggregationAdjustmentView(
                    options: aggregationOptions,
                    selectedServiceKey: $selectedServiceKey,
                    onMove: {
                        moveCurrentRecord()
                    },
                    onCreateNew: {
                        createNewGroup()
                    }
                )
            }
        }
        .confirmationDialog(confirmation?.title ?? "", isPresented: Binding(
            get: { confirmation != nil },
            set: { if !$0 { confirmation = nil } }
        ), titleVisibility: .visible) {
            if let confirmation {
                Button(confirmation.actionTitle, role: confirmation.role) {
                    apply(confirmation)
                    self.confirmation = nil
                }
            }
            Button("取消", role: .cancel) {
                confirmation = nil
            }
        } message: {
            Text(confirmation?.message ?? "")
        }
        .task {
            viewModel.load()
            if let record = viewModel.state?.record {
                loadAggregation(for: record)
            }
        }
    }

    private func apply(_ confirmation: Confirmation) {
        switch confirmation {
        case .pause:
            viewModel.pause()
        case .cancel:
            viewModel.cancel()
        case .restore:
            viewModel.restore()
        case .delete:
            viewModel.delete()
            onChanged()
            dismiss()
            return
        }
        onChanged()
    }

    private func loadAggregation(for record: SubscriptionRecord) {
        aggregationDetail = try? aggregationQuery.detail(serviceKey: record.serviceKey)
        aggregationOptions = ((try? aggregationQuery.options(excluding: record.id)) ?? [])
        if selectedServiceKey.isEmpty {
            selectedServiceKey = aggregationOptions.first?.serviceKey ?? ""
        }
    }

    private func moveCurrentRecord() {
        guard let record = viewModel.state?.record, !selectedServiceKey.isEmpty else { return }
        do {
            _ = try aggregationCommand.move(recordId: record.id, toExistingServiceKey: selectedServiceKey)
            isShowingAggregation = false
            viewModel.load()
            if let updated = viewModel.state?.record {
                loadAggregation(for: updated)
            }
            onChanged()
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func createNewGroup() {
        guard let record = viewModel.state?.record else { return }
        do {
            _ = try aggregationCommand.createNewGroup(for: record.id)
            isShowingAggregation = false
            viewModel.load()
            if let updated = viewModel.state?.record {
                selectedServiceKey = ""
                loadAggregation(for: updated)
            }
            onChanged()
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

struct ServiceAggregationAdjustmentView: View {
    var options: [ServiceAggregationOption]
    @Binding var selectedServiceKey: String
    var onMove: () -> Void
    var onCreateNew: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("移动到已有服务") {
                if options.isEmpty {
                    Text("暂无其他服务分组")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("目标分组", selection: $selectedServiceKey) {
                        ForEach(options) { option in
                            Text("\(option.displayName) · \(option.recordCount) 条").tag(option.serviceKey)
                        }
                    }
                    Button {
                        onMove()
                    } label: {
                        Label("移动到所选分组", systemImage: "arrow.right")
                    }
                    .disabled(selectedServiceKey.isEmpty)
                }
            }

            Section("拆分") {
                Button {
                    onCreateNew()
                } label: {
                    Label("创建新的服务分组", systemImage: "square.stack.3d.up")
                }
            }
        }
        .navigationTitle("调整服务分组")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") { dismiss() }
            }
        }
    }
}

private enum Confirmation {
    case pause
    case cancel
    case restore
    case delete

    var title: String {
        switch self {
        case .pause: "暂停订阅"
        case .cancel: "取消订阅"
        case .restore: "恢复订阅"
        case .delete: "删除记录"
        }
    }

    var message: String {
        switch self {
        case .pause: "将写入结束日期，并停止未来扣费提醒。"
        case .cancel: "将写入取消日期，并停止未来扣费提醒。"
        case .restore: "会创建一条新的订阅记录，历史记录不会被覆盖。"
        case .delete: "只删除当前这条历史记录，不影响同服务的其他记录。"
        }
    }

    var actionTitle: String {
        switch self {
        case .pause: "确认暂停"
        case .cancel: "确认取消"
        case .restore: "确认恢复"
        case .delete: "确认删除"
        }
    }

    var role: ButtonRole? {
        switch self {
        case .delete, .pause, .cancel: .destructive
        case .restore: nil
        }
    }
}

struct SubscriptionFormView: View {
    @StateObject var viewModel: SubscriptionFormViewModel
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("服务") {
                if !viewModel.isEditing {
                    Menu {
                        Button("手动创建") {
                            viewModel.selectTemplate(serviceKey: nil)
                        }
                        ForEach(viewModel.templates) { template in
                            Button {
                                viewModel.selectTemplate(serviceKey: template.serviceKey)
                            } label: {
                                Label(template.serviceName, systemImage: template.iconStyle.systemName)
                            }
                        }
                    } label: {
                        LabeledContent("常用模板", value: viewModel.selectedTemplateName)
                    }
                }
                TextField("服务名称", text: $viewModel.serviceName)
                Picker("分类", selection: Binding(
                    get: { viewModel.selectedCategoryId ?? viewModel.categories.first?.id },
                    set: { viewModel.selectedCategoryId = $0 }
                )) {
                    ForEach(viewModel.categories) { category in
                        Label(category.name, systemImage: category.iconName).tag(Optional(category.id))
                    }
                }
            }

            Section("金额") {
                TextField("标价金额", text: $viewModel.listedAmount)
                    .keyboardType(.decimalPad)
                Picker("标价币种", selection: $viewModel.listedCurrency) {
                    ForEach(CurrencyCode.allCases) { currency in
                        Text(currency.rawValue).tag(currency)
                    }
                }
                Toggle("记录实际支付金额", isOn: $viewModel.hasPaidAmount)
                if viewModel.hasPaidAmount {
                    TextField("实际支付金额", text: $viewModel.paidAmount)
                        .keyboardType(.decimalPad)
                    Picker("实际支付币种", selection: $viewModel.paidCurrency) {
                        ForEach(CurrencyCode.allCases) { currency in
                            Text(currency.rawValue).tag(currency)
                        }
                    }
                }
            }

            Section("周期") {
                Picker("订阅周期", selection: $viewModel.billingCycle) {
                    Text("周付").tag(BillingCycle.weekly)
                    Text("月付").tag(BillingCycle.monthly)
                    Text("季付").tag(BillingCycle.quarterly)
                    Text("半年付").tag(BillingCycle.halfYearly)
                    Text("年付").tag(BillingCycle.yearly)
                    Text("自定义天数").tag(BillingCycle.customDays(viewModel.customCycleDays))
                    Text("一次性购买").tag(BillingCycle.oneTime)
                    Text("试用期").tag(BillingCycle.trial(days: nil))
                }
                if case .customDays = viewModel.billingCycle {
                    Stepper("每 \(viewModel.customCycleDays) 天", value: $viewModel.customCycleDays, in: 1...999)
                }
                DatePicker("开始日期", selection: $viewModel.startDate, displayedComponents: .date)
                Toggle("设置结束日期", isOn: $viewModel.hasEndDate)
                if viewModel.hasEndDate {
                    DatePicker("结束日期", selection: $viewModel.endDate, displayedComponents: .date)
                }
                Toggle("手动下次扣费日", isOn: $viewModel.hasManualNextBillingDate)
                if viewModel.hasManualNextBillingDate {
                    DatePicker("下次扣费日", selection: $viewModel.nextBillingDate, displayedComponents: .date)
                }
            }

            Section("状态与提醒") {
                Picker("状态", selection: $viewModel.status) {
                    ForEach(SubscriptionStatus.allCases) { status in
                        Text(status.displayName).tag(status)
                    }
                }
                Toggle("提醒", isOn: $viewModel.reminderEnabled)
                Stepper("提前 \(viewModel.reminderDaysBefore) 天", value: $viewModel.reminderDaysBefore, in: 0...30)
            }

            Section("补充信息") {
                TextField("支付方式", text: $viewModel.paymentMethod)
                TextField("官网或管理链接", text: $viewModel.websiteURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                TextField("备注", text: $viewModel.note, axis: .vertical)
                    .lineLimit(3...6)
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(SublyColor.danger)
                }
            }
        }
        .navigationTitle(viewModel.isEditing ? "编辑订阅" : "新增订阅")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    do {
                        _ = try viewModel.save()
                        onSaved()
                    } catch {
                        viewModel.errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .task {
            viewModel.load()
        }
    }
}
