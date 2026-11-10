import ComposableArchitecture
import SwiftUI

/// 「友達を誘う」: いつ・だれと・会い方・なにする on one screen, with the send button fixed at the bottom (5.1–5.11).
struct InvitationComposerView: View {
    @Bindable var store: StoreOf<InvitationComposerFeature>
    @Environment(\.calendar) private var calendar

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HimatchSpacing.l) {
                    whenSection
                    whoSection
                    meetingSection
                    whatSection
                    if store.availabilityConflict != nil { conflictSection }
                }
                .padding(HimatchSpacing.m)
            }
            .background(HimatchColor.background)
            .safeAreaInset(edge: .bottom) { footer }
            .navigationTitle("友達を誘う")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { store.send(.closeTapped) }
                }
            }
            .interactiveDismissDisabled(store.isSubmitting)
        }
    }

    // MARK: いつ

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: HimatchSpacing.s) {
            SectionHeader("いつ")
            FlowLayout(spacing: HimatchSpacing.xs) {
                ForEach(store.candidates) { candidate in
                    CandidateChip(
                        title: candidate.title,
                        detail: AvailabilityFormatting.friendlyRange(candidate.range, calendar: calendar, now: store.now),
                        isSelected: store.selectedCandidateID == candidate.id
                    ) { store.send(.candidateSelected(candidate.id)) }
                }
                CandidateChip(title: "日時を選ぶ", detail: "14日先まで", isSelected: store.isCustomTime) {
                    store.send(.customTimeSelected)
                }
            }
            if store.isCustomTime, let range = store.range { customPicker(range) }
            if let range = store.range {
                Text(AvailabilityFormatting.friendlyRange(TimeIntervalRange(start: range.start, end: range.end), calendar: calendar, now: store.now))
                    .font(HimatchFont.emphasizedValue)
                    .accessibilityLabel("選んだ日時 \(AvailabilityFormatting.range(TimeIntervalRange(start: range.start, end: range.end), calendar: calendar))")
            }
        }
        .himatchCard()
    }

    private func customPicker(_ range: QuarterRange) -> some View {
        let today = calendar.startOfDay(for: store.now)
        let days = (0..<14).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        let earliest = AvailabilityPolicy.nextQuarterHour(after: store.now, calendar: calendar)
        let dayStart = calendar.startOfDay(for: range.start)
        let dayEnd = min(calendar.date(byAdding: .day, value: 1, to: dayStart) ?? range.end, AvailabilityPolicy.latestEnd(now: store.now, calendar: calendar))
        let starts = stride(from: dayStart, to: dayEnd, by: AvailabilityPolicy.quarterHour).filter { $0 >= earliest }
        let ends = stride(from: range.start.addingTimeInterval(AvailabilityPolicy.quarterHour), through: dayEnd, by: AvailabilityPolicy.quarterHour).map { $0 }
        return VStack(alignment: .leading, spacing: HimatchSpacing.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HimatchSpacing.xxs) {
                    ForEach(days, id: \.self) { day in
                        let selected = calendar.isDate(day, inSameDayAs: range.start)
                        Button { store.send(.daySelected(day)) } label: {
                            VStack(spacing: 2) {
                                Text(calendar.isDate(day, inSameDayAs: today) ? "今日" : AvailabilityFormatting.weekday(day, calendar: calendar))
                                    .font(.caption2.weight(.semibold))
                                Text("\(calendar.component(.day, from: day))").font(.headline.monospacedDigit())
                            }
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .frame(minWidth: HimatchMetrics.minTapTarget, minHeight: 52)
                            .background(RoundedRectangle(cornerRadius: HimatchRadius.control).fill(selected ? HimatchColor.accent : HimatchColor.elevatedSurface))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AvailabilityFormatting.day(day, calendar: calendar))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            HStack(spacing: HimatchSpacing.s) {
                Picker("開始", selection: Binding(get: { range.start }, set: { store.send(.startChanged($0)) })) {
                    ForEach(starts, id: \.self) { Text(AvailabilityFormatting.time($0, calendar: calendar)).tag($0) }
                }
                Text("〜").foregroundStyle(.secondary)
                Picker("終了", selection: Binding(get: { range.end }, set: { store.send(.endChanged($0)) })) {
                    ForEach(ends, id: \.self) { Text(AvailabilityFormatting.time($0, calendar: calendar)).tag($0) }
                }
            }
            .pickerStyle(.menu)
            .frame(minHeight: HimatchMetrics.minTapTarget)
            Text("日付をまたぐ時間はカレンダーから選べます。")
                .font(HimatchFont.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: だれと

    private var whoSection: some View {
        VStack(alignment: .leading, spacing: HimatchSpacing.s) {
            HStack {
                SectionHeader("だれと")
                Button(store.allFriendsSelected ? "選択を解除" : "全員を選ぶ") { store.send(.allFriendsToggled) }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: HimatchMetrics.minTapTarget)
            }
            FlowLayout(spacing: HimatchSpacing.s) {
                ForEach(store.friends) { friend in
                    let selected = store.selectedFriendIDs.contains(friend.id)
                    Button { store.send(.friendToggled(friend.id)) } label: {
                        VStack(spacing: HimatchSpacing.xxs) {
                            IconAvatar(systemImage: friend.icon, size: 52, tint: selected ? HimatchColor.accent : HimatchColor.secondaryText)
                                .overlay(alignment: .bottomTrailing) {
                                    if selected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.white, HimatchColor.accent)
                                            .accessibilityHidden(true)
                                    }
                                }
                            Text(friend.displayName).font(.caption).lineLimit(1)
                        }
                        .frame(minWidth: 60, minHeight: HimatchMetrics.minTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(friend.displayName)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .himatchCard()
    }

    // MARK: 会い方・なにする

    private var meetingSection: some View {
        VStack(alignment: .leading, spacing: HimatchSpacing.s) {
            SectionHeader("会い方")
            HStack(spacing: HimatchSpacing.xs) {
                ForEach(HostingMode.allCases, id: \.self) { mode in
                    SelectableChip(title: mode.displayName, systemImage: mode == .online ? "video" : "figure.2", isSelected: store.mode == mode) {
                        store.send(.modeSelected(mode))
                    }
                }
            }
            if store.mode == .offline {
                FlowLayout(spacing: HimatchSpacing.xs) {
                    ForEach(HostingArea.allCases, id: \.self) { area in
                        SelectableChip(title: area.rawValue, systemImage: "mappin", isSelected: store.area == area) {
                            store.send(.areaSelected(area))
                        }
                    }
                }
            }
        }
        .himatchCard()
    }

    private var whatSection: some View {
        VStack(alignment: .leading, spacing: HimatchSpacing.s) {
            SectionHeader("なにする", subtitle: "任意")
            FlowLayout(spacing: HimatchSpacing.xs) {
                ForEach(ActivityCategory.allCases, id: \.self) { category in
                    SelectableChip(title: category.rawValue, systemImage: category.systemImage, isSelected: store.category == category) {
                        store.send(.categoryToggled(category))
                    }
                }
            }
        }
        .himatchCard()
    }

    private var conflictSection: some View {
        VStack(alignment: .leading, spacing: HimatchSpacing.s) {
            Label("この時間は、設定の違うあなたの暇とつながります", systemImage: "exclamationmark.triangle")
                .font(HimatchFont.cardTitle)
            Text("つながったあとの暇の設定を選んでください。友達に暇が見えることはありません。")
                .font(HimatchFont.supporting).foregroundStyle(.secondary)
            FlowLayout(spacing: HimatchSpacing.xs) {
                ForEach(ActivityCategory.allCases, id: \.self) { category in
                    let chosen = store.availabilityConflict?.chosen
                    SelectableChip(title: category.rawValue, systemImage: category.systemImage, isSelected: chosen?.category == category) {
                        store.send(.availabilityMetadataChosen(
                            chosen?.category == category ? nil : category,
                            chosen?.visibility ?? .privateUntilAccepted
                        ))
                    }
                }
            }
            ForEach(AvailabilityVisibility.allCases, id: \.self) { visibility in
                let chosen = store.availabilityConflict?.chosen?.visibility == visibility
                SelectableChip(title: visibility.title, systemImage: visibility.systemImage, isSelected: chosen) {
                    store.send(.availabilityMetadataChosen(store.availabilityConflict?.chosen?.category, visibility))
                }
            }
        }
        .himatchCard(tint: HimatchColor.attention)
    }

    // MARK: 送信

    private var footer: some View {
        VStack(spacing: HimatchSpacing.xs) {
            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(HimatchFont.supporting).foregroundStyle(HimatchColor.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let missing = store.missingItem {
                Text(missing.message).font(HimatchFont.supporting).foregroundStyle(.secondary)
            } else {
                Text("\(store.selectedFriends.map { "\($0.displayName)さん" }.joined(separator: "・")) に送ります")
                    .font(HimatchFont.supporting.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            Button {
                store.send(.submitTapped)
            } label: {
                if store.isSubmitting { ProgressView().tint(.white) } else { Label("お誘いを送る", systemImage: "paperplane.fill") }
            }
            .buttonStyle(.himatchPrimary)
            .disabled(!store.canSubmit)
            Text("選んだ友達全員に、相手の暇の有無に関係なく届きます。この時間はあなたの暇（非公開）にも入ります。")
                .font(HimatchFont.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, HimatchSpacing.m)
        .padding(.vertical, HimatchSpacing.s)
        .background(.bar)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

/// Two-line chip for time candidates.
struct CandidateChip: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption.monospacedDigit()).foregroundStyle(isSelected ? HimatchColor.accent : .secondary)
            }
            .foregroundStyle(isSelected ? HimatchColor.accent : Color.primary)
            .padding(.horizontal, HimatchSpacing.s)
            .padding(.vertical, HimatchSpacing.xs)
            .frame(minHeight: HimatchMetrics.minTapTarget, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: HimatchRadius.control, style: .continuous)
                .fill(isSelected ? HimatchColor.tint(HimatchColor.accent) : HimatchColor.elevatedSurface))
            .overlay(RoundedRectangle(cornerRadius: HimatchRadius.control, style: .continuous)
                .strokeBorder(isSelected ? HimatchColor.accent : HimatchColor.separator, lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Wrapping row layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = Self.size(of: view, maxWidth: width)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = Self.size(of: view, maxWidth: bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    /// Never wider than the container, so large Dynamic Type wraps inside a chip instead of overflowing.
    private static func size(of view: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = view.sizeThatFits(.unspecified)
        guard ideal.width > maxWidth, maxWidth.isFinite else { return ideal }
        return view.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }
}
