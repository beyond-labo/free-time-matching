import AuthenticationServices
import ComposableArchitecture
import SwiftUI

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.send(.systemActionsForeground) }
        }
        .onChange(of: store.route) { _, route in
            if route == .main { store.send(.systemActionsForeground) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .systemActionRequested)) { _ in
            store.send(.systemActionsForeground)
        }
        .onReceive(NotificationCenter.default.publisher(for: .schedulingNotificationOpened)) { _ in
            store.send(.systemActionsForeground)
            if store.route == .main { store.send(.showInbox(true)) }
        }
        .sheet(isPresented: Binding(
            get: { store.route == .main && store.systemActionOperationID != nil },
            set: { if !$0 { store.send(.systemActionDismissed) } }
        )) {
            if let id = store.systemActionOperationID {
                SystemActionReviewView(operationID: id, service: AppRuntime.shared.systemActions) {
                    store.send(.systemActionCompleted)
                }
            }
        }
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
                    Text(HimatchApp.displayName)
                        .font(HimatchFont.screenTitle)
                        .foregroundStyle(HimatchColor.accent)
                    Text("空いてる時間に、友達を誘って遊ぼう。")
                        .font(HimatchFont.hero)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: HimatchSpacing.m) {
                    OnboardingStep(number: 1, title: "空いている時間を登録", detail: "予定を入れたい時間を15分単位で置いておきます。友達には公開されません。", tint: HimatchColor.accent)
                    OnboardingStep(number: 2, title: "自動提案を許可", detail: "許可し合った友達とだけ、共通の暇からオンラインの遊びが提案されます。初期はオフです。", tint: HimatchColor.hosting)
                    OnboardingStep(number: 3, title: "参加OKで予定が決まる", detail: "双方が参加OKすると、日程調整なしで予定が確定します。自分で友達を誘うこともできます。", tint: HimatchColor.plan)
                }
                .himatchCard()

                Label("暇の登録は誘いを受け取ってよいという意思で、参加OKではありません。相手の名前は双方OKで表示され、提案日時から共通の暇を推測される可能性があります。", systemImage: "lock.fill")
                    .font(HimatchFont.supporting)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

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
                        store.send(.startDemo(.noFriends))
                    } label: {
                        Label("デモではじめから試す", systemImage: "hammer.fill")
                    }
                    .buttonStyle(.himatchSecondary)
                    Button {
                        store.send(.startDemo(.withFriends))
                    } label: {
                        Label("デモで友達がいる状態から試す", systemImage: "person.2.fill")
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
                    Text("日本向け・18歳以上の、知り合い同士での利用を想定した初版です。")
                        .font(HimatchFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(HimatchSpacing.l)
        }
        .background(HimatchColor.background)
    }
}

private struct OnboardingStep: View {
    let number: Int
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: HimatchSpacing.s) {
            Text("\(number)")
                .font(.headline.weight(.heavy))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: HimatchRadius.control, style: .continuous).fill(HimatchColor.tint(tint)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HimatchSpacing.xxs) {
                Text(title).font(HimatchFont.cardTitle)
                Text(detail).font(HimatchFont.supporting).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ステップ\(number)、\(title)。\(detail)")
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
        .sheet(isPresented: Binding(get: { store.addFriendPresented }, set: { store.send(.showAddFriend($0)) })) {
            AddFriendView(store: store)
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
                            HStack {
                                NavigationLink {
                                    FriendDetailView(store: store, friend: friend)
                                } label: {
                                    FriendLabel(friend: friend)
                                }
                                Button("誘う") { store.send(.inviteFriendFromProfile(friend.id)) }
                                    .buttonStyle(.bordered)
                                    .accessibilityLabel("\(friend.displayName)さんを誘う")
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
                        .simultaneousGesture(TapGesture().onEnded { store.send(.inviteCodeShared) })
                        Button("コードを再発行", role: .destructive) {
                            store.send(.rotateInviteCode)
                        }
                        .disabled(store.isLoading)
                    }
                } else if !store.isDemo {
                    Section("招待コード") {
                        if store.isFriendshipLoading {
                            ProgressView("友達情報を読み込み中…")
                        } else if store.friendshipLoadError {
                            Text("友達情報を読み込めませんでした")
                        } else {
                            Text("招待コードがありません")
                        }
                        Button("再読み込み") { store.send(.reloadFriendships) }
                            .disabled(store.isFriendshipLoading)
                    }
                }
            }
            .navigationTitle("友達")
            .toolbar {
                Button { store.send(.reloadFriendships) } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("友達情報を再読み込み")
                    .disabled(store.isLoading || store.isFriendshipLoading || store.isDemo)
                Button { store.send(.showAddFriend(true)) } label: { Image(systemName: "person.badge.plus") }
                    .accessibilityLabel("友達を追加")
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

                SchedulingSettingsView(store: store.scope(state: \.automaticScheduling, action: \.automaticScheduling))

                Section("安全") {
                    Label("友達や提案の詳細から通報・ブロックできます", systemImage: "hand.raised.slash")
                    Text("ブロックすると新しい申請・招待・自動提案を止め、今後の確定予定を取り消します。")
                        .font(.footnote).foregroundStyle(.secondary)
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
                    LabeledContent("バージョン", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
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

struct InboxView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    let store: StoreOf<AppFeature>

    var body: some View {
        let now = Date()
        let requests = (store.snapshot?.requests ?? []).filter { $0.direction == .incoming }
        let invitations = (store.snapshot?.invitations ?? []).filter { !$0.isHostedByMe && HomeDashboard.needsAnswer($0, now: now) }
        let mine = (store.snapshot?.hostings ?? []).filter { $0.isHostedByMe && $0.status == .recruiting }
        NavigationStack {
            List {
                Section("自動提案と予定") {
                    SchedulingStatusView(store: store.scope(state: \.automaticScheduling, action: \.automaticScheduling))
                    ForEach(store.automaticScheduling.snapshot?.proposals.filter { $0.status == .pending || $0.status == .confirmed } ?? []) { proposal in
                        SchedulingProposalCard(store: store.scope(state: \.automaticScheduling, action: \.automaticScheduling), proposal: proposal)
                    }
                    if store.automaticScheduling.snapshot?.proposals.isEmpty == true {
                        Text("自動提案はまだありません。双方の許可と共通の暇があると届きます。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("終了した提案") {
                    ForEach(store.automaticScheduling.snapshot?.proposals.filter { $0.status != .pending && $0.status != .confirmed } ?? []) { proposal in
                        SchedulingProposalCard(store: store.scope(state: \.automaticScheduling, action: \.automaticScheduling), proposal: proposal)
                    }
                }
                Section("要対応") {
                    ForEach(requests) { request in
                        HStack {
                            Label("\(request.person.displayName)さんから友達申請", systemImage: "person.badge.plus")
                            Spacer()
                            Button("承認") { store.send(.acceptRequest(request.id)) }
                                .buttonStyle(.bordered)
                        }
                        .frame(minHeight: HimatchMetrics.minTapTarget)
                    }
                    ForEach(invitations) { invitation in
                        Button { store.send(.inboxReplyTapped(invitation.id)) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Label("\(invitation.host?.displayName ?? "友達")さんからのお誘い", systemImage: "envelope.badge")
                                Text(AvailabilityFormatting.friendlyRange(invitation.candidateRange, calendar: calendar, now: now))
                                    .font(HimatchFont.supporting).foregroundStyle(.secondary)
                            }
                            .frame(minHeight: HimatchMetrics.minTapTarget, alignment: .leading)
                        }
                    }
                    if requests.isEmpty && invitations.isEmpty {
                        EmptyRowText("対応が必要なお知らせはありません")
                    }
                }
                Section("あなたのお誘い") {
                    ForEach(mine) { hosting in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AvailabilityFormatting.friendlyRange(hosting.candidateRange, calendar: calendar, now: now))
                            if hosting.participants.isEmpty {
                                Text("返事待ち").font(HimatchFont.supporting).foregroundStyle(.secondary)
                            }
                            ForEach(hosting.participants) { participant in
                                Label(
                                    "\(participant.friend.displayName)さんが参加OK \(participant.approvedIntervals.map { AvailabilityFormatting.timeSpan($0, calendar: calendar) }.joined(separator: "、"))",
                                    systemImage: "checkmark.circle.fill"
                                )
                                .font(HimatchFont.supporting)
                                .foregroundStyle(HimatchColor.plan)
                            }
                        }
                    }
                    if mine.isEmpty { EmptyRowText("送ったお誘いはありません") }
                }
            }
            .navigationTitle("お知らせ")
            .toolbar { Button("閉じる") { dismiss() } }
        }
        .safeAreaInset(edge: .bottom) {
            Text("通知をオフにしていても、ここで確認できます。")
                .font(HimatchFont.caption).foregroundStyle(.secondary)
                .padding(.bottom, HimatchSpacing.s)
        }
    }
}

private struct AddFriendView: View {
    @Environment(\.dismiss) private var dismiss
    let store: StoreOf<AppFeature>

    var body: some View {
        NavigationStack {
            Form {
                if let code = store.snapshot?.inviteCode, !code.value.isEmpty {
                    Section {
                        Text(code.value)
                            .font(.title3.monospaced().weight(.semibold))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, HimatchSpacing.xs)
                        ShareLink(item: "\(HimatchApp.displayName)で友達になろう！ 招待コード：\(code.value)") {
                            Label("コードを送る", systemImage: "square.and.arrow.up")
                        }
                        .simultaneousGesture(TapGesture().onEnded { store.send(.inviteCodeShared) })
                        .frame(minHeight: HimatchMetrics.minTapTarget)
                    } header: {
                        Text("あなたの招待コード")
                    } footer: {
                        Text("LINE などで送り、相手のアプリで入力してもらいます。相手から申請が届いたら、承認すると友達になります。有効期限: \(code.expiresAt.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
                Section {
                    TextField("HIMA-ABCD-EFGH-JKMP-QRST", text: Binding(get: { store.inviteCodeInput }, set: { store.send(.inviteCodeChanged($0.uppercased())) }))
                        .textInputAutocapitalization(.characters)
                        .font(.body.monospaced())
                        .frame(minHeight: HimatchMetrics.minTapTarget)
                } header: {
                    Text("相手からコードをもらった場合")
                } footer: {
                    Text("無効・期限切れ・ブロックなどの違いは表示しません。知らない人を名前で検索する機能はありません。")
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
            .navigationTitle("友達を招待")
            .toolbar { Button("閉じる") { dismiss() } }
        }
    }
}

private struct FriendDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let store: StoreOf<AppFeature>
    let friend: FriendProfile
    @State private var removeConfirmationPresented = false
    @State private var reportConfirmationPresented = false

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
                SchedulingPermissionView(store: store.scope(state: \.automaticScheduling, action: \.automaticScheduling), friendID: friend.id)
                SchedulingStatusView(store: store.scope(state: \.automaticScheduling, action: \.automaticScheduling))
                Button { store.send(.inviteFriendFromProfile(friend.id)) } label: {
                    Label("自分で誘う", systemImage: "paperplane")
                }
                Button { reportConfirmationPresented = true } label: {
                    Label("通報", systemImage: "exclamationmark.bubble")
                }.disabled(!store.automaticScheduling.canMutate)
                Button(role: .destructive) { store.send(.setBlockTarget(friend)) } label: {
                    Label("ブロック", systemImage: "hand.raised.slash")
                }
                Button(role: .destructive) { removeConfirmationPresented = true } label: {
                    Label("友達を解除", systemImage: "person.badge.minus")
                }
            } footer: {
                Text("友達の暇一覧や、友達の友達は表示しません。")
            }
            if !confirmedPlans.isEmpty {
                Section("この友達との確定予定") {
                    ForEach(confirmedPlans) { proposal in
                        SchedulingProposalCard(store: store.scope(state: \.automaticScheduling, action: \.automaticScheduling), proposal: proposal)
                    }
                }
            }
        }
        .navigationTitle(friend.displayName)
        .onAppear { store.send(.automaticScheduling(.refresh)) }
        .confirmationDialog("通報理由を選んでください", isPresented: $reportConfirmationPresented, titleVisibility: .visible) {
            Button("迷惑な申請・お誘い") { store.send(.automaticScheduling(.send(.reportFriend(friend.id, .spam)))) }
            Button("嫌がらせ") { store.send(.automaticScheduling(.send(.reportFriend(friend.id, .harassment)))) }
            Button("表示名・なりすまし・その他") { store.send(.automaticScheduling(.send(.reportFriend(friend.id, .other)))) }
        }
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
            Text("友達関係を解除し、新しい申請・お誘い・自動提案を止め、未確定提案と今後の確定予定を取り消します。解除しても以前の友達関係や許可は復活しません。")
        }
        .confirmationDialog(
            "\(friend.displayName)さんとの友達関係を解除しますか？",
            isPresented: $removeConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("友達を解除", role: .destructive) { store.send(.removeFriend(friend.id)) }
                .disabled(store.isLoading)
        } message: {
            Text("新しい自動提案とお誘いを止め、未確定提案を取り下げます。確定済みの予定は残り、別に取り消せます。")
        }
        .onChange(of: store.snapshot?.friends.contains(where: { $0.id == friend.id }) ?? false) {
            _, remainsFriend in
            if !remainsFriend { dismiss() }
        }
    }

    private var confirmedPlans: [SchedulingProposal] {
        (store.automaticScheduling.snapshot?.proposals ?? []).filter {
            $0.status == .confirmed && $0.peer?.userId == friend.id
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
                    ForEach(ReportReason.allCases, id: \.self) { Text($0.title).tag($0) }
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
                    Label("プロフィール、暇時間、友達、お誘いと返事、自動提案", systemImage: "trash")
                    Text("未確定の提案を終了し、今後の確定予定を取り消し、通知配信を停止します。")
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

struct FriendLabel: View {
    let friend: FriendProfile
    var body: some View {
        HStack(spacing: HimatchSpacing.s) {
            IconAvatar(systemImage: friend.icon, size: 36)
            Text(friend.displayName)
        }
        .accessibilityElement(children: .combine)
    }
}

struct EmptyRowText: View {
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

#if DEBUG
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
#endif
