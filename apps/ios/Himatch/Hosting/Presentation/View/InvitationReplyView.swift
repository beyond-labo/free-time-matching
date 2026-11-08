import ComposableArchitecture
import SwiftUI

/// Reply to an invitation: pick 全部・前半・後半・時間を指定 and send 参加OK in one tap (7.1–7.10).
struct InvitationReplyView: View {
    @Bindable var store: StoreOf<InvitationReplyFeature>
    let profileName: String

    @Environment(\.calendar) private var calendar

    private var invitation: Hosting { store.invitation }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HimatchSpacing.l) {
                    header
                    if store.canRespond {
                        choices
                        if let range = store.selectedRange {
                            CandidateTimeBar(candidate: invitation.candidateRange, highlights: [range])
                        }
                        InfoRow(
                            icon: "person.crop.circle.badge.checkmark",
                            title: "参加OKで伝わること",
                            detail: "選んだ時間と表示名「\(profileName)」が\(hostName)さんに伝わります。期限までは変更・取り消しができます。"
                        )
                    } else {
                        StatusBadge(title: invitation.status == .cancelled ? "取り消されました" : "返事の期限を過ぎました", systemImage: "xmark.circle", tint: HimatchColor.secondaryText)
                    }
                }
                .padding(HimatchSpacing.m)
            }
            .background(HimatchColor.background)
            .safeAreaInset(edge: .bottom) { if store.canRespond { footer } }
            .navigationTitle("お誘いに返事")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { store.send(.closeTapped) } }
            }
        }
    }

    private var hostName: String { invitation.host?.displayName ?? "主催者" }

    private var header: some View {
        VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
            HStack(spacing: HimatchSpacing.s) {
                IconAvatar(systemImage: invitation.host?.icon ?? "person.fill", size: 40, tint: HimatchColor.hosting)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(hostName)さんから").font(HimatchFont.cardTitle)
                    Text(invitation.summary).font(HimatchFont.supporting).foregroundStyle(.secondary)
                }
            }
            Text(AvailabilityFormatting.friendlyRange(invitation.candidateRange, calendar: calendar, now: store.now))
                .font(HimatchFont.emphasizedValue)
            Text("返事の期限 \(AvailabilityFormatting.friendlyMoment(invitation.answerDeadline, calendar: calendar, now: store.now))まで")
                .font(HimatchFont.supporting).foregroundStyle(HimatchColor.hosting)
        }
        .himatchCard(tint: HimatchColor.hosting)
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
            SectionHeader("参加できる時間")
            ForEach(store.presets, id: \.choice) { preset in
                ChoiceRow(
                    title: preset.choice.title,
                    detail: AvailabilityFormatting.timeSpan(preset.range, calendar: calendar),
                    isSelected: store.choice == preset.choice
                ) { store.send(.choiceSelected(preset.choice)) }
            }
            ChoiceRow(title: ReplyChoice.custom.title, detail: nil, isSelected: store.choice == .custom) {
                store.send(.choiceSelected(.custom))
            }
            if store.choice == .custom {
                let candidate = invitation.candidateRange
                HStack(spacing: HimatchSpacing.s) {
                    Picker("開始", selection: Binding(get: { store.customRange.start }, set: { store.send(.customStartChanged($0)) })) {
                        ForEach(ReplyChoicePolicy.customStarts(in: candidate), id: \.self) {
                            Text(AvailabilityFormatting.time($0, calendar: calendar)).tag($0)
                        }
                    }
                    Text("〜").foregroundStyle(.secondary)
                    Picker("終了", selection: Binding(get: { store.customRange.end }, set: { store.send(.customEndChanged($0)) })) {
                        ForEach(ReplyChoicePolicy.customEnds(in: candidate, after: store.customRange.start), id: \.self) {
                            Text(AvailabilityFormatting.time($0, calendar: calendar)).tag($0)
                        }
                    }
                }
                .pickerStyle(.menu)
                .frame(minHeight: HimatchMetrics.minTapTarget)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: HimatchSpacing.xs) {
            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(HimatchFont.supporting).foregroundStyle(HimatchColor.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { store.send(.acceptTapped) } label: {
                if store.isSubmitting {
                    ProgressView().tint(.white)
                } else if let range = store.selectedRange {
                    Text("\(AvailabilityFormatting.timeSpan(range, calendar: calendar)) で参加OK")
                } else {
                    Text("参加できる時間を選んでください")
                }
            }
            .buttonStyle(.himatchPrimary)
            .disabled(!store.canAccept)
            if store.hasAccepted {
                Button("参加OKを取り消す", role: .destructive) { store.send(.withdrawTapped) }
                    .frame(minHeight: HimatchMetrics.minTapTarget)
                    .disabled(store.isSubmitting)
            } else {
                Button("今回は見送る（\(hostName)さんには通知されません）") { store.send(.declineTapped) }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: HimatchMetrics.minTapTarget)
                    .disabled(store.isSubmitting)
            }
        }
        .padding(.horizontal, HimatchSpacing.m)
        .padding(.vertical, HimatchSpacing.s)
        .background(.bar)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

private struct ChoiceRow: View {
    let title: String
    let detail: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.body.weight(.semibold))
                if let detail { Text(detail).font(.body.monospacedDigit()).foregroundStyle(.secondary) }
                Spacer()
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? HimatchColor.accent : HimatchColor.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, HimatchSpacing.m)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: HimatchRadius.control).fill(isSelected ? HimatchColor.tint(HimatchColor.accent) : HimatchColor.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
