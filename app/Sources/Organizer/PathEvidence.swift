import Foundation

/// 從檔名與資料夾結構讀到的證據。
///
/// 這一層完全不碰音訊。它只回報「路徑裡字面寫了什麼」，
/// 因此永遠可以被使用者驗證——打開 Finder 就能看到同樣的字。
struct PathEvidence: Equatable {
    var category: String?
    var confidence: Double
    var tags: [String]
    /// 實際命中的詞。審核介面要能說明「因為資料夾叫 Cinematic Hits」。
    var matchedTerms: [String]
    /// 路徑裡讀到的音樂風格。讀不到就是 nil——nil 是合法狀態。
    var style: StyleReader.Match?

    static let none = PathEvidence(category: nil, confidence: 0, tags: [], matchedTerms: [], style: nil)
}

/// 關鍵詞 → 分類路徑的對照表，以及從路徑抽取證據的邏輯。
enum PathEvidenceReader {

    /// 一條對照規則。`terms` 只要命中一個就算。
    struct Rule: Equatable {
        var terms: [String]
        var category: String
    }

    /// 全部的規則。英文在前，中文在後。
    static let rules: [Rule] = englishRules + chineseRules

    /// 中文音效庫的用詞。
    ///
    /// 排在英文規則之後，但同分時**中文的具體詞要贏過英文的概括詞**，
    /// 所以這一組內部也是具體在前：「风扇」必須宣告在「风」之前，
    /// 否則電風扇會被歸成自然風聲。
    ///
    /// 只收**描述聲音本身**的詞。「音效素材」「精选」「最实用」「更多选择」
    /// 這類是包裝用語，不是內容——把它們寫進規則表會讓幾千個檔案一起歸錯類。
    static let chineseRules: [Rule] = [
        // --- 自然（具體在前）---
        Rule(terms: ["风扇", "風扇", "电扇", "電扇"], category: "Machines/Fan"),
        Rule(terms: ["自然风光", "自然風光", "风光", "風光"], category: "Nature"),
        Rule(terms: ["雷达", "雷達"], category: "Machines/Electronics"),
        Rule(terms: ["雷电", "雷電", "打雷", "雷声", "雷聲"], category: "Nature/Thunder"),
        Rule(terms: ["雨声", "雨聲", "下雨", "大雨", "小雨"], category: "Nature/Rain"),
        Rule(terms: ["海浪", "海水", "波浪", "潮"], category: "Nature/Ocean"),
        Rule(terms: ["水声", "水聲", "流水", "水滴", "滴水", "溪", "水"], category: "Nature/Water"),
        Rule(terms: ["风声", "風聲", "大风", "狂风", "风", "風"], category: "Nature/Wind"),
        Rule(terms: ["火焰", "燃烧", "燃燒", "火"], category: "Nature/Fire"),
        Rule(terms: ["树叶", "樹葉", "落叶"], category: "Nature/Leaves"),
        Rule(terms: ["森林", "树林", "樹林"], category: "Nature/Forest"),
        Rule(terms: ["自然"], category: "Nature"),

        // --- 動物 ---
        Rule(terms: ["鸟类", "鳥類", "鸟叫", "鸟"], category: "Animals/Bird"),
        Rule(terms: ["狗叫", "犬", "狗"], category: "Animals/Dog"),
        Rule(terms: ["猫叫", "貓", "猫"], category: "Animals/Cat"),
        Rule(terms: ["马蹄", "馬蹄", "马叫", "马"], category: "Animals/Horse"),
        Rule(terms: ["昆虫", "昆蟲", "蟋蟀", "蝉"], category: "Animals/Insect"),
        Rule(terms: ["家畜", "家禽", "牛", "羊", "鸡", "猪"], category: "Animals/Farm Animal"),
        Rule(terms: ["兽类", "獸類", "野兽", "野獸"], category: "Animals/Wild Animal"),
        Rule(terms: ["动物", "動物"], category: "Animals"),

        // --- 人聲 ---
        Rule(terms: ["鼓掌", "掌声", "掌聲", "欢呼", "歡呼"], category: "Human/Cheer"),
        Rule(terms: ["笑声", "笑聲", "大笑"], category: "Human/Laugh"),
        Rule(terms: ["哭声", "哭聲", "哭泣"], category: "Human/Cry"),
        Rule(terms: ["尖叫", "喊叫", "呐喊", "吶喊"], category: "Human/Shout"),
        Rule(terms: ["呼吸", "喘息"], category: "Human/Breath"),
        Rule(terms: ["咳嗽"], category: "Human/Cough"),
        Rule(terms: ["喷嚏", "噴嚏"], category: "Human/Sneeze"),
        Rule(terms: ["人群", "群众", "群眾", "嘈杂人声"], category: "Human/Crowd Voice"),

        // --- 交通 ---
        Rule(terms: ["飞机", "飛機", "直升机", "直升機", "飞行", "飛行"], category: "Vehicles/Aircraft"),
        Rule(terms: ["火车", "火車", "地铁", "地鐵", "列车"], category: "Vehicles/Train"),
        Rule(terms: ["摩托", "机车", "機車"], category: "Vehicles/Motorcycle"),
        Rule(terms: ["卡车", "卡車", "货车"], category: "Vehicles/Truck"),
        Rule(terms: ["轮船", "輪船", "船"], category: "Vehicles/Boat"),
        Rule(terms: ["汽车", "汽車", "轿车", "刹车", "煞車", "车"], category: "Vehicles/Car"),
        Rule(terms: ["交通工具", "交通"], category: "Vehicles"),

        // --- 機械與電子 ---
        Rule(terms: ["电话", "電話", "手机", "手機"], category: "Machines/Electronics"),
        Rule(terms: ["办公设备", "辦公設備", "打印机", "印表機", "键盘", "鍵盤"],
             category: "Machines/Appliance"),
        Rule(terms: ["引擎", "马达", "馬達", "发动机"], category: "Machines/Motor"),
        // 按钮／铃音是葉資料夾，比「电子机器设备」這種上層分類具體，同分時要贏。
        Rule(terms: ["按钮", "按鈕", "开关", "開關"], category: "UI/Click"),
        Rule(terms: ["铃音", "鈴音", "铃声", "鈴聲", "提示音"], category: "UI/Notification"),
        Rule(terms: ["电子机器设备", "电子设备", "電子設備", "电子音效", "电子"],
             category: "Machines/Electronics"),
        Rule(terms: ["工业", "工業", "工厂", "工廠"], category: "Machines/Industrial Machine"),
        Rule(terms: ["机器", "機器", "机械", "機械", "设备", "設備"], category: "Machines/Mechanical"),
        Rule(terms: ["系统音效", "系統音效"], category: "UI"),

        // --- 撞擊與破壞 ---
        Rule(terms: ["玻璃"], category: "Impacts/Glass"),
        Rule(terms: ["金属", "金屬"], category: "Impacts/Metal"),
        Rule(terms: ["木头", "木頭", "木质", "木製"], category: "Impacts/Wood"),
        Rule(terms: ["爆炸", "爆破", "炸弹", "炸彈"], category: "Impacts/Generic"),
        Rule(terms: ["枪声", "槍聲", "射击", "射擊", "枪", "槍", "炮"], category: "Impacts/Generic"),
        Rule(terms: ["碰撞", "撞击", "撞擊", "敲击", "敲擊", "破碎", "打斗", "打鬥", "打架"],
             category: "Impacts"),

        // --- Foley ---
        Rule(terms: ["脚步", "腳步", "走路", "跑步"], category: "Foley/Footsteps"),
        Rule(terms: ["开门", "開門", "关门", "關門", "门", "門"], category: "Foley/Doors"),
        Rule(terms: ["衣服摩擦", "衣物", "布料", "衣服"], category: "Foley/Cloth"),
        Rule(terms: ["家具", "抽屉", "抽屜", "椅子"], category: "Foley/Furniture"),
        Rule(terms: ["纸张", "紙張", "翻书", "翻書"], category: "Foley/Props"),

        // --- 設計音 ---
        Rule(terms: ["转场音效", "轉場音效", "转场", "轉場", "字幕音效"],
             category: "Designed/Transition"),
        Rule(terms: ["光效音", "光速", "光音效", "光效"], category: "Designed/Whoosh"),
        Rule(terms: ["片头", "片頭", "序曲"], category: "Designed/Stinger"),
        Rule(terms: ["特效音", "特殊效果", "音效设计", "音效設計"], category: "Designed"),

        // --- 音樂 ---
        Rule(terms: ["木吉他", "吉他"], category: "Instruments/Guitar"),
        Rule(terms: ["钢琴", "鋼琴"], category: "Instruments/Keys"),
        Rule(terms: ["鼓声", "鼓聲", "鼓点", "鼓點"], category: "Drums"),
        Rule(terms: ["节奏", "節奏"], category: "Drums/Drum Loop"),
        Rule(terms: ["乐器", "樂器"], category: "Instruments"),
        Rule(terms: ["音乐", "音樂", "软音乐", "配乐", "配樂"], category: "Musical"),

        // --- 環境 ---
        Rule(terms: ["环境音", "環境音", "氛围", "氛圍", "底噪"], category: "Ambience"),
        Rule(terms: ["室内", "室內"], category: "Ambience/Interior"),
        Rule(terms: ["室外", "户外", "戶外"], category: "Ambience/Exterior"),
    ]

    /// 順序有意義：先比對詞數多的規則，"whoosh to hit" 才不會被 "whoosh" 搶走。
    /// 這張表是可檢討的資料，不是散落在判斷式裡的魔術字串。
    static let englishRules: [Rule] = [
        // --- 設計音（詞數多的在前）---
        Rule(terms: ["whoosh to hit", "swoosh to hit", "whoosh hit"], category: "Designed/Impact Hit"),
        Rule(terms: ["cinematic hit", "complex hit", "trailer hit", "braam", "boom hit", "hit reverb"],
             category: "Designed/Impact Hit"),
        Rule(terms: ["room tone"], category: "Ambience/Room Tone"),
        Rule(terms: ["metal impact", "metal hit"], category: "Impacts/Metal"),
        Rule(terms: ["wood impact", "wood hit"], category: "Impacts/Wood"),
        Rule(terms: ["glass impact", "glass break", "glass smash"], category: "Impacts/Glass"),

        // --- 音樂製作素材：鼓（多詞在前）---
        Rule(terms: ["drum loop", "drum loops", "top loop", "full loop", "perc loop",
                     "hat loop", "shaker loop", "drumloop"], category: "Drums/Drum Loop"),
        Rule(terms: ["vocal chop", "vocal chops", "vocal one shot", "vocal oneshot"],
             category: "Instruments/Vocal"),

        Rule(terms: ["kick", "kicks", "bassdrum", "bass drum"], category: "Drums/Kick"),
        Rule(terms: ["snare", "snares", "snr", "rimshot"], category: "Drums/Snare"),
        Rule(terms: ["clap", "claps", "handclap"], category: "Drums/Clap"),
        Rule(terms: ["hihat", "hi hat", "hihats", "hat", "hats", "openhat", "closedhat"],
             category: "Drums/Hi-Hat"),
        Rule(terms: ["cymbal", "cymbals", "crash", "ride"], category: "Drums/Cymbal"),
        Rule(terms: ["tom", "toms"], category: "Drums/Tom"),
        Rule(terms: ["808", "808s"], category: "Drums/808"),
        Rule(terms: ["percussion", "perc", "percs", "shaker", "tambourine", "tamb",
                     "conga", "bongo", "cowbell", "woodblock"], category: "Drums/Percussion"),
        Rule(terms: ["breakbeat", "breakbeats", "break", "breaks"], category: "Drums/Break"),
        Rule(terms: ["fill", "fills"], category: "Drums/Fill"),

        // --- 音樂製作素材：樂器 ---
        Rule(terms: ["bass", "basses", "sub bass", "808 bass"], category: "Instruments/Bass"),
        Rule(terms: ["keys", "piano", "rhodes", "organ", "wurlitzer", "epiano"],
             category: "Instruments/Keys"),
        Rule(terms: ["guitar", "guitars"], category: "Instruments/Guitar"),
        Rule(terms: ["brass", "trumpet", "sax", "saxophone", "horn", "horns"],
             category: "Instruments/Brass"),
        Rule(terms: ["strings", "violin", "cello", "viola"], category: "Instruments/Strings"),
        Rule(terms: ["vocal", "vocals", "vox", "shout", "adlib"], category: "Instruments/Vocal"),
        Rule(terms: ["chord", "chords"], category: "Instruments/Chord"),
        Rule(terms: ["lead", "leads"], category: "Instruments/Lead"),
        Rule(terms: ["pad", "pads"], category: "Instruments/Pad"),
        Rule(terms: ["synth", "synths", "synthesizer"], category: "Instruments/Synth"),
        // 通用桶子宣告在最後：同分時輸給比它具體的規則。
        // `Melodic_Loops/Guitar/Electric_Guitar/` 兩條都命中一個詞，
        // 該贏的是 Guitar——「吉他」比「旋律 loop」多告訴你一件事。
        // 注意不要在這裡加 "melodic"：`Melodic_Loops/Guitar/` 會同時命中
        // "melodic loop" 與 "melodic" 變成兩分，反而壓過 Guitar 的一分。
        // 規則的詞越多不代表越具體。
        Rule(terms: ["melodic loop", "melody loop", "melodic stack", "loop stem"],
             category: "Instruments/Melodic Loop"),

        Rule(terms: ["whoosh", "swoosh", "woosh"], category: "Designed/Whoosh"),
        Rule(terms: ["riser", "uplifter", "rise"], category: "Designed/Riser"),
        Rule(terms: ["downer", "downlifter", "falling"], category: "Designed/Downer"),
        Rule(terms: ["transition"], category: "Designed/Transition"),
        Rule(terms: ["stinger", "sting"], category: "Designed/Stinger"),
        Rule(terms: ["texture", "noise", "hiss", "crackle", "grain"], category: "Designed/Texture"),
        Rule(terms: ["drone"], category: "Designed/Drone"),
        Rule(terms: ["sweep"], category: "Designed/Sweep"),
        Rule(terms: ["glitch", "datamosh", "stutter"], category: "Designed/Glitch"),
        Rule(terms: ["special fx", "sound design", "designed"], category: "Designed"),

        // --- Foley ---
        Rule(terms: ["footstep", "foot step", "footsteps"], category: "Foley/Footsteps"),
        Rule(terms: ["door", "gate", "hinge", "latch"], category: "Foley/Doors"),
        Rule(terms: ["cloth", "fabric", "clothing"], category: "Foley/Cloth"),
        Rule(terms: ["drawer", "chair", "furniture"], category: "Foley/Furniture"),
        Rule(terms: ["handling", "pickup", "set down"], category: "Foley/Handling"),
        Rule(terms: ["prop", "props"], category: "Foley/Props"),
        Rule(terms: ["foley"], category: "Foley"),

        // --- 真實撞擊 ---
        Rule(terms: ["explosion", "explode", "blast", "detonation"], category: "Impacts/Generic"),
        Rule(terms: ["impact", "impacts", "crash", "slam"], category: "Impacts"),

        // --- 自然與環境 ---
        Rule(terms: ["thunder"], category: "Nature/Thunder"),
        Rule(terms: ["rain"], category: "Nature/Rain"),
        Rule(terms: ["wind"], category: "Nature/Wind"),
        Rule(terms: ["ocean", "wave", "sea"], category: "Nature/Ocean"),
        Rule(terms: ["fire", "flame", "burn"], category: "Nature/Fire"),
        Rule(terms: ["water", "splash", "drip"], category: "Nature/Water"),
        Rule(terms: ["ambience", "ambient", "atmo", "atmosphere"], category: "Ambience"),
        Rule(terms: ["liquid", "liquids"], category: "Nature/Water"),
        Rule(terms: ["industry", "industrial"], category: "Machines/Industrial Machine"),

        // --- 其他 ---
        Rule(terms: ["engine", "car", "vehicle"], category: "Vehicles/Car"),
        Rule(terms: ["notification", "alert"], category: "UI/Notification"),
        Rule(terms: ["click", "button"], category: "UI/Click"),
        // Musical/Instrument 與 Musical/Chord 的規則移到 Instruments/*：
        // 這個庫裡的 piano/guitar/chord 幾乎都是 sample pack 的製作素材，
        // 不是原音樂器演奏的錄音。Musical 分支保留在 taxonomy 裡供後者使用。
    ]

    /// 資料夾證據比檔名證據可信：資料夾是人刻意整理出來的，檔名常常是廠商亂取的。
    private enum Weight {
        static let folderOnly = 0.7
        static let filenameOnly = 0.5
        static let agreeing = 0.85
        /// 兩邊指向不同分類時，採信資料夾但降低信心。
        static let conflicting = 0.45
    }

    /// `relativePath` 應包含資料夾與檔名，例如 "Cinematic Hits/Hit Metal Reverb 03.wav"。
    static func read(relativePath: String,
                     filename: String,
                     taxonomy: Taxonomy,
                     vocabulary: TagVocabulary,
                     styles: StyleVocabulary? = nil) -> PathEvidence {
        let folderPart = folderComponent(of: relativePath, filename: filename)
        let folderText = normalise(folderPart)
        let filenameText = normalise((filename as NSString).deletingPathExtension)

        // 一個資料夾層級算一份證據。同一個名字裡出現同一條規則的兩個同義詞
        // （「电子机器设备」同時含有「机器」與「设备」）不該變成兩分。
        let folderLevels = folderPart.split(separator: "/").map { normalise(String($0)) }
        let folderMatch = bestMatch(in: folderLevels, taxonomy: taxonomy)
        let filenameMatch = bestMatch(in: [filenameText], taxonomy: taxonomy)

        let tags = literalTags(in: folderText + " " + filenameText, vocabulary: vocabulary)
        // 風格要在分類之後算：模糊字（metal、house⋯⋯）需要分類當脈絡才能判斷
        // 它是曲風還是材質。資料夾的分類優先，沒有才用檔名的。
        let resolvedCategory = folderMatch?.category ?? filenameMatch?.category
        let style = styles.flatMap {
            StyleReader.read(relativePath: relativePath,
                             filename: filename,
                             vocabulary: $0,
                             category: resolvedCategory)
        }

        switch (folderMatch, filenameMatch) {
        case let (.some(folder), .some(file)) where folder.category == file.category:
            return PathEvidence(category: folder.category,
                                confidence: Weight.agreeing,
                                tags: tags,
                                matchedTerms: Array(Set(folder.terms + file.terms)).sorted(),
                                style: style)
        case let (.some(folder), .some(file)):
            // 資料夾與檔名說法不同。這是真的不確定，信心要降下來，
            // 而且兩邊的線索都要留給審核者看。
            return PathEvidence(category: folder.category,
                                confidence: Weight.conflicting,
                                tags: tags,
                                matchedTerms: Array(Set(folder.terms + file.terms)).sorted(),
                                style: style)
        case let (.some(folder), .none):
            return PathEvidence(category: folder.category,
                                confidence: Weight.folderOnly,
                                tags: tags,
                                matchedTerms: folder.terms,
                                style: style)
        case let (.none, .some(file)):
            return PathEvidence(category: file.category,
                                confidence: Weight.filenameOnly,
                                tags: tags,
                                matchedTerms: file.terms,
                                style: style)
        case (.none, .none):
            return PathEvidence(category: nil, confidence: 0, tags: tags,
                                matchedTerms: [], style: style)
        }
    }

    // MARK: - 內部

    private struct Match: Equatable {
        var category: String
        var terms: [String]
    }

    private static func folderComponent(of relativePath: String, filename: String) -> String {
        let path = relativePath as NSString
        let folder = path.deletingLastPathComponent
        return folder.isEmpty ? "" : folder
    }

    /// 統一成小寫、以單一空白分隔的字串，底線與連字號都當成分隔。
    /// 這樣 "Hit_Metal-Reverb" 與 "hit metal reverb" 會命中同一批規則。
    static func normalise(_ text: String) -> String {
        let lowered = text.lowercased()
        let separators = CharacterSet.alphanumerics.inverted
        let parts = lowered.components(separatedBy: separators).filter { !$0.isEmpty }
        return " " + parts.joined(separator: " ") + " "
    }

    /// 命中最多**層級**的規則勝出，同分才看宣告順序。
    ///
    /// 不用「第一個命中的就算」，是因為真實路徑會同時命中好幾條規則。例：
    /// `Noise/musicradar-noise-hiss-crackle-samples/Noise_Perc_Hits/`
    /// 三層都提到 noise 系的詞，只有最後一層提到 perc。用宣告順序決定的話，
    /// 加入鼓的規則會把 FX 庫裡五百多個 Texture 一次弄壞。
    ///
    /// 計分的單位是**資料夾層級**而不是命中的詞數。這一點是踩過兩次坑才學到的：
    ///
    /// 1. 在 Melodic Loop 的規則裡多加一個 "melodic"，它就以兩分壓過 Guitar 的一分
    /// 2.「电子机器设备」一個資料夾名同時命中同一條規則的「机器」與「设备」，
    ///    也變成兩分，壓過命中葉資料夾「按钮」的 UI/Click
    ///
    /// 兩次都是同一件事被數了兩次。**規則的詞越多不代表越具體**，
    /// 但「越多層資料夾都在講同一件事」確實是更強的證據。
    private static func bestMatch(in levels: [String], taxonomy: Taxonomy) -> Match? {
        let levels = levels.filter { $0.trimmingCharacters(in: .whitespaces).isEmpty == false }
        guard levels.isEmpty == false else { return nil }

        var best: Match?
        var bestScore = 0
        for rule in rules {
            // 分類表可能被改動；送出無效路徑等於製造髒資料，寧可跳過。
            guard taxonomy.isValidPath(rule.category) else { continue }
            var score = 0
            var terms: [String] = []
            for level in levels {
                let hits = rule.terms.filter { matches($0, in: level) }
                guard hits.isEmpty == false else { continue }
                // 計分一層算一分，但**顯示要留下全部命中的詞**——
                // 審核介面要能說明憑什麼這樣判斷，只留一個詞就看不出理由了。
                score += 1
                terms.append(contentsOf: hits)
            }
            // 嚴格大於：同分時保留先宣告的那一條，具體的規則本來就排在前面。
            if score > bestScore {
                bestScore = score
                best = Match(category: rule.category, terms: Array(Set(terms)).sorted())
            }
        }
        return best
    }

    /// 詞尾的複數 s 要一起吃：資料夾名幾乎都是複數（Drones、Impacts、Cinematic Hits），
    /// 而規則表用單數寫比較好讀。只加 "s"，不做任何其他詞形變化——
    /// 真正的英文單複數規則（glass/glasses）遠比這複雜，硬做只會製造錯誤命中。
    ///
    /// **中文走另一條路：子字串比對。** 中文沒有空格，`normalise` 之後
    /// 「军事爆破」會是一整個 token，用詞界比對永遠對不上。
    /// 子字串在中文裡是安全的做法，但短詞風險高（「风」會命中「风扇」），
    /// 所以規則表裡具體的詞要宣告在概括的詞前面，靠既有的同分順序解決。
    private static func matches(_ term: String, in normalisedText: String) -> Bool {
        if containsCJK(term) {
            return normalisedText.contains(term)
        }
        return normalisedText.contains(" \(term) ") || normalisedText.contains(" \(term)s ")
    }

    static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)      // CJK 統一表意文字
                || (0x3400...0x4DBF).contains(scalar.value) // 擴充 A
        }
    }

    /// 只收「字面出現在路徑裡」的受控標籤。不做同義詞擴張，不做推論。
    private static func literalTags(in normalisedText: String, vocabulary: TagVocabulary) -> [String] {
        vocabulary.canonical.filter { tag in
            // 詞彙表裡有 "set-down" 這類含連字號的詞，正規化後會變成 "set down"。
            let normalisedTag = tag.replacingOccurrences(of: "-", with: " ")
            return normalisedText.contains(" \(normalisedTag) ")
        }
    }
}
