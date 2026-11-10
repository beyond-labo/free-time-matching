import SwiftUI

/// What was sent and what happens next. No delivery count or unanswered friends are shown (6.1, 6.2).
struct InvitationSentView: View {
    let invitation: Hosting
    let now: Date
    let onDone: () -> Void

    @Environment(\.calendar) private var calendar

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: HimatchSpacing.l) {
                    VStack(spacing: HimatchSpacing.s) {
                        IconAvatar(systemImage: "paperplane.fill", size: 72, tint: HimatchColor.plan)
                        Text("お誘いを送りました")
                            .font(HimatchFont.hero)
                        Text("参加OKの返事が届くと、ホームに名前と時間が表示されます。")
                            .font(HimatchFont.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, HimatchSpacing.l)

                    VStack(alignment: .leading, spacing: HimatchSpacing.xs) {
                        LabeledContent("いつ", value: AvailabilityFormatting.friendlyRange(invitation.candidateRange, calendar: calendar, now: now))
                        LabeledContent("会い方", value: invitation.meetingDescription)
                        if let category = invitation.category {
                            LabeledContent("なにする", value: category.rawValue)
                        }
                    }
                    .himatchCard()

                    InfoRow(
                        icon: "bubble.left.and.bubble.right",
                        title: "場所や集合はいつもの連絡手段で",
                        detail: "返事がない人や見送った人は表示されません。"
                    )
                    .himatchCard()
                }
                .padding(HimatchSpacing.m)
            }
            .background(HimatchColor.background)
            .safeAreaInset(edge: .bottom) {
                Button("ホームへ", action: onDone)
                    .buttonStyle(.himatchPrimary)
                    .padding(HimatchSpacing.m)
                    .background(.bar)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

extension Hosting {
    /// "オンライン" / "会う（渋谷）"
    var meetingDescription: String {
        switch mode {
        case .online: mode.displayName
        case .offline: "\(mode.displayName)（\(area?.rawValue ?? HostingArea.discussLater.rawValue)）"
        }
    }

    /// "ご飯・会う（渋谷）"
    var summary: String {
        [category?.rawValue, meetingDescription].compactMap { $0 }.joined(separator: "・")
    }
}
