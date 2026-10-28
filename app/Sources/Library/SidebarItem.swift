import Foundation

enum SidebarDisclosure: Equatable {
    case none
    case closed
    case open
}

/// 側欄的一列。
///
/// 樹在 store 裡就被攤平成一維陣列，view 只負責畫。
/// SwiftUI 不允許遞迴的 @ViewBuilder 函式，而且攤平之後
/// 之後要換成虛擬捲動也不用再動資料結構。
struct SidebarItem: Identifiable, Equatable {
    let id: String
    let title: String
    let count: Int
    let depth: Int
    let filter: SoundFilter
    let disclosure: SidebarDisclosure
    let toggleKey: String?
    let isOffline: Bool
    let libraryId: Int64?

    static func == (lhs: SidebarItem, rhs: SidebarItem) -> Bool {
        lhs.id == rhs.id
            && lhs.count == rhs.count
            && lhs.disclosure == rhs.disclosure
            && lhs.isOffline == rhs.isOffline
    }
}
