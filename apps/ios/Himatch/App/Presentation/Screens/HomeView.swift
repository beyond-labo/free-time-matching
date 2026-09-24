import ComposableArchitecture
import SwiftUI

/// Home tab: notices, the availability calendar and the primary actions.
/// Maps the app snapshot into read-only timeline items (own availability and confirmed plans only).
struct HomeView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = store.snapshot {
                    VStack(spacing: 0) {
                        notices(snapshot)
                        HomeTimelineView(
                            store: store.scope(state: \.homeTimeline, action: \.homeTimeline),
                            items: Self.scheduleItems(snapshot)
                        )
                    }
                } else {
                    ProgressView("読み込み中…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let selection = store.homeTimeline.selection, store.snapshot != nil {
                    SelectionConfirmationBar(
                        store: store.scope(state: \.homeTimeline, action: \.homeTimeline),
                        selection: selection
                    )
                } else {
                    actionBar
                }
            }
            .navigationTitle("ホーム")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.send(.showInbox(true)) } label: {
                        Image(systemName: "bell")
                            .frame(minWidth: HimatchMetrics.minTapTarget, minHeight: HimatchMetrics.minTapTarget)
                    }
                    .accessibilityLabel("お知らせ")
                }
            }
            .sheet(item: $store.scope(state: \.availabilityEditor, action: \.availabilityEditor)) { editorStore in
                AvailabilityEditorView(store: editorStore)
            }
            .sheet(isPresented: Binding(get: { store.hostingEditorPresented }, set: { store.send(.showHostingEditor($0)) })) {
                HostingEditorView(store: store)
            }
            .sheet(isPresented: Binding(get: { store.inboxPresented }, set: { store.send(.showInbox($0)) })) {
                InboxView(store: store)
            }
            .sheet(isPresented: Binding(get: { store.hostingListPresented }, set: { store.send(.showHostingList($0)) })) {
                HostingListView(store: store)
            }
        }
    }

    @ViewBuilder
    private func notices(_ snapshot: AppSnapshot) -> some View {
        let pending = snapshot.invitations.count + snapshot.requests.count
        let showsNotices = pending > 0 || !snapshot.hostings.isEmpty || snapshot.availability.isEmpty
        if showsNotices {
            VStack(spacing: HimatchSpacing.xs) {
                if pending > 0 {
                    NoticeBanner(icon: "bell.badge.fill", title: "要対応があります", detail: "\(pending)件") {
                        store.send(.showInbox(true))
                    }
                }
                if !snapshot.hostings.isEmpty {
                    NoticeBanner(
                        icon: "megaphone.fill",
                        title: "募集中",
                        detail: "\(snapshot.hostings.count)件",
                        tint: HimatchColor.hosting
                    ) {
                        store.send(.showHostingList(true))
                    }
                }
                if snapshot.availability.isEmpty {
                    InfoRow(
                        icon: "clock.badge.plus",
                        title: "まだ暇が登録されていません",
                        detail: "カレンダーの時間をタップするか、下の「暇を登録」から追加できます。"
                    )
                    .himatchCard()
                }
            }
            .padding(.horizontal, HimatchSpacing.m)
            .padding(.top, HimatchSpacing.xs)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
    }

    private var actionBar: some View {
        HStack(spacing: HimatchSpacing.s) {
            Button {
                store.send(.homeTimeline(.newAvailabilityTapped))
            } label: {
                Label("暇を登録", systemImage: "plus")
            }
            .buttonStyle(.himatchPrimary)
            .accessibilityHint("次の15分から2時間の暇を登録します。時間はあとで調整できます")

            Button {
                store.send(.showHostingEditor(true))
            } label: {
                Text("友達を誘う")
            }
            .buttonStyle(.himatchSecondary(tint: HimatchColor.accent, fullWidth: false))
            .frame(minHeight: HimatchMetrics.primaryButtonHeight)
        }
        .padding(.horizontal, HimatchSpacing.m)
        .padding(.vertical, HimatchSpacing.s)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background(.bar)
    }

    static func scheduleItems(_ snapshot: AppSnapshot) -> [HomeScheduleItem] {
        let availability = snapshot.availability.map { slot in
            HomeScheduleItem(
                id: .availability(slot.id),
                interval: slot.interval,
                title: slot.category?.rawValue ?? "暇",
                systemImage: slot.category?.systemImage ?? "clock.fill",
                kind: .availability(slot.visibility)
            )
        }
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
        return availability + plans
    }
}

private struct HostingListView: View {
    @Environment(\.dismiss) private var dismiss
    let store: StoreOf<AppFeature>

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: HimatchSpacing.s) {
                    ForEach(store.snapshot?.hostings ?? []) { hosting in
                        HostingCard(hosting: hosting) {
                            store.send(.confirmHosting(hosting.id))
                        }
                    }
                    if store.snapshot?.hostings.isEmpty ?? true {
                        EmptyStateView(icon: "megaphone", title: "募集中のお誘いはありません")
                    }
                }
                .padding(HimatchSpacing.m)
            }
            .background(HimatchColor.background)
            .navigationTitle("募集中")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
        }
    }
}

struct HostingCard: View {
    let hosting: Hosting
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
            Label(hosting.category?.rawValue ?? "遊びの募集", systemImage: "megaphone.fill")
                .font(HimatchFont.cardTitle)
            Text("\(hosting.mode.rawValue)・\(Int(hosting.requiredDuration / 3600))時間")
                .font(HimatchFont.supporting)
                .foregroundStyle(.secondary)
            Text("参加OKの回答があると表示されます。配信人数は表示しません。")
                .font(HimatchFont.caption)
                .foregroundStyle(.secondary)
            Button("この日時で確定") { onConfirm() }
                .buttonStyle(.himatchSecondary(tint: HimatchColor.hosting, fullWidth: false))
        }
        .himatchCard(tint: HimatchColor.hosting)
    }
}
