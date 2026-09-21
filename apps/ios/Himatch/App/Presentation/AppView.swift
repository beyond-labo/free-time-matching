import AuthenticationServices
import ComposableArchitecture
import SwiftUI

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        ZStack {
            switch store.route {
            case .onboarding:
                OnboardingView(store: store)
            case .profile:
                ProfileSetupView(store: store)
            case .main:
                MainTabView(store: store)
            case .deletionAccepted:
                DeletionAcceptedView(store: store)
            }

            if store.isLoading {
                Color.black.opacity(0.12).ignoresSafeArea()
                ProgressView("更新中…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel("更新中")
            }
        }
        .task { store.send(.task) }
        .alert(
            "お知らせ",
            isPresented: Binding(
                get: { store.alertMessage != nil },
                set: { if !$0 { store.send(.dismissAlert) } }
            )
        ) {
            Button("OK") { store.send(.dismissAlert) }
        } message: {
            Text(store.alertMessage ?? "")
        }
    }
}

private struct OnboardingView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer(minLength: 32)
                Label("ひまっち", systemImage: "calendar.badge.clock")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.indigo)

                Text("暇な時間を預けて、友達と遊ぶ予定を決めよう。")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 16) {
                    PrivacyPoint(icon: "lock.fill", title: "暇時間は初期設定で非公開", detail: "友達のホームに常時表示されません。")
                    PrivacyPoint(icon: "checkmark.circle.fill", title: "参加OKした時間だけ共有", detail: "選んだ候補時間と表示名が主催者に伝わります。")
                    PrivacyPoint(icon: "bubble.left.and.bubble.right", title: "場所や接続先は普段の連絡手段で", detail: "アプリでは時間と参加者を決めるところまで。")
                }

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = []
                } onCompletion: { result in
                    switch result {
                    case let .success(authorization):
                        let credential = authorization.credential as? ASAuthorizationAppleIDCredential
                        let code = credential?.authorizationCode?.base64EncodedString()
                        store.send(.appleAuthorizationCompleted(code))
                    case .failure:
                        store.send(.appleAuthorizationCompleted(nil))
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(minHeight: 50)
                .accessibilityHint("Apple認証を開始します")

#if DEBUG
                Button {
                    store.send(.startDemo)
                } label: {
                    Label("デモデータで試す", systemImage: "hammer.fill")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                Text("デモは実際のApple認証・通知・データ削除を行いません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
#endif

                HStack(spacing: 18) {
                    Text("利用規約")
                    Text("プライバシー")
                    Text("問い合わせ")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                Text("日本向け・18歳以上の招待利用を想定した初版です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct PrivacyPoint: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .frame(width: 28, height: 28)
                .foregroundStyle(.indigo)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProfileSetupView: View {
    let store: StoreOf<AppFeature>
    private let icons = ["sun.max.fill", "leaf.fill", "gamecontroller.fill", "figure.run"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "表示名",
                        text: Binding(
                            get: { store.profileName },
                            set: { store.send(.profileNameChanged($0)) }
                        )
                    )
                    .textInputAutocapitalization(.never)
                    Text("\(store.profileName.count)/20文字")
                        .font(.caption)
                        .foregroundStyle(store.profileName.count > 20 ? .red : .secondary)
                } header: {
                    Text("表示名")
                } footer: {
                    Text("本名を使う必要はありません。本人確認は内部IDで行います。")
                }

                Section("アイコン") {
                    HStack {
                        ForEach(icons, id: \.self) { icon in
                            Button {
                                store.send(.profileIconChanged(icon))
                            } label: {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .frame(width: 50, height: 50)
                                    .background(store.profileIcon == icon ? Color.indigo.opacity(0.18) : Color.clear)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("アイコン \(icon)")
                            .accessibilityAddTraits(store.profileIcon == icon ? .isSelected : [])
                        }
                    }
                }

                Section {
                    Button("プロフィールを保存") { store.send(.saveProfileTapped) }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(store.profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.profileName.count > 20)
                }
            }
            .navigationTitle("プロフィール設定")
        }
    }
}

private struct MainTabView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        TabView(
            selection: Binding(
                get: { store.selectedTab },
                set: { store.send(.selectTab($0)) }
            )
        ) {
            HomeView(store: store)
                .tabItem { Label("ホーム", systemImage: "clock") }
                .tag(AppFeature.State.Tab.home)
            FriendsView(store: store)
                .tabItem { Label("友達", systemImage: "person.2") }
                .tag(AppFeature.State.Tab.friends)
            SettingsView(store: store)
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(AppFeature.State.Tab.settings)
        }
    }
}

private struct HomeView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let snapshot = store.snapshot {
                        if !snapshot.invitations.isEmpty || !snapshot.requests.isEmpty {
                            Button {
                                store.send(.showInbox(true))
                            } label: {
                                HStack {
                                    Label("要対応があります", systemImage: "bell.badge.fill")
                                    Spacer()
                                    Text("\(snapshot.invitations.count + snapshot.requests.count)件")
                                    Image(systemName: "chevron.right")
                                }
                                .padding()
                                .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }

                        SectionTitle("今後の予定")
                        if snapshot.plans.isEmpty {
                            EmptyCard(icon: "calendar", text: "確定した予定はまだありません")
                        } else {
                            ForEach(snapshot.plans) { plan in PlanCard(plan: plan) }
                        }

                        SectionTitle("あなたの暇")
                        if snapshot.availability.isEmpty {
                            EmptyCard(icon: "clock.badge.plus", text: "空いている時間を登録しましょう")
                        } else {
                            ForEach(snapshot.availability) { slot in
                                AvailabilityCard(slot: slot) {
                                    store.send(.removeAvailability(slot.id))
                                }
                            }
                        }

                        if !snapshot.hostings.isEmpty {
                            SectionTitle("募集中")
                            ForEach(snapshot.hostings) { hosting in
                                HostingCard(hosting: hosting) {
                                    store.send(.confirmHosting(hosting.id))
                                }
                            }
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 220)
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button {
                        store.send(.showAvailabilityEditor(true))
                    } label: {
                        Label("暇を登録", systemImage: "plus")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    Button {
                        store.send(.showHostingEditor(true))
                    } label: {
                        Text("友達を誘う").frame(minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("ホーム")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.send(.showInbox(true)) } label: { Image(systemName: "bell") }
                        .accessibilityLabel("お知らせ")
                }
            }
            .sheet(isPresented: Binding(get: { store.availabilityEditorPresented }, set: { store.send(.showAvailabilityEditor($0)) })) {
                AvailabilityEditorView(store: store)
            }
            .sheet(isPresented: Binding(get: { store.hostingEditorPresented }, set: { store.send(.showHostingEditor($0)) })) {
                HostingEditorView(store: store)
            }
            .sheet(isPresented: Binding(get: { store.inboxPresented }, set: { store.send(.showInbox($0)) })) {
                InboxView(store: store)
            }
        }
    }
}

private struct FriendsView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        NavigationStack {
            List {
                Section("受信した申請") {
                    if let requests = store.snapshot?.requests.filter({ $0.direction == .incoming }), !requests.isEmpty {
                        ForEach(requests) { request in
                            HStack {
                                FriendLabel(friend: request.person)
                                Spacer()
                                Button("承認") { store.send(.acceptRequest(request.id)) }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    } else {
                        Text("受信中の申請はありません").foregroundStyle(.secondary)
                    }
                }

                Section("友達") {
                    if let friends = store.snapshot?.friends, !friends.isEmpty {
                        ForEach(friends) { friend in
                            NavigationLink {
                                FriendDetailView(store: store, friend: friend)
                            } label: {
                                FriendLabel(friend: friend)
                            }
                        }
                    } else {
                        Text("友達を追加すると、遊びに誘えます").foregroundStyle(.secondary)
                    }
                }

                if let code = store.snapshot?.inviteCode {
                    Section("招待コード") {
                        LabeledContent("あなたのコード", value: code.value)
                        Text("有効期限: \(code.expiresAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("友達")
            .toolbar {
                Button { store.send(.showAddFriend(true)) } label: { Image(systemName: "person.badge.plus") }
                    .accessibilityLabel("友達を追加")
            }
            .sheet(isPresented: Binding(get: { store.addFriendPresented }, set: { store.send(.showAddFriend($0)) })) {
                AddFriendView(store: store)
            }
        }
    }
}

private struct SettingsView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section("アカウント") {
                    if let snapshot = store.snapshot {
                        LabeledContent("表示名", value: snapshot.profileName)
                    }
                    Button("ログアウト") { store.send(.logoutTapped) }
                    Button("アカウントを削除", role: .destructive) { store.send(.showDeleteConfirmation(true)) }
                }

                Section("通知") {
                    Toggle("招待", isOn: Binding(get: { store.invitationNotifications }, set: { _ in store.send(.toggleInvitationNotifications) }))
                    Toggle("回答の更新", isOn: Binding(get: { store.responseNotifications }, set: { _ in store.send(.toggleResponseNotifications) }))
                    Toggle("確定・取消", isOn: Binding(get: { store.planNotifications }, set: { _ in store.send(.togglePlanNotifications) }))
                    Toggle("暇登録のリマインダー", isOn: Binding(get: { store.reminderEnabled }, set: { _ in store.send(.toggleReminder) }))
                    Text("通知を許可しなくても、受信箱からすべての操作を行えます。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("安全") {
                    LabeledContent("ブロックしたユーザー", value: "\(store.snapshot?.blocked.count ?? 0)人")
                }

                Section("サポート") {
                    Label("問い合わせ", systemImage: "envelope")
                    Label("利用規約", systemImage: "doc.text")
                    Label("プライバシーポリシー", systemImage: "hand.raised")
                    Label("コミュニティルール", systemImage: "person.2.badge.gearshape")
                    Text("公開URLと実際の問い合わせ先はTestFlight提出前に設定します。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("アプリ情報") {
                    LabeledContent("バージョン", value: "0.1.0")
                    LabeledContent("運営", value: "beyond-labo")
                }
            }
            .navigationTitle("設定")
            .confirmationDialog(
                "アカウントを削除しますか？",
                isPresented: Binding(get: { store.deleteConfirmationPresented }, set: { store.send(.showDeleteConfirmation($0)) }),
                titleVisibility: .visible
            ) {
                Button("削除を開始", role: .destructive) { store.send(.deleteAccountTapped) }
            } message: {
                Text("暇・友達・回答を削除し、主催予定を取消、参加予定から離脱します。処理中でもアプリへのアクセスは停止します。")
            }
        }
    }
}

private struct AvailabilityEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let store: StoreOf<AppFeature>

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "開始",
                    selection: Binding(get: { store.availabilityStart }, set: { store.send(.availabilityStartChanged($0)) }),
                    in: Date()...Date().addingTimeInterval(14 * 24 * 60 * 60),
                    displayedComponents: [.date, .hourAndMinute]
                )
                Picker("長さ", selection: Binding(get: { store.availabilityDurationHours }, set: { store.send(.availabilityDurationChanged($0)) })) {
                    ForEach([1, 2, 3], id: \.self) { Text("\($0)時間").tag($0) }
                }
                Picker("遊びたいこと", selection: Binding(get: { store.availabilityCategory }, set: { store.send(.availabilityCategoryChanged($0)) })) {
                    Text("未選択").tag(ActivityCategory?.none)
                    ForEach(ActivityCategory.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
                Picker("公開設定", selection: Binding(get: { store.availabilityVisibility }, set: { store.send(.availabilityVisibilityChanged($0)) })) {
                    ForEach(AvailabilityVisibility.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Section {
                    Text(visibilityExplanation(store.availabilityVisibility))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("暇を登録")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("登録") { store.send(.saveAvailabilityTapped) } }
            }
        }
    }
}

private struct HostingEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let store: StoreOf<AppFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section("① 内容と時間") {
                    Picker("開催形態", selection: Binding(get: { store.hostingMode }, set: { store.send(.hostingModeChanged($0)) })) {
                        ForEach(HostingMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    if store.hostingMode == .offline {
                        Picker("エリア", selection: Binding(get: { store.hostingArea }, set: { store.send(.hostingAreaChanged($0)) })) {
                            ForEach(HostingArea.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    }
                    Picker("カテゴリ", selection: Binding(get: { store.hostingCategory }, set: { store.send(.hostingCategoryChanged($0)) })) {
                        Text("未選択").tag(ActivityCategory?.none)
                        ForEach(ActivityCategory.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    DatePicker("候補開始", selection: Binding(get: { store.hostingStart }, set: { store.send(.hostingStartChanged($0)) }))
                    Picker("必要時間", selection: Binding(get: { store.hostingDurationHours }, set: { store.send(.hostingDurationChanged($0)) })) {
                        ForEach([1, 2, 3], id: \.self) { Text("\($0)時間").tag($0) }
                    }
                }
                Section("② 友達") {
                    ForEach(store.snapshot?.friends ?? []) { friend in
                        Button { store.send(.toggleFriend(friend.id)) } label: {
                            HStack {
                                FriendLabel(friend: friend)
                                Spacer()
                                if store.selectedFriendIDs.contains(friend.id) { Image(systemName: "checkmark.circle.fill") }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("③ 確認") {
                    Text("選んだ友達のうち、時間が重なる人に招待します。非公開設定の友達については、招待の配信有無は表示されません。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("友達を誘う")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("募集を開始") { store.send(.createHostingTapped) }
                        .disabled(store.selectedFriendIDs.isEmpty)
                }
            }
        }
    }
}

private struct InboxView: View {
    @Environment(\.dismiss) private var dismiss
    let store: StoreOf<AppFeature>

    var body: some View {
        NavigationStack {
            List {
                Section("要対応") {
                    ForEach(store.snapshot?.invitations ?? []) { invitation in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(invitation.category?.rawValue ?? "遊びの招待", systemImage: "envelope.open")
                            Text(invitation.candidateRange.start.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("参加OKすると、選んだ時間と表示名が主催者に伝わります。")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("この時間なら参加OK") { store.send(.acceptInvitation(invitation.id)) }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 6)
                    }
                    ForEach(store.snapshot?.requests ?? []) { request in
                        HStack {
                            Text("\(request.person.displayName)さんから友達申請")
                            Spacer()
                            Button("承認") { store.send(.acceptRequest(request.id)) }
                        }
                    }
                }
                Section("進行中") {
                    ForEach(store.snapshot?.hostings ?? []) { hosting in
                        Text("\(hosting.category?.rawValue ?? "遊び")を募集中")
                    }
                }
                Section("終了") {
                    ForEach(store.snapshot?.plans ?? []) { plan in
                        Text("\(plan.interval.start.formatted(date: .abbreviated, time: .shortened)) に確定")
                    }
                }
            }
            .navigationTitle("お知らせ")
            .toolbar { Button("閉じる") { dismiss() } }
        }
    }
}

private struct AddFriendView: View {
    @Environment(\.dismiss) private var dismiss
    let store: StoreOf<AppFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section("招待コードを入力") {
                    TextField("HIMA-0000", text: Binding(get: { store.inviteCodeInput }, set: { store.send(.inviteCodeChanged($0.uppercased())) }))
                        .textInputAutocapitalization(.characters)
                    Text("無効・期限切れ・ブロックなどの違いは表示しません。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("プロフィールを確認") {
                        store.send(.operationFailed("デモでは招待コード HIMA-2741 を共有できます。実検索はBackend接続後に利用できます。"))
                    }
                    .disabled(store.inviteCodeInput.isEmpty)
                }
            }
            .navigationTitle("友達を追加")
            .toolbar { Button("閉じる") { dismiss() } }
        }
    }
}

private struct FriendDetailView: View {
    let store: StoreOf<AppFeature>
    let friend: FriendProfile

    var body: some View {
        List {
            Section {
                FriendLabel(friend: friend)
                    .font(.title3.bold())
            }
            Section {
                Button("友達を誘う") { store.send(.selectTab(.home)); store.send(.showHostingEditor(true)) }
                Button("通報") { store.send(.showReport(true)) }
                Button("ブロック", role: .destructive) { store.send(.setBlockTarget(friend)) }
                Button("友達を解除", role: .destructive) { store.send(.removeFriend(friend.id)) }
            }
            Text("友達の暇一覧や、友達の友達は表示しません。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .navigationTitle(friend.displayName)
        .sheet(isPresented: Binding(get: { store.reportPresented }, set: { store.send(.showReport($0)) })) {
            ReportView(store: store, targetName: friend.displayName)
        }
        .confirmationDialog(
            "\(friend.displayName)さんをブロックしますか？",
            isPresented: Binding(
                get: { store.blockTarget?.id == friend.id },
                set: { if !$0 { store.send(.setBlockTarget(nil)) } }
            ),
            titleVisibility: .visible
        ) {
            Button("ブロック", role: .destructive) { store.send(.confirmBlock(friend.id)) }
        } message: {
            Text("友達関係を解除し、新しい申請・招待を止めます。関連する未確定回答と予定も更新されます。解除しても友達関係は復活しません。")
        }
    }
}

private struct ReportView: View {
    @Environment(\.dismiss) private var dismiss
    let store: StoreOf<AppFeature>
    let targetName: String

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("対象", value: targetName)
                Picker("理由", selection: Binding(get: { store.reportReason }, set: { store.send(.reportReasonChanged($0)) })) {
                    ForEach(ReportReason.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                TextField("補足（任意・500文字以内）", text: Binding(get: { store.reportNote }, set: { store.send(.reportNoteChanged($0)) }), axis: .vertical)
                    .lineLimit(4...8)
                Text("運営が確認します。通報者情報は相手に表示されません。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("通報")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("送信") { store.send(.submitReportTapped) } }
            }
        }
    }
}

private struct DeletionAcceptedView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
            Text("削除を受け付けました").font(.title2.bold())
            if case let .accepted(reference) = store.snapshot?.deletionStatus {
                Text("受付番号: \(reference)").font(.body.monospaced())
            }
            Text("アプリへのアクセスは停止しました。Apple連携の失効や関連データの削除は再試行可能な処理として進めます。")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("登録画面へ戻る") { store.send(.logoutTapped) }
                .buttonStyle(.bordered)
        }
        .padding(32)
    }
}

private struct AvailabilityCard: View {
    let slot: AvailabilitySlot
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(slot.category?.rawValue ?? "暇", systemImage: "clock.fill")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("この暇を削除", role: .destructive, action: onDelete)
                } label: { Image(systemName: "ellipsis") }
            }
            Text(dateRange(slot.interval))
            Label(slot.visibility.title, systemImage: slot.visibility == .privateUntilAccepted ? "lock.fill" : "person.crop.circle.badge.checkmark")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct HostingCard: View {
    let hosting: Hosting
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hosting.category?.rawValue ?? "遊びの募集").font(.headline)
            Text("\(hosting.mode.rawValue)・\(Int(hosting.requiredDuration / 3600))時間")
                .foregroundStyle(.secondary)
            Text("参加OKの回答があると表示されます。配信人数は表示しません。")
                .font(.caption).foregroundStyle(.secondary)
            Button("この日時で確定") { onConfirm() }
                .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct PlanCard: View {
    let plan: ConfirmedPlan
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(plan.category?.rawValue ?? "遊ぶ予定", systemImage: "calendar.badge.checkmark")
                .font(.headline)
            Text(dateRange(plan.interval))
            Text("参加者: \(plan.participants.map(\.displayName).joined(separator: "、"))")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("集合場所や接続先は、普段の連絡手段で確認してください。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct FriendLabel: View {
    let friend: FriendProfile
    var body: some View {
        Label {
            Text(friend.displayName)
        } icon: {
            Image(systemName: friend.icon)
                .frame(width: 32, height: 32)
                .background(Color.indigo.opacity(0.12), in: Circle())
        }
    }
}

private struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View { Text(title).font(.title3.bold()).padding(.top, 4) }
}

private struct EmptyCard: View {
    let icon: String
    let text: String
    var body: some View {
        Label(text, systemImage: icon)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private func dateRange(_ interval: TimeIntervalRange) -> String {
    "\(interval.start.formatted(date: .abbreviated, time: .shortened)) 〜 \(interval.end.formatted(date: .omitted, time: .shortened))"
}

private func visibilityExplanation(_ visibility: AvailabilityVisibility) -> String {
    switch visibility {
    case .privateUntilAccepted:
        "システムが重なりを確認して招待を届けます。参加OKするまでは主催者に暇時間を表示しません。"
    case .shareOnHosting:
        "友達が募集を始めたとき、募集と重なる暇時間を主催者に表示します。自動で参加OKにはなりません。"
    }
}

#Preview {
    let scenario = HimatchPrototypeScenario()
    AppView(
        store: Store(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.himatchClient = scenario.client()
        }
    )
}
