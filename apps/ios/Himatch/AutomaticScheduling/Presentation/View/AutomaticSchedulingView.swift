import ComposableArchitecture
import SwiftUI
import UIKit

struct SchedulingStatusView: View {
    let store: StoreOf<AutomaticSchedulingFeature>
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.isLoading { ProgressView("提案を読み込み中…") }
            if let error = store.error {
                Text(error).font(.footnote)
                if store.pendingCommand != nil {
                    Button("同じ操作で再試行") { store.send(.retry) }.disabled(store.isSending)
                } else {
                    Button("再読み込み") { store.send(.refresh) }.disabled(store.isLoading)
                }
            }
            if let message = store.message { Text(message).font(.footnote) }
            if let receipt = store.reportReceipt {
                Text("受付番号: \(receipt.uuidString)").font(.footnote).textSelection(.enabled)
            }
            if store.isSending { ProgressView("更新中…") }
        }
    }
}

struct SchedulingSettingsView: View {
    let store: StoreOf<AutomaticSchedulingFeature>
    @Environment(\.openURL) private var openURL
    var body: some View {
        Section {
            Toggle("友達との自動提案", isOn: Binding(
                get: { store.snapshot?.enabled ?? false },
                set: { store.send(.send(.settings($0))) }
            ))
            .disabled(!store.canMutate)
            SchedulingStatusView(store: store)
        } header: { Text("自動提案") } footer: {
            Text("双方が自動提案と友達別の許可を有効にした場合だけ提案します。暇登録は参加の承諾ではありません。提案日時から共通の暇があると推測される可能性があります。相手名は双方OK、または相手がOK共有を選んだ場合だけ表示します。")
        }
        Section {
            Button("通知を有効にする") { store.send(.requestNotifications) }
                .disabled(store.isRegisteringNotifications || store.ownerID == nil)
            Button("この端末の通知を停止する") { store.send(.disableNotifications) }
                .disabled(store.isRegisteringNotifications || store.ownerID == nil)
            Button("OSの通知設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            if store.isRegisteringNotifications { ProgressView() }
            if let message = store.notificationMessage { Text(message).font(.footnote) }
        } header: { Text("通知") } footer: {
            Text("通知を許可しなくても受信箱から利用できます。通知本文に相手名や暇時間は表示しません。")
        }
    }
}

struct SchedulingPermissionView: View {
    let store: StoreOf<AutomaticSchedulingFeature>
    let friendID: UUID
    var body: some View {
        Toggle("この友達との自動提案を許可", isOn: Binding(
            get: { store.snapshot?.permits(friendID) ?? false },
            set: { store.send(.send(.permission(friendID, $0))) }
        ))
        .disabled(!store.canMutate)
        Text("相手の許可状態や暇は表示しません。双方の許可がある場合だけ対象になります。")
            .font(.footnote).foregroundStyle(.secondary)
    }
}

struct SchedulingProposalCard: View {
    let store: StoreOf<AutomaticSchedulingFeature>
    let proposal: SchedulingProposal
    @State private var cancelPresented = false
    @State private var blockPresented = false
    @State private var reportPresented = false
    @State private var feedbackPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: proposal.status == .confirmed ? "calendar.badge.checkmark" : "sparkles")
                .font(.headline)
            Text(AvailabilityFormatting.range(proposal.interval, calendar: .current))
            if let peer = proposal.peer {
                Label(peer.nickname, systemImage: peer.presetIconKey)
                if proposal.status == .pending { Text("相手が参加OKを共有しました。").font(.footnote) }
            } else if proposal.status == .pending {
                Text("許可した友達とオンラインで遊びませんか？相手名は双方OK、または相手がOK共有を選んだ場合に表示します。")
                    .font(.subheadline)
            }
            if proposal.status == .pending {
                Text("回答期限: \(proposal.start.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                if proposal.myResponse == .pending {
                    Toggle("自分の参加OKと名前を相手に先に共有", isOn: Binding(
                        get: { store.shareAcceptance[proposal.id] ?? false },
                        set: { store.send(.setShareAcceptance(proposal.id, $0)) }
                    )).font(.footnote).disabled(!store.canMutate)
                    HStack {
                        Button("参加OK") {
                            store.send(.send(.response(proposal.id, .accepted, shareAcceptance: store.shareAcceptance[proposal.id] ?? false, version: proposal.version)))
                        }.buttonStyle(.borderedProminent)
                        Button("今回は見送る") {
                            store.send(.send(.response(proposal.id, .declined, shareAcceptance: false, version: proposal.version)))
                        }.buttonStyle(.bordered)
                    }.disabled(!store.canMutate || proposal.start <= Date())
                } else if proposal.myResponse == .accepted {
                    Text("参加OKを受け付けました。双方OKで確定します。")
                    if let withdrawal = proposal.withdrawalCommand {
                        Button("参加OKを取り消す") { store.send(.send(withdrawal)) }
                            .disabled(!store.canMutate)
                    }
                }
            } else if proposal.status == .confirmed {
                Text("オンラインの通話やゲームの予定です。接続先は普段の連絡手段をご利用ください。")
                    .font(.footnote)
                if proposal.end <= Date() {
                    Button(proposal.feedback == nil ? "遊べたかを任意で回答" : "実施後の回答を確認・変更") { feedbackPresented = true }
                } else {
                    Button("予定を取り消す", role: .destructive) { cancelPresented = true }.disabled(!store.canMutate)
                }
            }
            if proposal.status != .pending && proposal.status != .confirmed {
                Button("提案について任意で回答") { feedbackPresented = true }
            }
            HStack {
                Button("通報") { reportPresented = true }
                Button("この提案の相手をブロック", role: .destructive) { blockPresented = true }
            }.font(.footnote).disabled(!store.canMutate)
        }
        .padding(.vertical, 8)
        .controlSize(.large)
        .confirmationDialog("この予定を取り消しますか？", isPresented: $cancelPresented, titleVisibility: .visible) {
            Button("予定を取り消す", role: .destructive) { store.send(.send(.cancel(proposal.id, version: proposal.version))) }
        }
        .confirmationDialog("相手をブロックしますか？", isPresented: $blockPresented, titleVisibility: .visible) {
            Button("ブロック", role: .destructive) { store.send(.send(.blockProposal(proposal.id))) }
        } message: { Text("新しい申請やお誘いを止め、未確定提案と今後の予定を取り消します。相手の名前は開示しません。") }
        .confirmationDialog("通報理由を選んでください", isPresented: $reportPresented, titleVisibility: .visible) {
            Button("迷惑な提案") { store.send(.send(.report(proposal.id, .spam))) }
            Button("嫌がらせ") { store.send(.send(.report(proposal.id, .harassment))) }
            Button("その他") { store.send(.send(.report(proposal.id, .other))) }
        }
        .sheet(isPresented: $feedbackPresented) { SchedulingFeedbackView(store: store, proposal: proposal) }
    }

    private var title: String {
        switch proposal.status {
        case .pending: "遊びの候補があります"
        case .confirmed: "確定した予定"
        case .declined: "終了した提案"
        case .expired: "期限を過ぎた提案"
        case .cancelled: "取り消された予定・提案"
        }
    }
}

private struct SchedulingFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    let store: StoreOf<AutomaticSchedulingFeature>
    let proposal: SchedulingProposal
    @State private var played: Bool?
    @State private var bothersome = false
    @State private var privacyConcern = false
    var body: some View {
        NavigationStack {
            Form {
                if proposal.status == .confirmed {
                Section("実際に遊べましたか？（任意）") {
                    Button { played = true } label: { Label("遊べた", systemImage: played == true ? "checkmark.circle.fill" : "circle") }
                    Button { played = false } label: { Label("遊べなかった", systemImage: played == false ? "checkmark.circle.fill" : "circle") }
                }
                }
                Toggle("提案を煩わしく感じた", isOn: $bothersome)
                Toggle("意図せず暇を知られたと感じた", isOn: $privacyConcern)
                Button("回答を保存") {
                    guard let played else { return }
                    store.send(.send(.feedback(proposal.id, .init(played: played, bothersome: bothersome, privacyConcern: privacyConcern))))
                }.disabled(played == nil || !store.canMutate)
                SchedulingStatusView(store: store)
            }
            .navigationTitle("実施後の任意回答")
            .toolbar { Button("閉じる") { dismiss() } }
            .onAppear {
                played = proposal.feedback?.played ?? (proposal.status == .confirmed ? nil : false)
                bothersome = proposal.feedback?.bothersome ?? false
                privacyConcern = proposal.feedback?.privacyConcern ?? false
            }
            .onChange(of: store.snapshot?.proposals.first { $0.id == proposal.id }?.feedback) { _, value in
                if value != nil { dismiss() }
            }
        }
    }
}
