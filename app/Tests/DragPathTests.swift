import XCTest
@testable import FoleyLibrary

/// 拖進 DAW 的路徑永遠是原檔（D-019）。
///
/// 這組測試存在的唯一理由，是擋住未來某個「讓 Logic 顯示漂亮名字」的好意改動。
/// 整理後的樹裡的名字會隨規則調整而變，舊名字的連結會被刪掉；
/// 引用它的 Logic 專案會斷鏈，而 Logic 不會自己找回來。
final class DragPathTests: XCTestCase {

    private func sound(displayName: String? = nil) -> Sound {
        var sound = Sound(libraryId: 1,
                          filePath: "/Volumes/Example SSD/FX/Impacts/metal_hit.wav",
                          relativePath: "Cinematic Hits/Hit Metal Reverb 03.wav",
                          filename: "Hit Metal Reverb 03.wav",
                          fileExtension: "wav",
                          duration: 2)
        sound.displayName = displayName
        sound.displayNameSource = displayName == nil ? nil : .manual
        return sound
    }

    func testDragUsesTheOriginalFilePath() {
        XCTAssertEqual(FileActions.dragPath(for: sound()),
                       "/Volumes/Example SSD/FX/Impacts/metal_hit.wav")
    }

    func testRenamingInsideTheAppDoesNotChangeWhatTheDAWReceives() {
        // app 裡的顯示名稱是純 metadata，磁碟上一個位元組都沒動。
        let renamed = sound(displayName: "Cinematic Metal Hit — big")
        XCTAssertEqual(FileActions.dragPath(for: renamed), FileActions.dragPath(for: sound()))
    }

    func testDragPathIsNeverInsideTheOrganisedTree() {
        // _Organized 底下是硬連結，名字會變。DAW 不該拿到那裡的路徑。
        XCTAssertFalse(FileActions.dragPath(for: sound()).contains("_Organized"))
    }
}
