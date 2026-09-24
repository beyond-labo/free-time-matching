import ComposableArchitecture
import SwiftUI

// MARK: - Selection on the grid

/// Translucent block for the picked range with start/end handles and a floating summary.
/// Invalid ranges switch to a red dashed outline with a warning icon and a short reason,
/// so the state never depends on color alone.
struct TimelineSelectionOverlay: View {
    let store: StoreOf<HomeTimelineFeature>
    let selection: HomeTimelineFeature.State.Selection
    let day: Date
    let hourHeight: CGFloat
    let width: CGFloat
    let coordinateSpace: String

    @Environment(\.calendar) private var calendar

    private var isValid: Bool { selection.issue == nil }
    private var tint: Color { isValid ? HimatchColor.accent : HimatchColor.danger }
    private var top: CGFloat { TimelineLayout.yOffset(for: selection.range.start, dayStart: day, hourHeight: hourHeight) }
    private var bottom: CGFloat { TimelineLayout.yOffset(for: selection.range.end, dayStart: day, hourHeight: hourHeight) }

    var body: some View {
        let height = max(bottom - top, 1)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: HimatchRadius.block, style: .continuous)
                .fill(tint.opacity(isValid ? 0.22 : 0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: HimatchRadius.block, style: .continuous)
                        .strokeBorder(tint, style: StrokeStyle(lineWidth: 2, dash: isValid ? [] : [6, 4]))
                )
                .frame(width: width, height: height)
                .offset(y: top)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(accessibilityValue)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: store.send(.selectionEdgeStepped(.end, quarters: 1))
                    case .decrement: store.send(.selectionEdgeStepped(.end, quarters: -1))
                    @unknown default: break
                    }
                }
                .accessibilityAction(named: "開始を15分早くする") { store.send(.selectionEdgeStepped(.start, quarters: -1)) }
                .accessibilityAction(named: "開始を15分遅くする") { store.send(.selectionEdgeStepped(.start, quarters: 1)) }
                .accessibilityAction(named: "終了を15分延ばす") { store.send(.selectionEdgeStepped(.end, quarters: 1)) }
                .accessibilityAction(named: "終了を15分縮める") { store.send(.selectionEdgeStepped(.end, quarters: -1)) }
                .accessibilityAction(named: "非公開で登録") { store.send(.quickSaveTapped) }
                .accessibilityAction(named: "詳細を調整") { store.send(.adjustDetailsTapped) }
                .accessibilityAction(named: "選択を取消") { store.send(.selectionCleared) }

            summaryBadge
                .fixedSize()
                .offset(x: HimatchSpacing.xs, y: top >= 34 ? top - 30 : bottom + 6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if !selection.isSaving {
                handle(.start)
                    .position(x: min(28, width / 2), y: top)
                handle(.end)
                    .position(x: max(width - 28, width / 2), y: bottom)
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    private var summaryBadge: some View {
        HStack(spacing: HimatchSpacing.xxs) {
            Image(systemName: isValid ? "lock.fill" : "exclamationmark.triangle.fill")
            Text(summaryText)
                .monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(isValid ? Color.primary : HimatchColor.danger)
        .padding(.horizontal, HimatchSpacing.xs)
        .padding(.vertical, HimatchSpacing.xxs)
        .background(
            Capsule(style: .continuous)
                .fill(HimatchColor.elevatedSurface)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        )
        .overlay(Capsule(style: .continuous).strokeBorder(tint.opacity(0.6), lineWidth: 1))
    }

    private var summaryText: String {
        let start = AvailabilityFormatting.time(selection.range.start, calendar: calendar)
        let end = AvailabilityFormatting.time(selection.range.end, calendar: calendar)
        let endText = calendar.isDate(selection.range.end, inSameDayAs: selection.range.start) ? end : "24:00"
        let base = "\(start)〜\(endText)・\(AvailabilityFormatting.duration(selection.range.duration))"
        if let issue = selection.issue { return "\(base)・\(issue.shortLabel)" }
        return base
    }

    private func handle(_ edge: SelectionEdge) -> some View {
        Circle()
            .fill(HimatchColor.elevatedSurface)
            .overlay(Circle().strokeBorder(tint, lineWidth: 2.5))
            .frame(width: 14, height: 14)
            .frame(width: HimatchMetrics.minTapTarget, height: HimatchMetrics.minTapTarget)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpace))
                    .onChanged { value in
                        let date = TimelineLayout.date(atY: value.location.y, dayStart: day, hourHeight: hourHeight)
                        store.send(.selectionEdgeDragged(edge, to: date))
                    }
            )
            .accessibilityHidden(true)
    }

    private var rangeText: String {
        AvailabilityFormatting.range(
            TimeIntervalRange(start: selection.range.start, end: selection.range.end),
            calendar: calendar
        )
    }

    private var accessibilityLabel: String {
        "選択中 \(rangeText)、\(AvailabilityFormatting.duration(selection.range.duration))"
    }

    private var accessibilityValue: String {
        if let issue = selection.issue { return "登録できません。\(issue.message)" }
        if selection.isSaving { return "登録中" }
        return "参加OKまで非公開で登録できます。上下にスワイプで終了を15分ずつ調整"
    }
}

// MARK: - Confirmation bar

/// Replaces the home action bar while a range is selected. Nothing is saved until the
/// primary button is tapped.
struct SelectionConfirmationBar: View {
    let store: StoreOf<HomeTimelineFeature>
    let selection: HomeTimelineFeature.State.Selection

    @Environment(\.calendar) private var calendar

    var body: some View {
        VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
            HStack(alignment: .top, spacing: HimatchSpacing.s) {
                VStack(alignment: .leading, spacing: HimatchSpacing.xxs) {
                    Text(rangeText)
                        .font(.headline.monospacedDigit())
                        .fixedSize(horizontal: false, vertical: true)
                    Label("参加OKまで非公開", systemImage: "lock.fill")
                        .font(HimatchFont.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { store.send(.selectionCleared) } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: HimatchMetrics.minTapTarget, height: HimatchMetrics.minTapTarget)
                        .background(Circle().fill(HimatchColor.unavailable))
                }
                .buttonStyle(.plain)
                .disabled(selection.isSaving)
                .accessibilityLabel("選択を取消")
            }
            if let issue = selection.issue {
                Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                    .font(HimatchFont.supporting)
                    .foregroundStyle(HimatchColor.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let error = selection.saveError {
                Label("登録できませんでした。\(error)", systemImage: "exclamationmark.triangle.fill")
                    .font(HimatchFont.supporting)
                    .foregroundStyle(HimatchColor.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: HimatchSpacing.s) {
                Button { store.send(.quickSaveTapped) } label: {
                    if selection.isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Label(selection.saveError == nil ? "非公開で登録" : "もう一度登録", systemImage: "lock.fill")
                    }
                }
                .buttonStyle(.himatchPrimary)
                .disabled(!selection.canQuickSave)
                .accessibilityHint(selection.issue.map(\.message) ?? "カテゴリ未選択・参加OKまで非公開で登録します")

                Button("詳細を調整") { store.send(.adjustDetailsTapped) }
                    .buttonStyle(.himatchSecondary(tint: HimatchColor.accent, fullWidth: false))
                    .frame(minHeight: HimatchMetrics.primaryButtonHeight)
                    .disabled(selection.isSaving)
                    .accessibilityHint("選んだ時間のまま、カテゴリや公開設定を編集します")
            }
        }
        .padding(.horizontal, HimatchSpacing.m)
        .padding(.vertical, HimatchSpacing.s)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background(.bar)
    }

    private var rangeText: String {
        let range = TimeIntervalRange(start: selection.range.start, end: selection.range.end)
        return "\(AvailabilityFormatting.range(range, calendar: calendar))・\(AvailabilityFormatting.duration(selection.range.duration))"
    }
}

// MARK: - Hint

/// Short affordance shown while nothing is selected.
struct TimelineSelectionHint: View {
    let mode: HomeTimelineFeature.State.Mode

    var body: some View {
        Label(
            mode == .day ? "タップで15分／長押ししてなぞると範囲選択" : "時間をタップすると日表示で選べます",
            systemImage: "hand.tap"
        )
        .font(HimatchFont.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, HimatchSpacing.m)
        .padding(.vertical, HimatchSpacing.xxs)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}
