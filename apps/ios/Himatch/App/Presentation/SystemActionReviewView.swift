import SwiftUI

/// Continues the same system operation; never replays it through the demo store.
struct SystemActionReviewView: View {
    let operationID: UUID
    let service: SystemActionService
    var onCompleted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var currentID: UUID?
    @State private var record: SystemActionRecord?
    @State private var input: SystemActionInput?
    @State private var friends: [FriendProfile] = []
    @State private var hostings: [Hosting] = []
    @State private var message: String?
    @State private var isWorking = false
    @State private var prepared: PreparedSystemAction?
    @State private var metadataNeeded = false
    @State private var confirmationPresented = false

    private var isRetryOnly: Bool { record?.state == .sending || record?.state == .resultUnknown }

    var body: some View {
        NavigationStack {
            Form {
                if let input {
                    Section("引き継いだ操作") {
                        Text(title(input.kind))
                        if let start = input.start, let end = input.end {
                            Text(dateText(start, zone: input.timeZoneIdentifier))
                            Text(dateText(end, zone: input.timeZoneIdentifier))
                        }
                    }
                    if !isRetryOnly {
                        if input.kind != .cancelHosting {
                            Section("日時") {
                                DatePicker("開始", selection: dateBinding(\.start), displayedComponents: [.date, .hourAndMinute])
                                DatePicker("終了", selection: dateBinding(\.end), displayedComponents: [.date, .hourAndMinute])
                            }
                            .environment(\.timeZone, TimeZone(identifier: input.timeZoneIdentifier) ?? .current)
                        }
                        if input.kind == .createHosting {
                            Section("開催条件") {
                                Picker("開催形態", selection: modeBinding) {
                                    Text("選んでください").tag(Optional<HostingMode>.none)
                                    ForEach(HostingMode.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                                }
                                if input.mode == .offline {
                                    Picker("エリア", selection: areaBinding) {
                                        ForEach(HostingArea.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                                    }
                                }
                                Picker("カテゴリ", selection: categoryBinding) {
                                    Text("未選択").tag(Optional<ActivityCategory>.none)
                                    ForEach(ActivityCategory.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                                }
                            }
                            Section("誘う友達") {
                                ForEach(friends) { friend in
                                    Toggle(friend.displayName, isOn: Binding(
                                        get: { self.input?.friendIDs.contains(friend.id) == true },
                                        set: { selected in
                                            var ids = self.input?.friendIDs ?? []
                                            if selected { if !ids.contains(friend.id) { ids.append(friend.id) } }
                                            else { ids.removeAll { $0 == friend.id } }
                                            self.input?.friendIDs = ids
                                        }
                                    ))
                                }
                            }
                        }
                        if input.kind == .cancelHosting {
                            Section("取り消す募集") {
                                ForEach(hostings) { hosting in
                                    Button {
                                        self.input?.hostingID = hosting.id
                                        self.input?.start = hosting.candidateRange.start
                                        self.input?.end = hosting.candidateRange.end
                                    } label: {
                                        Label(dateText(hosting.candidateRange.start, zone: input.timeZoneIdentifier),
                                              systemImage: input.hostingID == hosting.id ? "checkmark.circle.fill" : "circle")
                                    }
                                }
                            }
                        }
                        if metadataNeeded {
                            Section("統合後の本人の暇") {
                                Text("重なる暇の属性を、統合後の範囲に適用します。")
                                Picker("暇のカテゴリ", selection: metadataCategoryBinding) {
                                    Text("未選択").tag(Optional<ActivityCategory>.none)
                                    ForEach(ActivityCategory.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                                }
                                Picker("公開設定", selection: metadataVisibilityBinding) {
                                    ForEach(AvailabilityVisibility.allCases, id: \.self) { Text($0.title).tag($0) }
                                }
                            }
                        }
                    }
                    if let message { Section { Text(message) } }
                    Section {
                        Button(isRetryOnly ? "同じ操作の結果を確認・再試行" : "続ける") { Task { await continueAction() } }
                            .disabled(isWorking)
                        Button("この操作を破棄", role: .destructive) {
                            Task {
                                do {
                                    try await service.discard(operationID: currentID ?? operationID)
                                    onCompleted()
                                    dismiss()
                                } catch { message = "操作記録を削除できませんでした。" }
                            }
                        }.disabled(isWorking)
                    }
                    if isWorking { ProgressView() }
                } else if let message {
                    Text(message)
                } else { ProgressView("入力を復元しています…") }
            }
            .navigationTitle("Siri から続ける")
            .toolbar { Button("閉じる") { dismiss() } }
            .task { await load() }
            .confirmationDialog("操作を確認", isPresented: $confirmationPresented, titleVisibility: .visible) {
                Button(record?.input.kind == .cancelHosting ? "募集を取り消す" : "選んだ友達全員へ招待する", role: record?.input.kind == .cancelHosting ? .destructive : nil) {
                    Task { await executePrepared() }
                }
            } message: {
                if let prepared { Text(confirmationText(prepared)) }
            }
        }
    }

    @MainActor
    private func load() async {
        do {
            guard let record = try await service.record(operationID: operationID) else {
                onCompleted(); dismiss(); return
            }
            self.record = record; input = record.input; currentID = record.operationID
            if record.input.kind == .createHosting { friends = try await service.queryFriends().friends }
            if record.input.kind == .cancelHosting { hostings = try await service.queryHostings().hostings }
        } catch { message = "サインイン状態と操作を確認してください。" }
    }

    @MainActor
    private func continueAction() async {
        guard let input else { return }
        isWorking = true; defer { isWorking = false }
        do {
            if isRetryOnly {
                await handle(try await service.retry(operationID: currentID ?? operationID)); return
            }
            let id = try await service.updateInput(operationID: currentID ?? operationID, input: input)
            currentID = id
            switch try await service.prepare(input, operationID: id) {
            case let .ready(value):
                prepared = value
                if value.requiresConfirmation { confirmationPresented = true }
                else { await handle(try await service.execute(value)) }
            case .needsMetadataSelection:
                metadataNeeded = true
                self.input?.availabilityMetadata = .init()
                message = "統合後のカテゴリと公開設定を選んでください。"
            case .needsAuthentication:
                message = "サインインとプロフィール設定を完了してください。"
            case .needsDisambiguation:
                message = "対象と開催形態を選んでください。"
            case let .invalidInput(reason): message = reason
            }
        } catch { message = "操作を完了できませんでした。入力は保持しています。" }
    }

    @MainActor
    private func executePrepared() async {
        guard let prepared else { return }
        isWorking = true; defer { isWorking = false }
        do { await handle(try await service.execute(prepared, confirmedFingerprint: prepared.confirmationFingerprint)) }
        catch { message = "操作を完了できませんでした。入力は保持しています。" }
    }

    @MainActor
    private func handle(_ outcome: ActionOutcome) async {
        switch outcome {
        case .completed: onCompleted(); dismiss()
        case .resultUnknown:
            record = try? await service.record(operationID: currentID ?? operationID)
            message = "結果を確認できません。同じ操作IDで安全に再試行できます。"
        case .conflict:
            record = try? await service.record(operationID: currentID ?? operationID)
            message = "状態が変わりました。内容を確認してから続けてください。"
        case .blockedByHosting: message = "募集中の時間は削除できません。先に募集を取り消してください。"
        case .needsForeground: message = "内容をもう一度確認してください。"
        case let .failed(reason): message = reason
        }
    }

    private func confirmationText(_ operation: PreparedSystemAction) -> String {
        let value = operation.input
        let dates = [value.start, value.end].compactMap { $0 }.map { dateText($0, zone: value.timeZoneIdentifier) }.joined(separator: " 〜 ")
        let targets = value.friendIDs.compactMap { id in friends.first { $0.id == id }?.displayName }.joined(separator: "、")
        return [dates, value.mode?.rawValue, value.category?.rawValue, value.area?.rawValue, targets.isEmpty ? nil : targets].compactMap { $0 }.joined(separator: "\n")
    }

    private func dateText(_ date: Date, zone: String) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: zone); formatter.dateFormat = "yyyy年M月d日 H:mm zzz"
        return formatter.string(from: date)
    }

    private func title(_ kind: SystemActionKind) -> String {
        switch kind {
        case .addAvailability: "暇を登録"
        case .subtractAvailability: "暇を削除"
        case .createHosting: "友達を誘う"
        case .cancelHosting: "募集を取り消す"
        }
    }
    private func dateBinding(_ path: WritableKeyPath<SystemActionInput, Date?>) -> Binding<Date> {
        Binding(get: { input?[keyPath: path] ?? Date() }, set: { input?[keyPath: path] = $0 })
    }
    private var modeBinding: Binding<HostingMode?> {
        Binding(get: { input?.mode }, set: { input?.mode = $0 })
    }
    private var areaBinding: Binding<HostingArea?> {
        Binding(get: { input?.area ?? .discussLater }, set: { input?.area = $0 })
    }
    private var categoryBinding: Binding<ActivityCategory?> {
        Binding(get: { input?.category }, set: { input?.category = $0 })
    }
    private var metadataCategoryBinding: Binding<ActivityCategory?> {
        Binding(get: { input?.availabilityMetadata?.category }, set: { input?.availabilityMetadata?.category = $0 })
    }
    private var metadataVisibilityBinding: Binding<AvailabilityVisibility> {
        Binding(get: { input?.availabilityMetadata?.visibility ?? .privateUntilAccepted }, set: { input?.availabilityMetadata?.visibility = $0 })
    }
}
