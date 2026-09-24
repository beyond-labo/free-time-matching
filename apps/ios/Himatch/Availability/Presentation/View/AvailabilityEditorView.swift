import ComposableArchitecture
import SwiftUI

struct AvailabilityEditorView: View {
    let store: StoreOf<AvailabilityEditorFeature>

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HimatchSpacing.l) {
                    AvailabilitySummaryCard(store: store)
                    timeSection
                    durationSection
                    categorySection
                    visibilitySection
                    Label("暇を登録しても、参加OKや予定の確定にはなりません。", systemImage: "info.circle")
                        .font(HimatchFont.supporting)
                        .foregroundStyle(.secondary)
                }
                .padding(HimatchSpacing.m)
            }
            .background(HimatchColor.background)
            .safeAreaInset(edge: .bottom) { saveBar }
            .navigationTitle("暇を登録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { store.send(.closeTapped) }
                }
            }
            .interactiveDismissDisabled(store.isSaving)
        }
    }

    // MARK: Sections

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: HimatchSpacing.s) {
            SectionHeader("時間", subtitle: "15分単位で調整できます")
            TimeAdjustRow(
                title: "開始",
                date: store.start,
                range: store.earliestStart...max(store.earliestStart, store.latestEnd.addingTimeInterval(-AvailabilityPolicy.quarterHour)),
                calendar: store.calendar,
                badge: nil,
                canDecrease: store.canMoveStartEarlier,
                canIncrease: store.canMoveStartLater,
                onPick: { store.send(.startPicked($0)) },
                onStep: { store.send(.startStepped(quarters: $0)) }
            )
            TimeAdjustRow(
                title: "終了",
                date: store.end,
                range: min(store.start.addingTimeInterval(AvailabilityPolicy.quarterHour), store.latestEnd)...store.latestEnd,
                calendar: store.calendar,
                badge: store.isOvernight ? "翌日以降" : nil,
                canDecrease: store.canMoveEndEarlier,
                canIncrease: store.canMoveEndLater,
                onPick: { store.send(.endPicked($0)) },
                onStep: { store.send(.endStepped(quarters: $0)) }
            )
            if let issue = store.issue {
                ValidationMessage(issue: issue, store: store)
            }
            if let error = store.saveError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(HimatchFont.supporting)
                    .foregroundStyle(HimatchColor.danger)
                    .accessibilityLabel("保存できませんでした。\(error)")
            }
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: HimatchSpacing.s) {
            SectionHeader("長さ", subtitle: "開始からの長さで終了を合わせます")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HimatchSpacing.xs) {
                    ForEach(AvailabilityEditorFeature.State.durationPresets, id: \.self) { minutes in
                        SelectableChip(
                            title: AvailabilityFormatting.duration(TimeInterval(minutes * 60)),
                            isSelected: Int(store.duration / 60) == minutes
                        ) {
                            store.send(.presetTapped(minutes: minutes))
                        }
                        .disabled(!store.state.isPresetAvailable(minutes: minutes))
                        .opacity(store.state.isPresetAvailable(minutes: minutes) ? 1 : 0.4)
                    }
                }
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: HimatchSpacing.s) {
            SectionHeader("遊びたいこと", subtitle: "未選択のままでも登録できます")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HimatchSpacing.xs) {
                    SelectableChip(title: "未選択", isSelected: store.category == nil) {
                        store.send(.categoryChanged(nil))
                    }
                    ForEach(ActivityCategory.allCases, id: \.self) { category in
                        SelectableChip(
                            title: category.rawValue,
                            systemImage: category.systemImage,
                            isSelected: store.category == category
                        ) {
                            store.send(.categoryChanged(category))
                        }
                    }
                }
            }
        }
    }

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: HimatchSpacing.s) {
            SectionHeader("公開設定", subtitle: "新しい暇は毎回「参加OKするまで非公開」から始まります")
            ForEach(AvailabilityVisibility.allCases, id: \.self) { visibility in
                VisibilityOptionCard(
                    visibility: visibility,
                    isSelected: store.visibility == visibility
                ) {
                    store.send(.visibilityChanged(visibility))
                }
            }
        }
    }

    private var saveBar: some View {
        VStack(spacing: HimatchSpacing.xs) {
            Button {
                store.send(.saveTapped)
            } label: {
                if store.isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text("この時間で暇を登録")
                }
            }
            .buttonStyle(.himatchPrimary)
            .disabled(!store.canSave)
            .accessibilityHint(store.issue.map(\.message) ?? "")
        }
        .padding(.horizontal, HimatchSpacing.m)
        .padding(.vertical, HimatchSpacing.s)
        .background(.bar)
    }
}

// MARK: - Parts

private struct AvailabilitySummaryCard: View {
    let store: StoreOf<AvailabilityEditorFeature>

    var body: some View {
        let calendar = store.calendar
        VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: HimatchSpacing.xs) {
                Text(AvailabilityFormatting.time(store.start, calendar: calendar))
                Image(systemName: "arrow.right")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text((store.isOvernight ? "翌" : "") + AvailabilityFormatting.time(store.end, calendar: calendar))
            }
            .font(HimatchFont.hero.monospacedDigit())
            Text(AvailabilityFormatting.range(TimeIntervalRange(start: store.start, end: store.end), calendar: calendar))
                .font(HimatchFont.supporting)
                .foregroundStyle(.secondary)
            HStack(spacing: HimatchSpacing.xs) {
                StatusBadge(
                    title: AvailabilityFormatting.duration(store.duration),
                    systemImage: "hourglass",
                    tint: HimatchColor.availability
                )
                if store.isOvernight {
                    StatusBadge(title: "日付をまたぐ", systemImage: "moon.stars.fill", tint: HimatchColor.availability)
                }
            }
            Text("時刻は\(AvailabilityFormatting.timeZone(calendar, at: store.start))で表示しています")
                .font(HimatchFont.caption)
                .foregroundStyle(.secondary)
        }
        .himatchCard(tint: HimatchColor.availability)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "登録する時間 \(AvailabilityFormatting.range(TimeIntervalRange(start: store.start, end: store.end), calendar: calendar))、\(AvailabilityFormatting.duration(store.duration))"
        )
    }
}

private struct TimeAdjustRow: View {
    let title: String
    let date: Date
    let range: ClosedRange<Date>
    let calendar: Calendar
    let badge: String?
    let canDecrease: Bool
    let canIncrease: Bool
    let onPick: (Date) -> Void
    let onStep: (Int) -> Void

    @State private var isPickerExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: HimatchSpacing.s) {
            HStack(alignment: .top) {
                heading
                Spacer(minLength: HimatchSpacing.xs)
                Button {
                    withAnimation { isPickerExpanded.toggle() }
                } label: {
                    Image(systemName: isPickerExpanded ? "chevron.up" : "calendar.badge.clock")
                        .font(.title3)
                        .frame(width: HimatchMetrics.minTapTarget, height: HimatchMetrics.minTapTarget)
                        .background(Circle().fill(HimatchColor.tint(HimatchColor.accent)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(HimatchColor.accent)
                .accessibilityLabel(isPickerExpanded ? "\(title)日時の選択を閉じる" : "\(title)日時を選ぶ")
            }
            if isPickerExpanded {
                QuarterHourDatePicker(
                    selection: date,
                    range: range,
                    accessibilityLabel: "\(title)日時",
                    onChange: onPick
                )
                .frame(maxWidth: .infinity)
                .frame(height: QuarterHourDatePicker.height)
            }
            HStack(spacing: HimatchSpacing.xs) {
                Button { onStep(-1) } label: {
                    Label("15分早く", systemImage: "minus")
                }
                .buttonStyle(.himatchSecondary)
                .disabled(!canDecrease)
                .accessibilityLabel("\(title)を15分早くする")
                Button { onStep(1) } label: {
                    Label("15分遅く", systemImage: "plus")
                }
                .buttonStyle(.himatchSecondary)
                .disabled(!canIncrease)
                .accessibilityLabel("\(title)を15分遅くする")
            }
        }
        .himatchCard()
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: HimatchSpacing.xxs) {
            HStack(spacing: HimatchSpacing.xs) {
                Text(title).font(HimatchFont.cardTitle)
                if let badge {
                    StatusBadge(title: badge, systemImage: "moon.fill", tint: HimatchColor.availability)
                }
            }
            Text("\(AvailabilityFormatting.day(date, calendar: calendar)) \(AvailabilityFormatting.time(date, calendar: calendar))")
                .font(HimatchFont.emphasizedValue)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ValidationMessage: View {
    let issue: AvailabilityValidationError
    let store: StoreOf<AvailabilityEditorFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
            Label(issue.message, systemImage: "exclamationmark.circle.fill")
                .font(HimatchFont.supporting)
                .foregroundStyle(HimatchColor.danger)
            switch issue {
            case let .overlap(id):
                Button("重なっている暇を見る") { store.send(.conflictTapped(id)) }
                    .buttonStyle(.himatchSecondary(tint: HimatchColor.danger, fullWidth: false))
            case .past:
                Button("次の15分からに合わせる") { store.send(.snapToEarliestTapped) }
                    .buttonStyle(.himatchSecondary(tint: HimatchColor.danger, fullWidth: false))
            default:
                EmptyView()
            }
        }
        .padding(HimatchSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HimatchRadius.control, style: .continuous)
                .fill(HimatchColor.tint(HimatchColor.danger))
        )
    }
}

private struct VisibilityOptionCard: View {
    let visibility: AvailabilityVisibility
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: HimatchSpacing.s) {
                IconAvatar(systemImage: visibility.systemImage, size: 36)
                VStack(alignment: .leading, spacing: HimatchSpacing.xxs) {
                    Text(visibility.title)
                        .font(HimatchFont.cardTitle)
                        .foregroundStyle(.primary)
                    Text(visibility.explanation)
                        .font(HimatchFont.supporting)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? HimatchColor.accent : HimatchColor.secondaryText)
                    .accessibilityHidden(true)
            }
            .multilineTextAlignment(.leading)
            .padding(HimatchSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HimatchRadius.card, style: .continuous)
                    .fill(HimatchColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HimatchRadius.card, style: .continuous)
                    .strokeBorder(isSelected ? HimatchColor.accent : Color.clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: HimatchRadius.card))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
