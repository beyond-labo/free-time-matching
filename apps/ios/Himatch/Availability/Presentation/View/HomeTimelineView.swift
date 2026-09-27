import ComposableArchitecture
import SwiftUI
import UIKit

/// Home calendar with day/week modes over the next 14 days.
struct HomeTimelineView: View {
    @Bindable var store: StoreOf<HomeTimelineFeature>
    let items: [HomeScheduleItem]

    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let today = store.today ?? calendar.startOfDay(for: now)
            let latestEnd = AvailabilityPolicy.latestEnd(now: now, calendar: calendar)
            VStack(spacing: 0) {
                HomeTimelineHeader(store: store, today: today, items: items, now: now)
                if store.selection == nil {
                    TimelineSelectionHint(mode: store.mode)
                }
                Divider()
                switch store.mode {
                case .day:
                    let day = calendar.date(byAdding: .day, value: store.selectedDayIndex, to: today) ?? today
                    TimelineDayView(
                        store: store,
                        day: day,
                        segments: TimelineLayout.segments(for: items, on: day, calendar: calendar),
                        now: now,
                        latestEnd: latestEnd
                    )
                case .week:
                    let days = store.weekDayIndices.compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
                    if dynamicTypeSize.isAccessibilitySize {
                        TimelineAgendaView(
                            days: days,
                            items: items,
                            now: now,
                            latestEnd: latestEnd,
                            onSelectTime: { store.send(.quarterTapped($0)) },
                            onTapItem: { store.send(.itemTapped($0)) }
                        )
                    } else {
                        TimelineWeekView(
                            days: days,
                            items: items,
                            now: now,
                            latestEnd: latestEnd,
                            onSelectTime: { store.send(.quarterTapped($0)) },
                            onTapItem: { store.send(.itemTapped($0)) },
                            onSelectDay: { day in
                                let offset = calendar.dateComponents([.day], from: today, to: day).day ?? 0
                                store.send(.daySelected(offset))
                                store.send(.modeChanged(.day))
                            }
                        )
                    }
                }
            }
        }
        // Selection appears → light impact; each 15-minute boundary change → selection tick.
        .sensoryFeedback(trigger: store.selection?.range) { old, new in
            guard new != nil else { return nil }
            return old == nil ? .impact(weight: .light) : .selection
        }
        .sensoryFeedback(.success, trigger: store.quickSaveSuccessCount)
        .sensoryFeedback(trigger: store.selection?.saveError) { _, new in
            new == nil ? nil : .warning
        }
        .onChange(of: store.quickSaveSuccessCount) {
            AccessibilityNotification.Announcement("暇時間を登録しました").post()
        }
        .task { store.send(.refreshWindow) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            store.send(.refreshWindow)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            store.send(.refreshWindow)
        }
        .sheet(
            item: Binding(
                get: { store.selectedItem.flatMap { id in items.first { $0.id == id } } },
                set: { if $0 == nil { store.send(.itemDismissed) } }
            )
        ) { item in
            ScheduleItemDetailView(item: item, onDelete: { id in
                store.send(.deleteAvailabilityConfirmed(id))
            }, onInvite: { interval in
                store.send(.itemDismissed)
                store.send(.delegate(.startHosting(QuarterRange(start: interval.start, end: interval.end))))
            })
            .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Header

private struct HomeTimelineHeader: View {
    @Bindable var store: StoreOf<HomeTimelineFeature>
    let today: Date
    let items: [HomeScheduleItem]
    let now: Date

    @Environment(\.calendar) private var calendar

    var body: some View {
        VStack(alignment: .leading, spacing: HimatchSpacing.s) {
            HStack(spacing: HimatchSpacing.s) {
                Picker(
                    "表示",
                    selection: Binding(get: { store.mode }, set: { store.send(.modeChanged($0)) })
                ) {
                    ForEach(HomeTimelineFeature.State.Mode.allCases, id: \.self) { mode in
                        Text("\(mode.title)表示").tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minHeight: HimatchMetrics.minTapTarget)

                Button("今日") { store.send(.todayTapped) }
                    .buttonStyle(.himatchSecondary(tint: HimatchColor.accent, fullWidth: false))
                    .disabled(store.selectedDayIndex == 0)
                    .accessibilityLabel("今日に戻る")
            }

            HStack(spacing: HimatchSpacing.xs) {
                Button { store.send(.previousTapped) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: HimatchMetrics.minTapTarget, height: HimatchMetrics.minTapTarget)
                }
                .disabled(!store.canGoBackward)
                .accessibilityLabel(store.mode == .day ? "前の日" : "前の週")

                Text(title)
                    .font(HimatchFont.cardTitle)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)

                Button { store.send(.nextTapped) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: HimatchMetrics.minTapTarget, height: HimatchMetrics.minTapTarget)
                }
                .disabled(!store.canGoForward)
                .accessibilityLabel(store.mode == .day ? "次の日" : "次の週")
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: HimatchSpacing.xxs) {
                        ForEach(0..<HomeTimelineFeature.State.dayCount, id: \.self) { index in
                            let day = calendar.date(byAdding: .day, value: index, to: today) ?? today
                            DayChip(
                                day: day,
                                isToday: index == 0,
                                isSelected: index == store.selectedDayIndex,
                                isInVisibleWeek: store.mode == .week && store.weekDayIndices.contains(index),
                                availabilityCount: availabilityCount(on: day)
                            ) {
                                store.send(.daySelected(index))
                            }
                            .id(index)
                        }
                    }
                }
                .onChange(of: store.selectedDayIndex) { _, index in
                    withAnimation { proxy.scrollTo(index, anchor: .center) }
                }
            }
            // The strip scrolls horizontally; VoiceOver reads each chip's full date instead.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            Label(
                "時刻は\(AvailabilityFormatting.timeZone(calendar, at: now))で表示",
                systemImage: "globe.asia.australia"
            )
            .font(HimatchFont.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.horizontal, HimatchSpacing.m)
        .padding(.vertical, HimatchSpacing.s)
    }

    private var title: String {
        switch store.mode {
        case .day:
            let day = calendar.date(byAdding: .day, value: store.selectedDayIndex, to: today) ?? today
            let label = AvailabilityFormatting.day(day, calendar: calendar)
            return store.selectedDayIndex == 0 ? "\(label) 今日" : label
        case .week:
            let indices = store.weekDayIndices
            guard let first = calendar.date(byAdding: .day, value: indices.lowerBound, to: today),
                  let last = calendar.date(byAdding: .day, value: indices.upperBound - 1, to: today)
            else { return "" }
            return "\(AvailabilityFormatting.shortDay(first, calendar: calendar))〜\(AvailabilityFormatting.shortDay(last, calendar: calendar))"
        }
    }

    private func availabilityCount(on day: Date) -> Int {
        let range = TimelineLayout.dayRange(for: day, calendar: calendar)
        return items.filter { item in
            if case .availability = item.kind { return item.interval.overlaps(range) }
            return false
        }.count
    }
}

private struct DayChip: View {
    let day: Date
    let isToday: Bool
    let isSelected: Bool
    let isInVisibleWeek: Bool
    let availabilityCount: Int
    let action: () -> Void

    @Environment(\.calendar) private var calendar

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(isToday ? "今日" : AvailabilityFormatting.weekday(day, calendar: calendar))
                    .font(.caption2.weight(.semibold))
                Text("\(calendar.component(.day, from: day))")
                    .font(.headline.monospacedDigit())
                Circle()
                    .fill(availabilityCount > 0 ? (isSelected ? Color.white : HimatchColor.availability) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(minWidth: HimatchMetrics.minTapTarget, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: HimatchRadius.control, style: .continuous)
                    .fill(
                        isSelected
                            ? HimatchColor.accent
                            : (isInVisibleWeek ? HimatchColor.tint(HimatchColor.accent) : Color.clear)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: HimatchRadius.control))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var accessibilityText: String {
        let label = AvailabilityFormatting.day(day, calendar: calendar)
        let prefix = isToday ? "今日、\(label)" : label
        return availabilityCount > 0 ? "\(prefix)、暇\(availabilityCount)件" : prefix
    }
}

// MARK: - Detail

private struct ScheduleItemDetailView: View {
    let item: HomeScheduleItem
    let onDelete: (UUID) -> Void
    let onInvite: (TimeIntervalRange) -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.dismiss) private var dismiss
    @State private var deleteConfirmationPresented = false
    @State private var inviteSelection: AvailabilityInviteSelection?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HimatchSpacing.m) {
                    VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
                        Label(item.title, systemImage: item.systemImage)
                            .font(HimatchFont.sectionTitle)
                        Text(AvailabilityFormatting.range(item.interval, calendar: calendar))
                            .font(HimatchFont.body)
                        StatusBadge(
                            title: AvailabilityFormatting.duration(item.interval.duration),
                            systemImage: "hourglass",
                            tint: tint
                        )
                    }
                    .himatchCard(tint: tint)

                    switch item.kind {
                    case let .availability(visibility):
                        InfoRow(icon: visibility.systemImage, title: visibility.title, detail: visibility.explanation)
                            .himatchCard()
                        Text("暇時間は、あなたが予定を入れたい時間として登録しています。")
                            .font(HimatchFont.supporting)
                            .foregroundStyle(.secondary)
                        inviteRangeControls
                        Button {
                            let range = inviteSelection?.range ?? QuarterRange(start: item.interval.start, end: item.interval.end)
                            onInvite(TimeIntervalRange(start: range.start, end: range.end))
                        } label: {
                            Label("この時間に友達を誘う", systemImage: "megaphone")
                        }
                        .buttonStyle(.himatchSecondary(tint: HimatchColor.hosting, fullWidth: false))
                        if case let .availability(id) = item.id {
                            Button(role: .destructive) {
                                deleteConfirmationPresented = true
                            } label: {
                                Label("この暇を削除", systemImage: "trash")
                            }
                            .buttonStyle(.himatchSecondary(tint: HimatchColor.danger))
                            .confirmationDialog(
                                "この暇を削除しますか？",
                                isPresented: $deleteConfirmationPresented,
                                titleVisibility: .visible
                            ) {
                                Button("削除", role: .destructive) { onDelete(id) }
                            }
                        }
                    case .plan:
                        ForEach(item.notes, id: \.self) { note in
                            Text(note)
                                .font(HimatchFont.supporting)
                                .foregroundStyle(.secondary)
                        }
                    case .hosting:
                        StatusBadge(title: "募集中", systemImage: "megaphone.fill", tint: HimatchColor.hosting)
                        ForEach(item.notes, id: \.self) { note in
                            Text(note).font(HimatchFont.supporting).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(HimatchSpacing.m)
            }
            .navigationTitle(detailTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                inviteSelection = AvailabilityInviteSelection(availability: item.interval)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var inviteRangeControls: some View {
        if case .availability = item.kind, let inviteSelection {
            VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
                Text("招待する時間（15分単位）").font(HimatchFont.supporting)
                HStack {
                    Text("開始 \(AvailabilityFormatting.time(inviteSelection.range.start, calendar: calendar))")
                    Spacer()
                    Button("−") {
                        self.inviteSelection?.stepStart(by: -1)
                    }
                    .disabled(!inviteSelection.canStepStart(by: -1))
                    .accessibilityLabel("招待時間の開始を15分早める")
                    Button("＋") {
                        self.inviteSelection?.stepStart(by: 1)
                    }
                    .disabled(!inviteSelection.canStepStart(by: 1))
                    .accessibilityLabel("招待時間の開始を15分遅らせる")
                }
                HStack {
                    Text("終了 \(AvailabilityFormatting.time(inviteSelection.range.end, calendar: calendar))")
                    Spacer()
                    Button("−") {
                        self.inviteSelection?.stepEnd(by: -1)
                    }
                    .disabled(!inviteSelection.canStepEnd(by: -1))
                    .accessibilityLabel("招待時間の終了を15分早める")
                    Button("＋") {
                        self.inviteSelection?.stepEnd(by: 1)
                    }
                    .disabled(!inviteSelection.canStepEnd(by: 1))
                    .accessibilityLabel("招待時間の終了を15分遅らせる")
                }
            }
            .font(HimatchFont.supporting)
            .himatchCard()
        }
    }

    private var isAvailability: Bool {
        if case .availability = item.kind { return true }
        return false
    }

    private var detailTitle: String {
        switch item.kind { case .availability: "暇の詳細"; case .hosting: "募集中の時間"; case .plan: "予定の詳細" }
    }

    private var tint: Color {
        switch item.kind { case .availability: HimatchColor.availability; case .hosting: HimatchColor.hosting; case .plan: HimatchColor.plan }
    }
}
