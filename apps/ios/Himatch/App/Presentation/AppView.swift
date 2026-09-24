import AuthenticationServices
import ComposableArchitecture
import SwiftUI

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        ZStack {
            switch store.route {
            case .launching:
                ProgressView("サインイン状態を確認中…")
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
                    .padding(HimatchSpacing.l)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HimatchRadius.card, style: .continuous))
                    .accessibilityLabel("更新中")
            }
        }
        .tint(HimatchColor.accent)
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
    @State private var rawNonce: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HimatchSpacing.l) {
                Spacer(minLength: HimatchSpacing.l)
                IconAvatar(systemImage: "calendar.badge.clock", size: 72)
                VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
                    Text("ひまっち")
                        .font(HimatchFont.screenTitle)
                        .foregroundStyle(HimatchColor.accent)
                    Text("暇な時間を預けて、友達と遊ぶ予定を決めよう。")
                        .font(HimatchFont.hero)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: HimatchSpacing.m) {
                    InfoRow(icon: "lock.fill", title: "暇時間は初期設定で非公開", detail: "友達のホームに常時表示されません。")
                    InfoRow(icon: "checkmark.circle.fill", title: "参加OKした時間だけ共有", detail: "選んだ候補時間と表示名が主催者に伝わります。")
                    InfoRow(icon: "bubble.left.and.bubble.right", title: "場所や接続先は普段の連絡手段で", detail: "アプリでは時間と参加者を決めるところまで。")
                }
                .himatchCard()

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = []
                    do {
                        let nonce = try AppleNonce.generate()
                        rawNonce = nonce
                        request.nonce = AppleNonce.sha256(nonce)
                    } catch {
                        rawNonce = nil
                        store.send(.appleAuthorizationFailed(error.localizedDescription))
                    }
                } onCompletion: { result in
                    switch result {
                    case let .success(authorization):
                        do {
                            store.send(.appleAuthorizationCompleted(try appleCredential(authorization, rawNonce: rawNonce)))
                        } catch {
                            store.send(.appleAuthorizationFailed(error.localizedDescription))
                        }
                        rawNonce = nil
                    case let .failure(error):
                        rawNonce = nil
                        let cancelled = (error as? ASAuthorizationError)?.code == .canceled
                        store.send(.appleAuthorizationFailed(cancelled ? nil : error.localizedDescription))
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(minHeight: HimatchMetrics.primaryButtonHeight)
                .clipShape(RoundedRectangle(cornerRadius: HimatchRadius.control, style: .continuous))
                .accessibilityHint("Apple認証を開始します")

#if DEBUG
                VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
                    Button {
                        store.send(.startDemo)
                    } label: {
                        Label("デモデータで試す", systemImage: "hammer.fill")
                    }
                    .buttonStyle(.himatchSecondary)
                    Text("デモは実際のApple認証・通知・データ削除を行いません。")
                        .font(HimatchFont.caption)
                        .foregroundStyle(.secondary)
                }
#endif

                VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
                    HStack(spacing: HimatchSpacing.m) {
                        Text("利用規約")
                        Text("プライバシー")
                        Text("問い合わせ")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    Text("日本向け・18歳以上の招待利用を想定した初版です。")
                        .font(HimatchFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(HimatchSpacing.l)
        }
        .background(HimatchColor.background)
    }
}

private struct ProfileSetupView: View {
    let store: StoreOf<AppFeature>
    private let icons = PresetProfileIcon.allCases

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
                    .frame(minHeight: HimatchMetrics.minTapTarget)
                    Text("\(store.profileName.count)/20文字")
                        .font(HimatchFont.caption)
                        .foregroundStyle(store.profileName.count > 20 ? HimatchColor.danger : .secondary)
                    if let message = store.profileValidationMessage {
                        Label(message, systemImage: "exclamationmark.circle.fill")
                            .font(HimatchFont.caption)
                            .foregroundStyle(HimatchColor.danger)
                    }
                } header: {
                    Text("表示名")
                } footer: {
                    Text("本名を使う必要はありません。本人確認は内部IDで行います。")
                }

                Section("アイコン") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: HimatchSpacing.s)], spacing: HimatchSpacing.s) {
                        ForEach(icons, id: \.self) { preset in
                            let icon = preset.rawValue
                            let isSelected = store.profileIcon == icon
                            Button {
                                store.send(.profileIconChanged(icon))
                            } label: {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .foregroundStyle(HimatchColor.accent)
                                    .frame(width: 56, height: 56)
                                    .background(Circle().fill(isSelected ? HimatchColor.tint(HimatchColor.accent) : Color.clear))
                                    .overlay(Circle().strokeBorder(isSelected ? HimatchColor.accent : HimatchColor.separator, lineWidth: isSelected ? 2 : 1))
                                    .overlay(alignment: .bottomTrailing) {
                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.body)
                                                .foregroundStyle(.white, HimatchColor.accent)
                                                .accessibilityHidden(true)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("アイコン \(icon)")
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, HimatchSpacing.xs)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("プロフィールを保存") { store.send(.saveProfileTapped) }
                    .buttonStyle(.himatchPrimary)
                    .disabled(store.profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.profileName.count > 20)
                    .padding(.horizontal, HimatchSpacing.m)
                    .padding(.vertical, HimatchSpacing.s)
                    .background(.bar)
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
                .tabItem { Label("ホーム", systemImage: "calendar") }
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

private struct FriendsView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        NavigationStack {
            List {
                Section("受信した申請") {
                    if let requests = store.snapshot?.requests.filter({ $0.direction == .incoming }), !requests.isEmpty {
                        ForEach(requests) { request in
                            HStack(spacing: HimatchSpacing.xs) {
                                FriendLabel(friend: request.person)
                                Spacer()
                                Button("拒否") { store.send(.rejectRequest(request.id)) }
                                    .buttonStyle(.bordered)
                                    .disabled(store.isLoading)
                                Button("承認") { store.send(.acceptRequest(request.id)) }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(store.isLoading)
                            }
                            .frame(minHeight: HimatchMetrics.minTapTarget)
                        }
                    } else {
                        EmptyRowText("受信中の申請はありません")
                    }
                }

                Section("送信した申請") {
                    if let requests = store.snapshot?.requests.filter({ $0.direction == .outgoing }), !requests.isEmpty {
                        ForEach(requests) { request in
                            HStack {
                                FriendLabel(friend: request.person)
                                Spacer()
                                Button("取消") { store.send(.cancelRequest(request.id)) }
                                    .buttonStyle(.bordered)
                                    .disabled(store.isLoading)
                            }
                            .frame(minHeight: HimatchMetrics.minTapTarget)
                        }
                    } else {
                        EmptyRowText("送信中の申請はありません")
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
                        EmptyRowText("友達を追加すると、遊びに誘えます")
                    }
                }

                if let code = store.snapshot?.inviteCode, !code.value.isEmpty {
                    Section("招待コード") {
                        VStack(alignment: .leading, spacing: HimatchSpacing.xxs) {
                            Text("あなたのコード")
                                .font(HimatchFont.caption)
                                .foregroundStyle(.secondary)
                            Text(code.value)
                                .font(.title3.monospaced().weight(.semibold))
                                .textSelection(.enabled)
                            Text("有効期限: \(code.expiresAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(HimatchFont.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        ShareLink(item: code.value) {
                            Label("コードを共有", systemImage: "square.and.arrow.up")
                        }
                        Button("コードを再発行", role: .destructive) {
                            store.send(.rotateInviteCode)
                        }
                        .disabled(store.isLoading)
                    }
                } else if !store.isDemo {
                    Section("招待コード") {
                        ProgressView("コードを発行しています")
                        Button("再読み込み") { store.send(.reloadFriendships) }
                    }
                }
            }
            .navigationTitle("友達")
            .toolbar {
                Button { store.send(.reloadFriendships) } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("友達情報を再読み込み")
                    .disabled(store.isLoading || store.isDemo)
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
                        HStack(spacing: HimatchSpacing.s) {
                            IconAvatar(systemImage: snapshot.profileIcon, size: 40)
                            LabeledContent("表示名", value: snapshot.profileName)
                        }
                    }
                    Button { store.send(.logoutTapped) } label: {
                        Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    Button(role: .destructive) { store.send(.showDeleteConfirmation(true)) } label: {
                        Label("アカウントを削除", systemImage: "person.crop.circle.badge.xmark")
                    }
                }

                Section {
                    Toggle(isOn: Binding(get: { store.invitationNotifications }, set: { _ in store.send(.toggleInvitationNotifications) })) {
                        Label("招待", systemImage: "envelope")
                    }
                    Toggle(isOn: Binding(get: { store.responseNotifications }, set: { _ in store.send(.toggleResponseNotifications) })) {
                        Label("回答の更新", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Toggle(isOn: Binding(get: { store.planNotifications }, set: { _ in store.send(.togglePlanNotifications) })) {
                        Label("確定・取消", systemImage: "calendar.badge.checkmark")
                    }
                    Toggle(isOn: Binding(get: { store.reminderEnabled }, set: { _ in store.send(.toggleReminder) })) {
                        Label("暇登録のリマインダー", systemImage: "bell")
                    }
                } header: {
                    Text("通知")
                } footer: {
                    Text("通知を許可しなくても、受信箱からすべての操作を行えます。")
                }

                Section("安全") {
                    LabeledContent {
                        Text("\(store.snapshot?.blocked.count ?? 0)人")
                    } label: {
                        Label("ブロックしたユーザー", systemImage: "hand.raised.slash")
                    }
                }

                Section {
                    Label("問い合わせ", systemImage: "envelope")
                    Label("利用規約", systemImage: "doc.text")
                    Label("プライバシーポリシー", systemImage: "hand.raised")
                    Label("コミュニティルール", systemImage: "person.2.badge.gearshape")
                } header: {
                    Text("サポート")
                } footer: {
                    Text("公開URLと実際の問い合わせ先はTestFlight提出前に設定します。")
                }

                Section("アプリ情報") {
                    LabeledContent("バージョン", value: "0.1.0")
                    LabeledContent("運営", value: "beyond-labo")
                }
            }
            .navigationTitle("設定")
            .sheet(isPresented: Binding(
                get: { store.deleteConfirmationPresented },
                set: { store.send(.showDeleteConfirmation($0)) }
            )) {
                AccountDeletionView(store: store)
            }
        }
    }
}

struct HostingEditorView: View {
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
                        let isSelected = store.selectedFriendIDs.contains(friend.id)
                        Button { store.send(.toggleFriend(friend.id)) } label: {
                            HStack {
                                FriendLabel(friend: friend)
                                Spacer()
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? HimatchColor.accent : HimatchColor.secondaryText)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: HimatchMetrics.minTapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

struct InboxView: View {
    @Environment(\.dismiss) private var dismiss
    let store: StoreOf<AppFeature>

    var body: some View {
        NavigationStack {
            List {
                Section("要対応") {
                    ForEach(store.snapshot?.invitations ?? []) { invitation in
                        VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
                            Label(invitation.category?.rawValue ?? "遊びの招待", systemImage: "envelope.open")
                                .font(HimatchFont.cardTitle)
                            Text(invitation.candidateRange.start.formatted(date: .abbreviated, time: .shortened))
                                .font(HimatchFont.supporting).foregroundStyle(.secondary)
                            Text("参加OKすると、選んだ時間と表示名が主催者に伝わります。")
                                .font(HimatchFont.caption).foregroundStyle(.secondary)
                            Button("この時間なら参加OK") { store.send(.acceptInvitation(invitation.id)) }
                                .buttonStyle(.borderedProminent)
                                .frame(minHeight: HimatchMetrics.minTapTarget)
                        }
                        .padding(.vertical, HimatchSpacing.xxs)
                    }
                    ForEach(store.snapshot?.requests ?? []) { request in
                        HStack {
                            Label("\(request.person.displayName)さんから友達申請", systemImage: "person.badge.plus")
                            Spacer()
                            Button("承認") { store.send(.acceptRequest(request.id)) }
                                .buttonStyle(.bordered)
                        }
                        .frame(minHeight: HimatchMetrics.minTapTarget)
                    }
                    if (store.snapshot?.invitations.isEmpty ?? true) && (store.snapshot?.requests.isEmpty ?? true) {
                        EmptyRowText("対応が必要なお知らせはありません")
                    }
                }
                Section("進行中") {
                    ForEach(store.snapshot?.hostings ?? []) { hosting in
                        Label("\(hosting.category?.rawValue ?? "遊び")を募集中", systemImage: "megaphone")
                    }
                }
                Section("終了") {
                    ForEach(store.snapshot?.plans ?? []) { plan in
                        Label("\(plan.interval.start.formatted(date: .abbreviated, time: .shortened)) に確定", systemImage: "calendar.badge.checkmark")
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
                Section {
                    TextField("HIMA-ABCD-EFGH-JKMP-QRST", text: Binding(get: { store.inviteCodeInput }, set: { store.send(.inviteCodeChanged($0.uppercased())) }))
                        .textInputAutocapitalization(.characters)
                        .font(.body.monospaced())
                        .frame(minHeight: HimatchMetrics.minTapTarget)
                } header: {
                    Text("招待コードを入力")
                } footer: {
                    Text("無効・期限切れ・ブロックなどの違いは表示しません。")
                }
                Section {
                    Button("プロフィールを確認") {
                        store.send(.resolveInviteCode)
                    }
                    .frame(minHeight: HimatchMetrics.minTapTarget)
                    .disabled(store.inviteCodeInput.isEmpty || store.isLoading)
                }
                if let candidate = store.friendCandidate {
                    Section("申請する相手") {
                        FriendLabel(friend: candidate)
                        Text("この相手に友達申請を送信します。相手が承認すると友達になります。")
                            .font(HimatchFont.caption)
                            .foregroundStyle(.secondary)
                        Button("友達申請を送る") { store.send(.sendFriendRequest) }
                            .buttonStyle(.himatchPrimary)
                            .disabled(store.isLoading)
                    }
                }
            }
            .navigationTitle("友達を追加")
            .toolbar { Button("閉じる") { dismiss() } }
        }
    }
}

private struct FriendDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let store: StoreOf<AppFeature>
    let friend: FriendProfile
    @State private var removeConfirmationPresented = false

    var body: some View {
        List {
            Section {
                HStack(spacing: HimatchSpacing.s) {
                    IconAvatar(systemImage: friend.icon, size: 56)
                    Text(friend.displayName).font(HimatchFont.sectionTitle)
                }
                .padding(.vertical, HimatchSpacing.xxs)
                .accessibilityElement(children: .combine)
            }
            Section {
                Button { store.send(.selectTab(.home)); store.send(.showHostingEditor(true)) } label: {
                    Label("友達を誘う", systemImage: "megaphone")
                }
                Button { store.send(.showReport(true)) } label: {
                    Label("通報", systemImage: "exclamationmark.bubble")
                }
                Button(role: .destructive) { store.send(.setBlockTarget(friend)) } label: {
                    Label("ブロック", systemImage: "hand.raised.slash")
                }
                Button(role: .destructive) { removeConfirmationPresented = true } label: {
                    Label("友達を解除", systemImage: "person.badge.minus")
                }
            } footer: {
                Text("友達の暇一覧や、友達の友達は表示しません。")
            }
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
        .confirmationDialog(
            "\(friend.displayName)さんとの友達関係を解除しますか？",
            isPresented: $removeConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("友達を解除", role: .destructive) { store.send(.removeFriend(friend.id)) }
                .disabled(store.isLoading)
        } message: {
            Text("新しい招待と共有は停止します。確定済みの予定は自動では削除されません。")
        }
        .onChange(of: store.snapshot?.friends.contains(where: { $0.id == friend.id }) ?? false) {
            _, remainsFriend in
            if !remainsFriend { dismiss() }
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
    @State private var rawNonce: String?

    var body: some View {
        ScrollView {
            VStack(spacing: HimatchSpacing.l) {
                IconAvatar(systemImage: statusIcon, size: 88, tint: statusColor)
                VStack(spacing: HimatchSpacing.s) {
                    if store.accountDeletionReceipt == nil {
                        Text("削除結果の確認が必要です").font(HimatchFont.hero)
                    } else if store.accountDeletionReceipt?.status == .actionRequired {
                        Text("削除手続きに対応が必要です").font(HimatchFont.hero)
                    } else if store.accountDeletionReceipt?.status == .accepted
                                || store.accountDeletionReceipt?.status == .processing {
                        Text("削除手続きを処理中です").font(HimatchFont.hero)
                    } else {
                        Text("アカウントを削除しました").font(HimatchFont.hero)
                    }
                    if let receipt = store.accountDeletionReceipt {
                        Text("受付番号: \(receipt.reference)")
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                        if let message = receipt.message { Text(message).foregroundStyle(.secondary) }
                    } else if let message = store.deletionRecoveryMessage {
                        Text(message).foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
                Text("通常画面へのアクセスは停止しました。削除完了後に再登録する場合はAppleでサインインしてください。")
                    .font(HimatchFont.supporting)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .himatchCard()
                if store.accountDeletionReceipt == nil, store.authenticationSession != nil {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = []
                        do {
                            let nonce = try AppleNonce.generate()
                            rawNonce = nonce
                            request.nonce = AppleNonce.sha256(nonce)
                        } catch {
                            rawNonce = nil
                            store.send(.appleAuthorizationFailed(error.localizedDescription))
                        }
                    } onCompletion: { result in
                        switch result {
                        case let .success(authorization):
                            do {
                                store.send(.deleteAccountAuthorized(try appleCredential(authorization, rawNonce: rawNonce)))
                            } catch {
                                store.send(.appleAuthorizationFailed(error.localizedDescription))
                            }
                        case let .failure(error):
                            let cancelled = (error as? ASAuthorizationError)?.code == .canceled
                            store.send(.appleAuthorizationFailed(cancelled ? nil : error.localizedDescription))
                        }
                        rawNonce = nil
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(minHeight: HimatchMetrics.primaryButtonHeight)
                    .clipShape(RoundedRectangle(cornerRadius: HimatchRadius.control, style: .continuous))
                } else if store.accountDeletionReceipt?.status == .completed {
                    Button("登録画面へ戻る") { store.send(.logoutTapped) }
                        .buttonStyle(.himatchSecondary)
                }
            }
            .padding(HimatchSpacing.xl)
        }
        .background(HimatchColor.background)
    }

    private var statusIcon: String {
        guard let status = store.accountDeletionReceipt?.status else { return "exclamationmark.shield.fill" }
        switch status {
        case .accepted, .processing: return "clock.badge.checkmark.fill"
        case .completed: return "checkmark.circle.fill"
        case .actionRequired: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        guard let status = store.accountDeletionReceipt?.status else { return HimatchColor.attention }
        switch status {
        case .accepted, .processing: return HimatchColor.attention
        case .completed: return HimatchColor.plan
        case .actionRequired: return HimatchColor.attention
        }
    }
}

private struct AccountDeletionView: View {
    @Environment(\.dismiss) private var dismiss
    let store: StoreOf<AppFeature>
    @State private var rawNonce: String?

    var body: some View {
        NavigationStack {
            List {
                Section("削除されるもの") {
                    Label("プロフィール、暇、友達、未確定の回答", systemImage: "trash")
                    Label("主催中の予定は取消され、参加予定から離脱します", systemImage: "calendar.badge.minus")
                    Label("この端末のセッションを停止します", systemImage: "iphone.slash")
                }
                Section {
                    Text("既に他の人が閲覧した情報やスクリーンショットまでは削除できません。削除理由や追加の連絡先は必要ありません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("本人確認") {
                    Text("削除を確定するため、Appleで再認証してください。")
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = []
                        do {
                            let nonce = try AppleNonce.generate()
                            rawNonce = nonce
                            request.nonce = AppleNonce.sha256(nonce)
                        } catch {
                            rawNonce = nil
                            store.send(.appleAuthorizationFailed(error.localizedDescription))
                        }
                    } onCompletion: { result in
                        switch result {
                        case let .success(authorization):
                            do {
                                store.send(.deleteAccountAuthorized(try appleCredential(authorization, rawNonce: rawNonce)))
                            } catch {
                                store.send(.appleAuthorizationFailed(error.localizedDescription))
                            }
                            rawNonce = nil
                        case let .failure(error):
                            rawNonce = nil
                            let cancelled = (error as? ASAuthorizationError)?.code == .canceled
                            store.send(.appleAuthorizationFailed(cancelled ? nil : error.localizedDescription))
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(minHeight: HimatchMetrics.primaryButtonHeight)
                }
            }
            .navigationTitle("アカウント削除")
            .toolbar { Button("閉じる") { dismiss() } }
        }
    }
}

private struct FriendLabel: View {
    let friend: FriendProfile
    var body: some View {
        HStack(spacing: HimatchSpacing.s) {
            IconAvatar(systemImage: friend.icon, size: 36)
            Text(friend.displayName)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyRowText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(HimatchFont.supporting)
            .foregroundStyle(.secondary)
    }
}

private func appleCredential(
    _ authorization: ASAuthorization,
    rawNonce: String?
) throws -> AppleAuthorizationCredential {
    guard
        let rawNonce,
        let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
        credential.identityToken != nil,
        credential.authorizationCode != nil
    else { throw AuthenticationFailure.invalidAppleCredential }
    return AppleAuthorizationCredential(
        identityToken: try AppleCredentialDataDecoder.identityToken(credential.identityToken),
        authorizationCode: try AppleCredentialDataDecoder.authorizationCode(credential.authorizationCode),
        rawNonce: rawNonce
    )
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
