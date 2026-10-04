import AppIntents

struct HimatchAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddAvailabilityIntent(), phrases: ["\(.applicationName)で暇を登録"],
                    shortTitle: "暇を登録", systemImageName: "calendar.badge.plus")
        AppShortcut(intent: SubtractAvailabilityIntent(), phrases: ["\(.applicationName)で暇を削除"],
                    shortTitle: "暇を削除", systemImageName: "calendar.badge.minus")
        AppShortcut(intent: CreateHostingIntent(), phrases: ["\(.applicationName)で友達を誘う"],
                    shortTitle: "友達を誘う", systemImageName: "person.2")
        AppShortcut(intent: CancelHostingIntent(), phrases: ["\(.applicationName)で募集を取り消す"],
                    shortTitle: "募集を取り消す", systemImageName: "xmark.circle")
    }
}
