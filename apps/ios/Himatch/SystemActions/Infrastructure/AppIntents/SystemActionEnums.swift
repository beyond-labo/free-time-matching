import AppIntents

enum SystemHostingMode: String, AppEnum {
    case online, offline
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "開催形態"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .online: "オンライン", .offline: "オフライン",
    ]
    var domainValue: HostingMode { self == .online ? .online : .offline }
}

enum SystemHostingArea: String, AppEnum {
    case shinjuku, shibuya, discussLater
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "エリア"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .shinjuku: "新宿", .shibuya: "渋谷", .discussLater: "あとで相談",
    ]
    var domainValue: HostingArea {
        switch self {
        case .shinjuku: .shinjuku
        case .shibuya: .shibuya
        case .discussLater: .discussLater
        }
    }
}

enum SystemActivityCategory: String, AppEnum {
    case game, meal, call, work
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "カテゴリ"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .game: "ゲーム", .meal: "ご飯", .call: "通話", .work: "作業",
    ]
    var domainValue: ActivityCategory {
        switch self {
        case .game: .game
        case .meal: .meal
        case .call: .call
        case .work: .work
        }
    }
}
