import ComposableArchitecture
import SwiftUI

/// Home tab: what to do next, built from the `HomeDashboard` projection (requirements 2, 3, 6–8).
/// The 14-day timeline moved to `AvailabilityCalendarView`, one tap away.
struct HomeView: View {
    @Bindable var store: StoreOf<AppFeature>
    @Environment(\.calendar) private var calendar

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let now = context.date
                Group {
                    if let snapshot = store.snapshot {
                        let dashboard = HomeDashboard.make(
                            snapshot: snapshot, scheduling: store.automaticScheduling.snapshot,
                            record: store.firstMatchRecord, now: now, calendar: calendar
                        )
                        content(dashboard, snapshot: snapshot, now: now)
                            .safeAreaInset(edge: .bottom) { primaryAction(dashboard.primaryAction) }
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) { bell(count: dashboard.noticeCount) }
                            }
                    } else {
                        ProgressView("読み込み中…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .overlay(alignment: .top) {
                    if let banner = store.participationBanner {
                        ParticipationNoticeBannerView(
                            banner: banner,
                            onTap: { store.send(.participationBannerDismissed); store.send(.showInbox(true)) },
                            onDismiss: { store.send(.participationBannerDismissed) }
                        )
                        .padding(.horizontal, HimatchSpacing.m)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.default, value: store.participationBanner)
                .sheet(item: Binding(get: { store.sentInvitation }, set: { if $0 == nil { store.send(.sentInvitationDismissed) } })) { invitation in
                    InvitationSentView(invitation: invitation, now: now) { store.send(.sentInvitationDismissed) }
                }
            }
            .background(HimatchColor.background)
            .navigationTitle("ホーム")
            .navigationDestination(isPresented: Binding(get: { store.calendarPresented }, set: { store.send(.showCalendar($0)) })) {
                AvailabilityCalendarView(store: store)
            }
            .sheet(item: $store.scope(state: \.availabilityEditor, action: \.availabilityEditor)) { editorStore in
                AvailabilityEditorView(store: editorStore)
            }
            .sheet(item: $store.scope(state: \.composer, action: \.composer)) { composerStore in
                InvitationComposerView(store: composerStore)
            }
            .sheet(item: $store.scope(state: \.reply, action: \.reply)) { replyStore in
                InvitationReplyView(store: replyStore, profileName: store.profileName)
            }
            .sheet(isPresented: Binding(get: { store.inboxPresented }, set: { store.send(.showInbox($0)) })) {
                InboxView(store: store)
            }
            .task { store.send(.homeAppeared) }
        }
    }

    @ViewBuilder
    private func content(_ dashboard: HomeDashboard, snapshot: AppSnapshot, now: Date) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: HimatchSpacing.l) {
                if store.hostingLoadError {
                    HStack {
                        Label("お誘いを読み込めませんでした", systemImage: "exclamationmark.triangle")
                            .font(HimatchFont.supporting)
                        Spacer()
                        Button("再読み込み") { store.send(.reloadHostings) }
                    }
                    .himatchCard(tint: HimatchColor.attention)
                }
                ForEach(Array(dashboard.sections.enumerated()), id: \.element.kind) { _, section in
                    sectionView(section, snapshot: snapshot, now: now)
                }
#if DEBUG
                if store.isDemo, Self.hasDemoActions(snapshot, scheduling: store.automaticScheduling.snapshot) { demoControls(snapshot) }
#endif
            }
            .padding(HimatchSpacing.m)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .refreshable { store.send(.homeRefreshed) }
    }

    @ViewBuilder
    private func sectionView(_ section: HomeDashboard.Section, snapshot: AppSnapshot, now: Date) -> some View {
        switch section {
        case let .friendRequests(requests):
            VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
                SectionHeader("友達申請")
                FriendRequestsSection(requests: requests, store: store)
            }
        case let .invitationsToAnswer(invitations):
            VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
                SectionHeader("届いたお誘い")
                ForEach(invitations) { invitation in
                    ReceivedInvitationCard(invitation: invitation, now: now) { store.send(.openReply(invitation.id)) }
                }
            }
        case let .proposals(proposals, proposalsOff):
            VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
                SectionHeader("遊ぶ時間の提案")
                if proposalsOff {
                    HStack(spacing: HimatchSpacing.s) {
                        Label("自動提案はオフです", systemImage: "sparkles").font(HimatchFont.supporting)
                        Spacer()
                        Button("オンにする") { store.send(.automaticScheduling(.send(.settings(true)))) }
                            .disabled(!store.automaticScheduling.canMutate)
                            .buttonStyle(.himatchSecondary(tint: HimatchColor.accent, fullWidth: false))
                    }
                    .himatchCard()
                }
                ForEach(proposals) { proposal in
                    SchedulingProposalCard(store: schedulingStore, proposal: proposal).himatchCard()
                }
                SchedulingStatusView(store: schedulingStore)
            }
        case let .guide(step, _):
            FirstMatchGuideCard(step: step, friends: snapshot.friends, store: store)
        case let .confirmedPlans(proposals):
            VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
                SectionHeader("決まった予定")
                ForEach(proposals) { proposal in
                    SchedulingProposalCard(store: schedulingStore, proposal: proposal).himatchCard()
                }
            }
        case let .myInvitations(hostings):
            VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
                SectionHeader("あなたのお誘い")
                ForEach(hostings) { hosting in
                    MyInvitationCard(hosting: hosting, now: now) { store.send(.cancelHosting(hosting.id)) }
                }
            }
        case let .timeCandidates(candidates):
            VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
                SectionHeader("自分で誘う")
                TimeCandidateChips(candidates: candidates, now: now, store: store).himatchCard()
            }
        case let .availability(slots, busyIDs):
            VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
                HStack {
                    SectionHeader("あなたの暇（非公開）")
                    Button { store.send(.showCalendar(true)) } label: { Label("カレンダー", systemImage: "calendar") }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: HimatchMetrics.minTapTarget)
                }
                MyAvailabilitySection(slots: slots, busyIDs: busyIDs, canInvite: !snapshot.friends.isEmpty, now: now, store: store)
            }
        }
    }

    private var schedulingStore: StoreOf<AutomaticSchedulingFeature> {
        store.scope(state: \.automaticScheduling, action: \.automaticScheduling)
    }

    private func primaryAction(_ action: HomeDashboard.PrimaryAction) -> some View {
        Button { store.send(.primaryActionTapped) } label: {
            switch action {
            case .inviteFriendCode: Label("友達を招待する", systemImage: "person.badge.plus")
            case .registerAvailability: Label("暇を登録", systemImage: "calendar.badge.plus")
            }
        }
        .buttonStyle(.himatchPrimary)
        .padding(.horizontal, HimatchSpacing.m)
        .padding(.vertical, HimatchSpacing.s)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background(.bar)
    }

    private func bell(count: Int) -> some View {
        Button { store.send(.showInbox(true)) } label: {
            Image(systemName: count > 0 ? "bell.badge" : "bell")
                .frame(minWidth: HimatchMetrics.minTapTarget, minHeight: HimatchMetrics.minTapTarget)
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .background(Capsule().fill(HimatchColor.danger))
                            .offset(x: 2, y: 4)
                    }
                }
        }
        .accessibilityLabel(count > 0 ? "お知らせ \(count)件" : "お知らせ")
    }

#if DEBUG
    static func hasDemoActions(_ snapshot: AppSnapshot, scheduling: SchedulingSnapshot?) -> Bool {
        (snapshot.friends.isEmpty && snapshot.requests.isEmpty)
            || snapshot.hostings.contains { $0.isHostedByMe && $0.status == .recruiting && $0.participants.count < $0.friends.count }
            || canSimulateProposal(snapshot, scheduling: scheduling)
            || !(scheduling?.proposals.filter { $0.status == .pending && $0.peerResponse == nil }.isEmpty ?? true)
    }

    /// Mirrors the backend precondition: both sides enabled and permitted, with registered free time.
    static func canSimulateProposal(_ snapshot: AppSnapshot, scheduling: SchedulingSnapshot?) -> Bool {
        guard let scheduling, scheduling.enabled,
              !scheduling.proposals.contains(where: { $0.status == .pending }) else { return false }
        return FirstMatchProgress.readiness(snapshot: snapshot, scheduling: scheduling, now: Date()).isReady
    }

    @ViewBuilder
    private func demoControls(_ snapshot: AppSnapshot) -> some View {
        let open = snapshot.hostings.filter { $0.isHostedByMe && $0.status == .recruiting }
        VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
            Label("デモ操作", systemImage: "hammer.fill").font(HimatchFont.cardTitle)
            Text("実際の友達の操作を再現します。デモだけの表示です。").font(HimatchFont.caption).foregroundStyle(.secondary)
            if snapshot.friends.isEmpty, snapshot.requests.isEmpty {
                Button("りくさんがあなたのコードで申請する") { store.send(.demoFriendRequestTapped) }
                    .buttonStyle(.himatchSecondary(tint: HimatchColor.accent))
            }
            let scheduling = store.automaticScheduling.snapshot
            if Self.canSimulateProposal(snapshot, scheduling: scheduling) {
                Button("共通の暇が見つかり、提案が届く") { store.send(.demoProposalTapped) }
                    .buttonStyle(.himatchSecondary(tint: HimatchColor.accent))
            }
            ForEach(scheduling?.proposals.filter { $0.status == .pending && $0.peerResponse == nil } ?? []) { proposal in
                Button("相手が \(AvailabilityFormatting.timeSpan(proposal.interval, calendar: calendar)) の提案に参加OKする") {
                    store.send(.demoPeerAcceptanceTapped(proposal.id))
                }
                .buttonStyle(.himatchSecondary(tint: HimatchColor.accent))
            }
            ForEach(open) { hosting in
                if hosting.participants.count < hosting.friends.count {
                    Button("友達が \(AvailabilityFormatting.timeSpan(hosting.candidateRange, calendar: calendar)) のお誘いに参加OKする") {
                        store.send(.demoAcceptanceTapped(hosting.id))
                    }
                    .buttonStyle(.himatchSecondary(tint: HimatchColor.accent))
                }
            }
        }
        .himatchCard()
    }
#endif

    static func scheduleItems(_ snapshot: AppSnapshot, scheduling: SchedulingSnapshot? = nil) -> [HomeScheduleItem] {
        let availability = snapshot.availability.map { slot in
            HomeScheduleItem(
                id: .availability(slot.id),
                interval: slot.interval,
                title: slot.category?.rawValue ?? "暇",
                systemImage: slot.category?.systemImage ?? "clock.fill",
                kind: .availability(slot.visibility)
            )
        }
        let hostings = snapshot.hostings.filter { $0.status == .recruiting }.map { hosting in
            HomeScheduleItem(
                id: .hosting(hosting.id), interval: hosting.candidateRange,
                title: "お誘い中", systemImage: "megaphone.fill", kind: .hosting,
                notes: hosting.participants.map { "\($0.friend.displayName)さんが参加OK" }
            )
        }
        let automaticPlans = (scheduling?.proposals ?? []).filter { $0.status == .confirmed }.map { proposal in
            HomeScheduleItem(id: .plan(proposal.id), interval: proposal.interval,
                             title: "オンラインで遊ぶ予定", systemImage: "calendar.badge.checkmark", kind: .plan,
                             notes: [proposal.peer.map { "参加者: \($0.nickname)" } ?? "参加者を確認中", "取消や実施後の任意回答は「提案と予定」から行えます。"])
        }
#if DEBUG
        let plans = snapshot.plans.map { plan in
            HomeScheduleItem(
                id: .plan(plan.id),
                interval: plan.interval,
                title: plan.category?.rawValue ?? "遊ぶ予定",
                systemImage: "calendar.badge.checkmark",
                kind: .plan,
                notes: [
                    "参加者: \(plan.participants.map(\.displayName).joined(separator: "、"))",
                    "集合場所や接続先は、普段の連絡手段で確認してください。",
                ]
            )
        }
        return availability + hostings + plans + automaticPlans
#else
        return availability + hostings + automaticPlans
#endif
    }
}
