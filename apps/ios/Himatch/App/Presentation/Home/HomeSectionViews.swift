import ComposableArchitecture
import SwiftUI

// MARK: - 友達申請

struct FriendRequestsSection: View {
    let requests: [FriendRequest]
    let store: StoreOf<AppFeature>

    var body: some View {
        VStack(spacing: HimatchSpacing.xs) {
            ForEach(requests) { request in
                HStack(spacing: HimatchSpacing.s) {
                    IconAvatar(systemImage: request.person.icon, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(request.person.displayName)さん").font(HimatchFont.cardTitle)
                        Text("から友達申請が届きました").font(HimatchFont.supporting).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer()
                    Button("承認") { store.send(.acceptRequest(request.id)) }
                        .buttonStyle(.himatchSecondary(tint: HimatchColor.accent, fullWidth: false))
                        .disabled(store.isLoading)
                }
                .himatchCard(tint: HimatchColor.attention)
            }
        }
    }
}

// MARK: - 届いたお誘い

struct ReceivedInvitationCard: View {
    let invitation: Hosting
    let now: Date
    let onOpen: () -> Void

    @Environment(\.calendar) private var calendar

    private var needsAnswer: Bool { HomeDashboard.needsAnswer(invitation, now: now) }
    private var acceptedRange: TimeIntervalRange? {
        invitation.myInvitation?.status == .accepted ? invitation.myInvitation?.intervals?.first : nil
    }
    private var isClosed: Bool { invitation.status != .recruiting || now >= invitation.answerDeadline }

    var body: some View {
        VStack(alignment: .leading, spacing: HimatchSpacing.s) {
            HStack(spacing: HimatchSpacing.s) {
                IconAvatar(systemImage: invitation.host?.icon ?? "person.fill", size: 40, tint: HimatchColor.hosting)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(invitation.host?.displayName ?? "友達")さんから").font(HimatchFont.cardTitle)
                    Text(invitation.summary).font(HimatchFont.supporting).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                statusBadge
            }
            Text(AvailabilityFormatting.friendlyRange(invitation.candidateRange, calendar: calendar, now: now))
                .font(HimatchFont.emphasizedValue)
            CandidateTimeBar(candidate: invitation.candidateRange, highlights: acceptedRange.map { [$0] } ?? [])
            if let acceptedRange {
                Text("あなたの参加OK：\(AvailabilityFormatting.timeSpan(acceptedRange, calendar: calendar))")
                    .font(HimatchFont.supporting)
            }
            if !isClosed {
                Text("返事の期限 \(AvailabilityFormatting.friendlyMoment(invitation.answerDeadline, calendar: calendar, now: now))まで")
                    .font(HimatchFont.caption).foregroundStyle(.secondary)
                if needsAnswer {
                    Button("返事をする", action: onOpen).buttonStyle(.himatchPrimary)
                } else {
                    Button("返事を変える", action: onOpen).buttonStyle(.himatchSecondary(tint: HimatchColor.accent))
                }
            }
        }
        .himatchCard(tint: needsAnswer ? HimatchColor.hosting : (acceptedRange != nil ? HimatchColor.plan : nil))
    }

    @ViewBuilder private var statusBadge: some View {
        if invitation.status == .cancelled {
            StatusBadge(title: "取り消されました", systemImage: "xmark.circle")
        } else if isClosed {
            StatusBadge(title: "期限切れ", systemImage: "clock")
        } else if acceptedRange != nil {
            StatusBadge(title: "参加OK済み", systemImage: "checkmark.circle.fill", tint: HimatchColor.plan)
        } else if invitation.myInvitation?.status == .declined {
            StatusBadge(title: "見送り", systemImage: "moon.zzz")
        } else {
            StatusBadge(title: "返事する", systemImage: "envelope.badge", tint: HimatchColor.hosting)
        }
    }
}

// MARK: - はじめての予定

struct FirstMatchGuideCard: View {
    let step: FirstMatchStep
    let friends: [FriendProfile]
    let store: StoreOf<AppFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: HimatchSpacing.s) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("はじめての予定").font(HimatchFont.sectionTitle).accessibilityAddTraits(.isHeader)
                    Text("友達と共通の暇が見つかると、遊ぶ時間を提案します").font(HimatchFont.supporting).foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(title: "\(step.completedCount)/3", systemImage: "flag.checkered", tint: HimatchColor.accent)
                Button { store.send(.dismissGuide) } label: {
                    Image(systemName: "xmark").frame(width: HimatchMetrics.minTapTarget, height: HimatchMetrics.minTapTarget)
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel("案内を閉じる")
            }
            ProgressView(value: Double(step.completedCount), total: 3).tint(HimatchColor.accent)
                .accessibilityHidden(true)
            row(1, "友達とつながる", state: state(for: 1)) {
                if case let .connectFriends(codeShared) = step {
                    Text("招待コードを送り、相手の申請を承認すると友達になります。")
                        .font(HimatchFont.supporting).foregroundStyle(.secondary)
                    if codeShared {
                        Label("コードを送りました。相手の申請を待っています。", systemImage: "hourglass")
                            .font(HimatchFont.supporting.weight(.semibold)).foregroundStyle(HimatchColor.hosting)
                    }
                } else {
                    Text("\(friends.count)人とつながっています").font(HimatchFont.supporting).foregroundStyle(.secondary)
                }
            }
            row(2, "暇を登録して自動提案を許可", state: state(for: 2)) {
                if case let .prepareProposals(readiness) = step { preparation(readiness) }
            }
            row(3, "提案に参加OK", state: state(for: 3)) {
                if case let .answerProposal(hasPending) = step {
                    Text(hasPending
                         ? "届いた提案に参加OKすると、相手もOKした時点で予定が決まります。"
                         : "共通の暇が見つかると、ここに提案が届きます。待たずに自分で誘うこともできます。")
                        .font(HimatchFont.supporting).foregroundStyle(.secondary)
                }
            }
        }
        .himatchCard()
    }

    @ViewBuilder
    private func preparation(_ readiness: FirstMatchReadiness) -> some View {
        let scheduling = store.automaticScheduling
        VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
            Text("暇の時間や友達の名前は相手に見えません。双方が許可した友達とだけ提案します。")
                .font(HimatchFont.supporting).foregroundStyle(.secondary)
            checklist("空いている時間を登録", done: readiness.hasAvailability) {
                Button("暇を登録") { store.send(.registerAvailabilityTapped) }
            }
            checklist("自動提案をオンにする", done: readiness.proposalsEnabled) {
                Button("オンにする") { store.send(.automaticScheduling(.send(.settings(true)))) }
                    .disabled(!scheduling.canMutate)
            }
            checklist("提案してよい友達を許可", done: readiness.hasPermittedFriend) {
                if friends.count <= 2 {
                    ForEach(friends) { friend in
                        Button("\(friend.displayName)さんを許可") {
                            store.send(.automaticScheduling(.send(.permission(friend.id, true))))
                        }
                        .disabled(!scheduling.canMutate)
                    }
                } else {
                    Button("友達を選ぶ") { store.send(.selectTab(.friends)) }
                }
            }
            if scheduling.isLoading || scheduling.isSending || scheduling.error != nil {
                SchedulingStatusView(store: store.scope(state: \.automaticScheduling, action: \.automaticScheduling))
            }
        }
    }

    private func checklist<Action: View>(_ title: String, done: Bool, @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: HimatchSpacing.xs) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? HimatchColor.plan : .secondary)
                .accessibilityHidden(true)
            Text(title).font(HimatchFont.supporting.weight(.semibold))
            Spacer(minLength: HimatchSpacing.xs)
            if !done {
                VStack(alignment: .trailing, spacing: HimatchSpacing.xxs) { action() }
                    .buttonStyle(.himatchSecondary(tint: HimatchColor.accent, fullWidth: false))
            }
        }
        .frame(minHeight: HimatchMetrics.minTapTarget)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title)、\(done ? "済み" : "まだ")")
    }

    private enum StepState { case done, current, later }

    private func state(for number: Int) -> StepState {
        let current = step.completedCount + 1
        return number < current ? .done : (number == current ? .current : .later)
    }

    private func row<Content: View>(_ number: Int, _ title: String, state: StepState, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: HimatchSpacing.s) {
            ZStack {
                Circle().fill(state == .done ? HimatchColor.plan : (state == .current ? HimatchColor.accent : HimatchColor.unavailable))
                if state == .done {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.caption.weight(.bold)).foregroundStyle(state == .current ? .white : .secondary)
                }
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HimatchSpacing.xxs) {
                Text(title).font(HimatchFont.cardTitle).foregroundStyle(state == .later ? .secondary : .primary)
                if state != .later { content() }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ステップ\(number) \(title)、\(state == .done ? "完了" : (state == .current ? "いまここ" : "これから"))")
    }
}

struct TimeCandidateChips: View {
    let candidates: [TimeCandidate]
    let now: Date
    let store: StoreOf<AppFeature>

    @Environment(\.calendar) private var calendar

    var body: some View {
        FlowLayout(spacing: HimatchSpacing.xs) {
            ForEach(candidates) { candidate in
                CandidateChip(
                    title: candidate.title,
                    detail: AvailabilityFormatting.friendlyRange(candidate.range, calendar: calendar, now: now),
                    isSelected: false
                ) { store.send(.startInvitation(.candidate(candidate))) }
            }
            CandidateChip(title: "日時を選ぶ", detail: "14日先まで", isSelected: false) {
                store.send(.startInvitation(.blank))
            }
        }
    }
}

// MARK: - あなたのお誘い

struct MyInvitationCard: View {
    let hosting: Hosting
    let now: Date
    let onCancel: () -> Void

    @Environment(\.calendar) private var calendar
    @State private var confirmCancel = false

    var body: some View {
        let participants = hosting.participants
        VStack(alignment: .leading, spacing: HimatchSpacing.s) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AvailabilityFormatting.friendlyRange(hosting.candidateRange, calendar: calendar, now: now))
                        .font(HimatchFont.emphasizedValue)
                    Text(hosting.summary).font(HimatchFont.supporting).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if participants.isEmpty {
                    StatusBadge(title: "返事待ち", systemImage: "hourglass", tint: HimatchColor.hosting)
                } else {
                    StatusBadge(title: "参加OK \(participants.count)人", systemImage: "checkmark.circle.fill", tint: HimatchColor.plan)
                }
            }
            CandidateTimeBar(candidate: hosting.candidateRange, highlights: participants.flatMap(\.approvedIntervals))
            if participants.isEmpty {
                Text("参加OKの返事が届くと、ここに名前と時間が出ます。返事がない人や見送った人は表示されません。")
                    .font(HimatchFont.supporting).foregroundStyle(.secondary)
            }
            ForEach(participants) { participant in
                HStack(spacing: HimatchSpacing.s) {
                    FriendLabel(friend: participant.friend)
                    Spacer()
                    Text(participant.approvedIntervals.map { AvailabilityFormatting.timeSpan($0, calendar: calendar) }.joined(separator: "、"))
                        .font(.subheadline.monospacedDigit())
                    Text("参加OK").font(.caption.weight(.semibold)).foregroundStyle(HimatchColor.plan)
                }
                .accessibilityElement(children: .combine)
            }
            if let everyone = HostingPolicy.everyoneAvailable(candidate: hosting.candidateRange, participants: participants) {
                StatusBadge(title: "全員そろう時間 \(AvailabilityFormatting.timeSpan(everyone, calendar: calendar))", systemImage: "person.3.fill", tint: HimatchColor.plan)
            }
            if !participants.isEmpty {
                InfoRow(icon: "bubble.left.and.bubble.right", title: "あとはいつもの連絡手段で", detail: "場所や集合のことは、LINE など普段の連絡手段で相談してください。", tint: HimatchColor.plan)
            }
            Button("お誘いを取り消す", role: .destructive) { confirmCancel = true }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: HimatchMetrics.minTapTarget)
                .confirmationDialog("このお誘いを取り消しますか？", isPresented: $confirmCancel, titleVisibility: .visible) {
                    Button("取り消す", role: .destructive, action: onCancel)
                } message: {
                    Text("友達の返事も無効になります。あなたの暇は残ります。")
                }
        }
        .himatchCard(tint: participants.isEmpty ? HimatchColor.hosting : HimatchColor.plan)
    }
}

// MARK: - あなたの暇

struct MyAvailabilitySection: View {
    let slots: [AvailabilitySlot]
    let busyIDs: Set<UUID>
    let canInvite: Bool
    let now: Date
    let store: StoreOf<AppFeature>

    @Environment(\.calendar) private var calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.isAvailabilityLoading {
                ProgressView("あなたの暇を読み込み中…").frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 52)
            } else if store.availabilityLoadError {
                HStack {
                    Text("あなたの暇を読み込めませんでした").font(HimatchFont.supporting)
                    Spacer()
                    Button("再読み込み") { store.send(.reloadAvailability) }
                }
                .frame(minHeight: 52)
            } else if slots.isEmpty {
                Text("空いている時間を登録すると、自動提案と誘う候補に使われます。暇の時間は相手に見えません。")
                    .font(HimatchFont.supporting).foregroundStyle(.secondary)
                    .padding(.vertical, HimatchSpacing.xs)
            }
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                if index > 0 { Divider() }
                HStack(spacing: HimatchSpacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AvailabilityFormatting.friendlyRange(slot.interval, calendar: calendar, now: now))
                            .font(.body.weight(.semibold).monospacedDigit())
                        if busyIDs.contains(slot.id) {
                            Text("お誘い中の時間を含みます").font(HimatchFont.caption).foregroundStyle(HimatchColor.hosting)
                        }
                    }
                    Spacer()
                    if canInvite, !busyIDs.contains(slot.id) {
                        Button("この時間で誘う") {
                            store.send(.startInvitation(.range(QuarterRange(start: max(slot.interval.start, AvailabilityPolicy.nextQuarterHour(after: now, calendar: calendar)), end: slot.interval.end))))
                        }
                        .buttonStyle(.himatchSecondary(tint: HimatchColor.accent, fullWidth: false))
                    }
                }
                .frame(minHeight: 56)
            }
            Button {
                store.send(.registerAvailabilityTapped)
            } label: {
                Label("暇を追加", systemImage: "plus")
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: HimatchMetrics.minTapTarget)
        }
        .himatchCard()
    }
}

// MARK: - 参加OKの一時表示

struct ParticipationNoticeBannerView: View {
    let banner: ParticipationBanner
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: HimatchSpacing.s) {
                IconAvatar(systemImage: "checkmark.circle.fill", size: 36, tint: HimatchColor.plan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(banner.title).font(HimatchFont.cardTitle)
                    Text(banner.detail).font(HimatchFont.supporting).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(HimatchSpacing.m)
            .background(RoundedRectangle(cornerRadius: HimatchRadius.card, style: .continuous).fill(HimatchColor.elevatedSurface))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("お知らせを開きます")
        .task {
            AccessibilityNotification.Announcement("\(banner.title)。\(banner.detail)").post()
            try? await Task.sleep(for: .seconds(5))
            onDismiss()
        }
    }
}
