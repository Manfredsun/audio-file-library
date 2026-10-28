import Foundation

/// 把資料庫的列變成命名計畫。
///
/// 中間這一步的工作只有一件：descriptor 是**逐資料夾**算的
/// （同一個資料夾的檔名才共用慣例），但計畫是整份的。
enum NamingPlanBuilder {

    static func build(rows: [NamingRow],
                      roleTerms: Set<String>,
                      styleTerms: Set<String>,
                      existingDestinations: Set<String> = []) -> NamingPlan {
        // 依直屬資料夾分組——廠商的命名慣例就活在那一層。
        var groups: [String: [NamingRow]] = [:]
        for row in rows {
            groups[(row.relativePath as NSString).deletingLastPathComponent, default: []].append(row)
        }

        var descriptors: [Int64: String] = [:]
        for (_, members) in groups {
            let (_, extracted) = NamingConventionDetector.detect(
                filenames: members.map(\.filename),
                roleTerms: roleTerms,
                styleTerms: styleTerms)
            for member in members {
                if let value = extracted[member.filename] { descriptors[member.id] = value }
            }
        }

        let inputs = rows.map { row in
            NamingInput(soundId: row.id,
                        relativePath: row.relativePath,
                        filename: row.filename,
                        fileExtension: row.fileExtension,
                        category: row.category,
                        style: row.style,
                        bpm: row.bpm,
                        musicalKey: row.musicalKey,
                        isLoop: row.isLoop,
                        descriptor: descriptors[row.id],
                        // 凍結的號碼只在**同一個資料夾**裡有效。
                        // 分類改過了就要在新資料夾重新拿一個號，不能沿用。
                        frozenNumber: row.organizedFolder == (row.category ?? NamingPlanner.unclassifiedFolder)
                            ? row.organizedNumber : nil)
        }
        return NamingPlanner.plan(inputs, existingDestinations: existingDestinations)
    }
}
