import Foundation

enum ArticleReadingLanguage: String, CaseIterable {
    case english
    case englishAndChinese
    case followAlong

    static let storageKey = "articleReadingLanguage"

    static var saved: ArticleReadingLanguage {
        ArticleReadingLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .english
    }

    var title: String {
        switch self {
        case .english: return "只读英文"
        case .englishAndChinese: return "英文 + 中文"
        case .followAlong: return "跟读模式"
        }
    }
}
