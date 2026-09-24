import ComposableArchitecture
import SwiftUI
import UIKit

// MARK: - Day

/// 24-hour vertical grid for one day with direct selection:
/// - tap selects the 15 minutes under the finger;
/// - a 0.3 s long press, then an up/down drag, selects a continuous range snapped to 15 minutes;
/// - a vertical swipe that starts moving before the press completes keeps scrolling.
/// Raw finger positions and the in-progress press stay in the View (gesture surface coordinator
/// and `isPressing`); only dates reach the reducer, which snaps them to 15 minutes.
/// VoiceOver uses per-hour row actions instead of gestures.
struct TimelineDayView: View {
    let store: StoreOf<HomeTimelineFeature>
    let day: Date
    let segments: [TimelineSegment]
    let now: Date
    let latestEnd: Date

    static let gridSpace = "timelineDayGrid"
    static let longPressDuration = 0.3
    static let longPressMaximumDistance: CGFloat = 10

    @Environment(\.calendar) private var calendar
    @ScaledMetric(relativeTo: .body) private var scaledHourHeight: CGFloat = 60
    @ScaledMetric(relativeTo: .caption) private var gutterWidth: CGFloat = 44
    @State private var isPressing = false

    private var hourHeight: CGFloat { max(scaledHourHeight, HimatchMetrics.minTapTarget) }
    private var dayHeight: CGFloat { hourHeight * 24 }
    private var gridLeading: CGFloat { gutterWidth + HimatchSpacing.xs }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { hour in
                            DayHourRow(
                                hour: hour,
                                day: day,
                                now: now,
                                latestEnd: latestEnd,
                                hourHeight: hourHeight,
                                gutterWidth: gutterWidth,
                                onSelectQuarter: { store.send(.quarterTapped($0)) }
                            )
                            .id(hour)
                        }
                    }
                    canvas
                        .padding(.leading, gridLeading)
                        .padding(.trailing, HimatchSpacing.xs)
                }
                .padding(.vertical, HimatchSpacing.s)
            }
            .onAppear { scroll(proxy) }
            .onChange(of: day) { scroll(proxy) }
            .onChange(of: store.selectedItem) { scroll(proxy) }
        }
    }

    /// Interaction layer over the grid area. Ordered bottom to top: shading, guides, gesture
    /// surface, existing blocks (their buttons win), selection with handles, now line.
    private var canvas: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                unavailableShading(width: width)
                QuarterGuides(hourHeight: hourHeight, emphasized: isPressing || store.selection != nil)
                    .stroked()
                    .frame(width: width, height: dayHeight)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                gestureSurface
                ForEach(segments) { segment in
                    let laneWidth = width / CGFloat(max(segment.laneCount, 1))
                    let top = TimelineLayout.yOffset(for: segment.start, dayStart: day, hourHeight: hourHeight)
                    let bottom = TimelineLayout.yOffset(for: segment.end, dayStart: day, hourHeight: hourHeight)
                    TimelineBlockView(
                        segment: segment,
                        compact: bottom - top < 36,
                        isRecentlySaved: store.lastSavedItem == segment.id
                    ) {
                        store.send(.itemTapped(segment.id))
                    }
                    .frame(width: max(laneWidth - 2, 0), height: max(bottom - top - 1, 18))
                    .offset(x: CGFloat(segment.lane) * laneWidth, y: top)
                }
                if let selection = store.selection,
                   calendar.isDate(selection.range.start, inSameDayAs: day) {
                    TimelineSelectionOverlay(
                        store: store,
                        selection: selection,
                        day: day,
                        hourHeight: hourHeight,
                        width: width,
                        coordinateSpace: Self.gridSpace
                    )
                }
                if calendar.isDate(now, inSameDayAs: day) {
                    NowIndicator()
                        .frame(width: width + 6)
                        .offset(x: -6, y: TimelineLayout.yOffset(for: now, dayStart: day, hourHeight: hourHeight) - 4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(height: dayHeight)
        .coordinateSpace(name: Self.gridSpace)
    }

    /// UIKit recognizers on a transparent view that covers the grid area (see
    /// `TimelineSelectionGestureSurface` for why this is not a SwiftUI gesture).
    /// Its y coordinate equals the offset from the start of the day.
    private var gestureSurface: some View {
        TimelineSelectionGestureSurface(
            onTap: { y in
                store.send(.quarterTapped(date(atY: y)))
            },
            onSelect: { anchorY, focusY in
                store.send(.rangeSelectionChanged(anchor: date(atY: anchorY), focus: date(atY: focusY)))
            },
            onPressingChanged: { isPressing = $0 }
        )
        .frame(height: dayHeight)
        .accessibilityHidden(true)
    }

    private func date(atY y: CGFloat) -> Date {
        TimelineLayout.date(atY: y, dayStart: day, hourHeight: hourHeight)
    }

    @ViewBuilder
    private func unavailableShading(width: CGFloat) -> some View {
        let dayRange = TimelineLayout.dayRange(for: day, calendar: calendar)
        let pastEnd = min(max(now, dayRange.start), dayRange.end)
        let futureStart = max(min(latestEnd, dayRange.end), dayRange.start)
        let pastHeight = TimelineLayout.yOffset(for: pastEnd, dayStart: day, hourHeight: hourHeight)
        let futureTop = TimelineLayout.yOffset(for: futureStart, dayStart: day, hourHeight: hourHeight)
        let fullHeight = TimelineLayout.yOffset(for: dayRange.end, dayStart: day, hourHeight: hourHeight)
        ZStack(alignment: .topLeading) {
            if pastHeight > 0 {
                Rectangle().fill(HimatchColor.unavailable).frame(width: width, height: pastHeight)
            }
            if futureTop < fullHeight {
                Rectangle()
                    .fill(HimatchColor.unavailable)
                    .frame(width: width, height: fullHeight - futureTop)
                    .offset(y: futureTop)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        let targetHour: Int
        if let focusedItem = store.selectedItem, let segment = segments.first(where: { $0.id == focusedItem }) {
            targetHour = calendar.component(.hour, from: segment.start)
        } else if let selection = store.selection, calendar.isDate(selection.range.start, inSameDayAs: day) {
            targetHour = calendar.component(.hour, from: selection.range.start)
        } else if calendar.isDate(now, inSameDayAs: day) {
            targetHour = calendar.component(.hour, from: now)
        } else if let first = segments.first {
            targetHour = calendar.component(.hour, from: first.start)
        } else {
            targetHour = 9
        }
        proxy.scrollTo(max(targetHour - 1, 0), anchor: .top)
    }
}

/// Pure bookkeeping for one long-press session: the anchor is fixed where the press was
/// recognized, and every later position extends the range from that anchor.
struct TimelinePressTracker: Equatable {
    private(set) var anchorY: CGFloat?

    var isPressing: Bool { anchorY != nil }

    /// Long press recognized: select the quarter under the finger, even without movement.
    mutating func began(at y: CGFloat) -> (anchorY: CGFloat, focusY: CGFloat) {
        anchorY = y
        return (y, y)
    }

    /// Finger moved after recognition. Nil when no press session is active.
    func moved(to y: CGFloat) -> (anchorY: CGFloat, focusY: CGFloat)? {
        anchorY.map { ($0, y) }
    }

    mutating func ended() {
        anchorY = nil
    }
}

/// Transparent UIKit view carrying the tap and long-press recognizers of the day grid.
///
/// Recognizer ownership (all three see the same touch because the enclosing `UIScrollView`
/// is an ancestor of this view):
/// - `UIScrollView.panGestureRecognizer`: owns any touch that moves beyond the pan slop
///   before 0.3 s. When it begins, UIKit fails the still-possible long press and tap
///   (default exclusivity, no simultaneous delegate), so ordinary swipes scroll at once.
/// - `UILongPressGestureRecognizer` (0.3 s, 10 pt allowable movement): if the finger stays
///   still for 0.3 s it begins first, and by the same exclusivity the pan in `.possible`
///   fails for this touch sequence, so the following drag edits the range without scrolling.
/// - `UITapGestureRecognizer`: requires the long press to fail, so a quick touch-up selects
///   15 minutes and a held press never also fires a tap.
/// SwiftUI views stacked above this surface (existing blocks, selection handles) win SwiftUI
/// hit testing and keep their own buttons and drags.
struct TimelineSelectionGestureSurface: UIViewRepresentable {
    let onTap: (CGFloat) -> Void
    let onSelect: (_ anchorY: CGFloat, _ focusY: CGFloat) -> Void
    let onPressingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = TimelineDayView.longPressDuration
        longPress.allowableMovement = TimelineDayView.longPressMaximumDistance

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.require(toFail: longPress)

        view.addGestureRecognizer(longPress)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: TimelineSelectionGestureSurface
        private var tracker = TimelinePressTracker()

        init(parent: TimelineSelectionGestureSurface) {
            self.parent = parent
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            parent.onTap(recognizer.location(in: recognizer.view).y)
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            let y = recognizer.location(in: recognizer.view).y
            switch recognizer.state {
            case .began:
                let range = tracker.began(at: y)
                parent.onPressingChanged(true)
                parent.onSelect(range.anchorY, range.focusY)
            case .changed:
                if let range = tracker.moved(to: y) {
                    parent.onSelect(range.anchorY, range.focusY)
                }
            case .ended, .cancelled, .failed:
                tracker.ended()
                parent.onPressingChanged(false)
            default:
                break
            }
        }
    }
}

private struct DayHourRow: View {
    let hour: Int
    let day: Date
    let now: Date
    let latestEnd: Date
    let hourHeight: CGFloat
    let gutterWidth: CGFloat
    let onSelectQuarter: (Date) -> Void

    @Environment(\.calendar) private var calendar

    var body: some View {
        let quarters = (0..<TimelineLayout.quartersPerHour).map {
            TimelineLayout.date(hour: hour, quarter: $0, on: day, calendar: calendar)
        }
        let hasRegistrableQuarter = quarters.contains {
            $0.addingTimeInterval(AvailabilityPolicy.quarterHour) > now && $0 < latestEnd
        }
        HStack(alignment: .top, spacing: HimatchSpacing.xs) {
            Text(AvailabilityFormatting.time(quarters[0], calendar: calendar))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: gutterWidth, alignment: .trailing)
                .offset(y: -6)
            Rectangle()
                .fill(HimatchColor.gridLine)
                .frame(height: 0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.trailing, HimatchSpacing.xs)
        .frame(height: hourHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(AvailabilityFormatting.day(day, calendar: calendar)) \(hour)時台")
        .accessibilityValue(hasRegistrableQuarter ? "空き" : "登録できない時間")
        .accessibilityHint("ダブルタップで\(AvailabilityFormatting.time(quarters[0], calendar: calendar))からの15分を選択します。ほかの15分は操作から選べます")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onSelectQuarter(quarters[0]) }
        .accessibilityActions {
            ForEach(quarters.dropFirst(), id: \.self) { date in
                Button("\(AvailabilityFormatting.time(date, calendar: calendar))からの15分を選択") { onSelectQuarter(date) }
            }
        }
    }
}

/// Quarter-hour guide lines; stronger while a selection is being made or shown.
private struct QuarterGuides: Shape {
    let hourHeight: CGFloat
    let emphasized: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let quarterHeight = hourHeight / CGFloat(TimelineLayout.quartersPerHour)
        for index in 0..<(24 * TimelineLayout.quartersPerHour) where index % TimelineLayout.quartersPerHour != 0 {
            let y = CGFloat(index) * quarterHeight
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

extension QuarterGuides {
    func stroked() -> some View {
        stroke(
            HimatchColor.gridLine.opacity(emphasized ? 0.9 : 0.35),
            style: StrokeStyle(lineWidth: 0.5, dash: [3, 3])
        )
    }
}

private struct NowIndicator: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle().fill(HimatchColor.danger).frame(width: 8, height: 8)
            Rectangle().fill(HimatchColor.danger).frame(height: 1.5)
        }
    }
}

// MARK: - Week

/// Seven day columns inside the 14-day window. Hour cells are ≥44pt; tapping one opens the day
/// view with that hour's first quarter selected.
struct TimelineWeekView: View {
    let days: [Date]
    let items: [HomeScheduleItem]
    let now: Date
    let latestEnd: Date
    let onSelectTime: (Date) -> Void
    let onTapItem: (HomeTimelineFeature.State.Item) -> Void
    let onSelectDay: (Date) -> Void

    @Environment(\.calendar) private var calendar
    @ScaledMetric(relativeTo: .body) private var hourHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var gutterWidth: CGFloat = 36

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: gutterWidth)
                ForEach(days, id: \.self) { day in
                    Button { onSelectDay(day) } label: {
                        VStack(spacing: 0) {
                            Text(AvailabilityFormatting.weekday(day, calendar: calendar))
                                .font(.caption2)
                            Text("\(calendar.component(.day, from: day))")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                        .foregroundStyle(calendar.isDate(day, inSameDayAs: now) ? HimatchColor.accent : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: HimatchMetrics.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(AvailabilityFormatting.day(day, calendar: calendar))を日表示で開く")
                }
            }
            .padding(.trailing, HimatchSpacing.xs)
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    grid
                        .padding(.vertical, HimatchSpacing.s)
                }
                .onAppear { proxy.scrollTo(max(calendar.component(.hour, from: now) - 1, 0), anchor: .top) }
            }
        }
    }

    private var grid: some View {
        let height = max(hourHeight, HimatchMetrics.minTapTarget)
        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    Text("\(hour)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: gutterWidth, height: height, alignment: .topTrailing)
                        .padding(.trailing, 4)
                        .offset(y: -6)
                        .id(hour)
                        .accessibilityHidden(true)
                }
            }
            ForEach(days, id: \.self) { day in
                WeekDayColumn(
                    day: day,
                    segments: TimelineLayout.segments(for: items, on: day, calendar: calendar),
                    now: now,
                    latestEnd: latestEnd,
                    hourHeight: height,
                    onSelectTime: onSelectTime,
                    onTapItem: onTapItem
                )
            }
        }
        .padding(.trailing, HimatchSpacing.xs)
    }
}

private struct WeekDayColumn: View {
    let day: Date
    let segments: [TimelineSegment]
    let now: Date
    let latestEnd: Date
    let hourHeight: CGFloat
    let onSelectTime: (Date) -> Void
    let onTapItem: (HomeTimelineFeature.State.Item) -> Void

    @Environment(\.calendar) private var calendar

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                let start = TimelineLayout.date(hour: hour, on: day, calendar: calendar)
                let registrable = start.addingTimeInterval(3600) > now && start < latestEnd
                Rectangle()
                    .fill(registrable ? Color.clear : HimatchColor.unavailable)
                    .overlay(alignment: .top) { Rectangle().fill(HimatchColor.gridLine).frame(height: 0.5) }
                    .overlay(alignment: .leading) { Rectangle().fill(HimatchColor.gridLine).frame(width: 0.5) }
                    .frame(height: hourHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelectTime(start) }
                    .accessibilityElement()
                    .accessibilityLabel("\(AvailabilityFormatting.day(day, calendar: calendar)) \(hour)時台")
                    .accessibilityValue(registrable ? "空き" : "登録できない時間")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("日表示へ移り、この時間の15分を選択します")
            }
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ForEach(segments) { segment in
                        let laneWidth = geometry.size.width / CGFloat(max(segment.laneCount, 1))
                        let top = TimelineLayout.yOffset(for: segment.start, dayStart: day, hourHeight: hourHeight)
                        let bottom = TimelineLayout.yOffset(for: segment.end, dayStart: day, hourHeight: hourHeight)
                        TimelineBlockView(segment: segment, compact: true) { onTapItem(segment.id) }
                            .frame(width: max(laneWidth - 2, 0), height: max(bottom - top - 1, 14))
                            .offset(x: CGFloat(segment.lane) * laneWidth + 1, y: top)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Agenda (accessibility text sizes)

/// Replaces the week grid at accessibility text sizes where seven columns cannot fit text.
struct TimelineAgendaView: View {
    let days: [Date]
    let items: [HomeScheduleItem]
    let now: Date
    let latestEnd: Date
    let onSelectTime: (Date) -> Void
    let onTapItem: (HomeTimelineFeature.State.Item) -> Void

    @Environment(\.calendar) private var calendar

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: HimatchSpacing.m) {
                ForEach(days, id: \.self) { day in
                    let segments = TimelineLayout.segments(for: items, on: day, calendar: calendar)
                    VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
                        SectionHeader(AvailabilityFormatting.day(day, calendar: calendar))
                        if segments.isEmpty {
                            Text("登録された暇や予定はありません")
                                .font(HimatchFont.supporting)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(segments) { segment in
                            Button { onTapItem(segment.id) } label: {
                                Label(
                                    "\(segment.item.title) \(AvailabilityFormatting.range(segment.item.interval, calendar: calendar))",
                                    systemImage: segment.item.systemImage
                                )
                                .frame(maxWidth: .infinity, minHeight: HimatchMetrics.minTapTarget, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                        let anchor = calendar.isDate(day, inSameDayAs: now)
                            ? AvailabilityPolicy.nextQuarterHour(after: now, calendar: calendar)
                            : TimelineLayout.date(hour: 10, on: day, calendar: calendar)
                        if calendar.isDate(anchor, inSameDayAs: day), anchor < latestEnd {
                            Button("この日の時間を選ぶ") { onSelectTime(anchor) }
                                .buttonStyle(.himatchSecondary)
                        }
                    }
                    .himatchCard()
                }
            }
            .padding(HimatchSpacing.m)
        }
    }
}

// MARK: - Block

struct TimelineBlockView: View {
    let segment: TimelineSegment
    let compact: Bool
    var isRecentlySaved = false
    let action: () -> Void

    @Environment(\.calendar) private var calendar

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Rectangle().fill(color).frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: isRecentlySaved ? "checkmark.circle.fill" : segment.item.systemImage)
                            .font(.caption2)
                        Text(segment.item.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        if case let .availability(visibility) = segment.item.kind {
                            Image(systemName: visibility.systemImage)
                                .font(.caption2)
                        }
                    }
                    if !compact {
                        Text(timeText)
                            .font(.caption2.monospacedDigit())
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                Spacer(minLength: 0)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(color.opacity(isRecentlySaved ? 0.28 : 0.18))
            .clipShape(RoundedRectangle(cornerRadius: HimatchRadius.block, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HimatchRadius.block, style: .continuous)
                    .strokeBorder(isRecentlySaved ? color : Color.clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: HimatchRadius.block))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("詳細を表示します")
    }

    private var color: Color {
        switch segment.item.kind {
        case .availability: HimatchColor.availability
        case .plan: HimatchColor.plan
        }
    }

    private var timeText: String {
        let start = AvailabilityFormatting.time(segment.item.interval.start, calendar: calendar)
        let end = AvailabilityFormatting.time(segment.item.interval.end, calendar: calendar)
        let prefix = segment.continuesFromPreviousDay ? "前日" : ""
        let suffix = segment.continuesToNextDay ? "翌" : ""
        return "\(prefix)\(start)〜\(suffix)\(end)"
    }

    private var accessibilityText: String {
        let kind: String
        switch segment.item.kind {
        case let .availability(visibility): kind = "暇、\(visibility.title)"
        case .plan: kind = "確定した予定"
        }
        let saved = isRecentlySaved ? "、登録しました" : ""
        return "\(segment.item.title)、\(AvailabilityFormatting.range(segment.item.interval, calendar: calendar))、\(kind)\(saved)"
    }
}
