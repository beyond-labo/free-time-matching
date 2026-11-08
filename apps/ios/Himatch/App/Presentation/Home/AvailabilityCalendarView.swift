import ComposableArchitecture
import SwiftUI

/// The existing 14-day timeline, now opened from Home (2.2). Its operations are unchanged.
struct AvailabilityCalendarView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                HomeTimelineView(
                    store: store.scope(state: \.homeTimeline, action: \.homeTimeline),
                    items: HomeView.scheduleItems(snapshot)
                )
            } else {
                ProgressView("読み込み中…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let selection = store.homeTimeline.selection, store.snapshot != nil {
                SelectionConfirmationBar(
                    store: store.scope(state: \.homeTimeline, action: \.homeTimeline),
                    selection: selection
                )
            } else {
                HStack(spacing: HimatchSpacing.s) {
                    Button {
                        store.send(.homeTimeline(.newAvailabilityTapped))
                    } label: {
                        Label("暇を登録", systemImage: "plus")
                    }
                    .buttonStyle(.himatchPrimary)
                    .accessibilityHint("次の15分から2時間の暇を登録します。時間はあとで調整できます")

                    Button {
                        store.send(.homeTimeline(.selectionModeChanged(.hosting)))
                    } label: {
                        Text("範囲を選んで誘う")
                    }
                    .buttonStyle(.himatchSecondary(tint: HimatchColor.accent, fullWidth: false))
                    .frame(minHeight: HimatchMetrics.primaryButtonHeight)
                    .disabled(store.snapshot?.friends.isEmpty ?? true)
                }
                .padding(.horizontal, HimatchSpacing.m)
                .padding(.vertical, HimatchSpacing.s)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .background(.bar)
            }
        }
        .navigationTitle("カレンダー")
        .navigationBarTitleDisplayMode(.inline)
    }
}
