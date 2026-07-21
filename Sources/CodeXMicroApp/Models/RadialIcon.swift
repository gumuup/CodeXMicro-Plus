import Foundation

enum RadialIconReference: Hashable, Sendable {
    case system(String)
    case emoji(String)
    case local(String)

    private static let emojiPrefix = "emoji:"
    private static let localPrefix = "local:"

    init(rawValue: String) {
        if rawValue.hasPrefix(Self.emojiPrefix) {
            self = .emoji(String(rawValue.dropFirst(Self.emojiPrefix.count)))
        } else if rawValue.hasPrefix(Self.localPrefix) {
            self = .local(String(rawValue.dropFirst(Self.localPrefix.count)))
        } else {
            self = .system(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case let .system(symbol): symbol
        case let .emoji(value): Self.emojiPrefix + value
        case let .local(filename): Self.localPrefix + filename
        }
    }
}

struct RadialEmojiCategory: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let emojis: [String]
}

private struct RadialIconSearchGroup: Sendable {
    let terms: String
    let values: [String]

    init(_ terms: String, _ values: String) {
        self.terms = terms
        self.values = values.split(separator: " ").map(String.init)
    }

    init(_ terms: String, values: [String]) {
        self.terms = terms
        self.values = values
    }
}

enum RadialFuzzySearch {
    static func score(query: String, fields: [String]) -> Int? {
        let queryTokens = tokens(in: query)
        guard !queryTokens.isEmpty else { return nil }
        let fieldTokens = fields.flatMap { field -> [String] in
            let normalized = normalize(field)
            return [normalized] + tokens(in: field)
        }

        var total = 0
        for queryToken in queryTokens {
            let best = fieldTokens.map { score(token: queryToken, candidate: $0) }.max() ?? 0
            guard best > 0 else { return nil }
            total += best
        }
        return total
    }

    private static func score(token: String, candidate: String) -> Int {
        guard !token.isEmpty, !candidate.isEmpty else { return 0 }
        if candidate == token { return 120 }
        if candidate.hasPrefix(token) { return 100 - min(candidate.count - token.count, 18) }
        if candidate.contains(token) { return 82 - min(candidate.count - token.count, 22) }
        if token.count >= 2, token.contains(candidate) { return 58 - min(token.count - candidate.count, 18) }

        guard token.unicodeScalars.allSatisfy(\.properties.isAlphabetic),
              candidate.unicodeScalars.allSatisfy(\.properties.isAlphabetic) else { return 0 }
        if isSubsequence(token, of: candidate) {
            return max(28, 54 - (candidate.count - token.count) * 2)
        }
        let maximumDistance = token.count <= 4 ? 1 : max(1, token.count / 3)
        let distance = editDistance(token, candidate, cutoff: maximumDistance)
        return distance <= maximumDistance ? max(22, 48 - distance * 10) : 0
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokens(in value: String) -> [String] {
        normalize(value)
            .split { character in
                character.isWhitespace || ".,_-/\\|:;()[]{}".contains(character)
            }
            .map(String.init)
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var iterator = haystack.makeIterator()
        for character in needle {
            var found = false
            while let candidate = iterator.next() {
                if candidate == character {
                    found = true
                    break
                }
            }
            if !found { return false }
        }
        return true
    }

    private static func editDistance(_ lhs: String, _ rhs: String, cutoff: Int) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        if abs(left.count - right.count) > cutoff { return cutoff + 1 }
        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1] + Array(repeating: 0, count: right.count)
            var rowMinimum = current[0]
            for (rightIndex, rightCharacter) in right.enumerated() {
                current[rightIndex + 1] = min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                )
                rowMinimum = min(rowMinimum, current[rightIndex + 1])
            }
            if rowMinimum > cutoff { return cutoff + 1 }
            previous = current
        }
        return previous[right.count]
    }
}

enum RadialEmojiCatalog {
    static let categories: [RadialEmojiCategory] = [
        category("people", "表情与人物", "😀 😃 😄 😁 😆 😅 😂 🤣 😊 😇 🙂 🙃 😉 😌 😍 🥰 😘 😗 😙 😚 😋 😛 😝 😜 🤪 🤨 🧐 🤓 😎 🥸 🤩 🥳 😏 😒 😞 😔 😟 😕 🙁 ☹️ 😣 😖 😫 😩 🥺 😢 😭 😤 😠 😡 🤬 🤯 😳 🥵 🥶 😱 😨 😰 😥 😓 🤗 🤔 🫣 🤭 🫢 🫡 🤫 🫠 🤥 😶 🫥 😐 🫤 😑 😬 🙄 😯 😦 😧 😮 😲 🥱 😴 🤤 😪 😵 🤐 🥴 🤢 🤮 🤧 😷 🤒 🤕 😈 👿 👻 💀 ☠️ 👽 🤖 🎃 😺 😸 😹 😻 😼 😽 🙀 😿 😾 👋 🤚 🖐️ ✋ 🖖 👌 🤌 🤏 ✌️ 🤞 🫰 🤟 🤘 🤙 👈 👉 👆 👇 ☝️ 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 🫶 👐 🤲 🤝 🙏 ✍️ 💅 🤳 💪 🦾 🦿 🦵 🦶 👂 👃 🧠 🫀 🫁 🦷 👀 👁️ 👅 👄"),
        category("animals", "动物与自然", "🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐻‍❄️ 🐨 🐯 🦁 🐮 🐷 🐽 🐸 🐵 🙈 🙉 🙊 🐒 🐔 🐧 🐦 🐤 🐣 🐥 🦆 🦅 🦉 🦇 🐺 🐗 🐴 🦄 🐝 🪱 🐛 🦋 🐌 🐞 🐜 🪰 🪲 🪳 🦟 🦗 🕷️ 🦂 🐢 🐍 🦎 🐙 🦑 🦐 🦞 🦀 🐡 🐠 🐟 🐬 🐳 🐋 🦈 🦭 🐊 🐅 🐆 🦓 🦍 🦧 🐘 🦛 🦏 🐪 🐫 🦒 🦘 🦬 🐃 🐂 🐄 🐎 🐖 🐏 🐑 🦙 🐐 🦌 🐕 🐩 🦮 🐕‍🦺 🐈 🐈‍⬛ 🪶 🐓 🦃 🦤 🦚 🦜 🦢 🦩 🕊️ 🐇 🦝 🦨 🦡 🦫 🦦 🦥 🐁 🐀 🐿️ 🦔 🌵 🎄 🌲 🌳 🌴 🪵 🌱 🌿 ☘️ 🍀 🎍 🪴 🎋 🍃 🍂 🍁 🍄 🐚 🪨 🌾 💐 🌷 🌹 🥀 🌺 🌸 🌼 🌻 ☀️ 🌤️ ⛅ 🌥️ ☁️ 🌦️ 🌧️ ⛈️ 🌩️ 🌨️ ❄️ ☃️ ⛄ 🌬️ 💨 🌈 ☂️ ☔ ⚡ 🌊"),
        category("food", "食物与饮品", "🍏 🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍈 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🍆 🥑 🥦 🥬 🥒 🌶️ 🫑 🌽 🥕 🫒 🧄 🧅 🥔 🍠 🥐 🥯 🍞 🥖 🥨 🧀 🥚 🍳 🧈 🥞 🧇 🥓 🥩 🍗 🍖 🌭 🍔 🍟 🍕 🫓 🥪 🥙 🧆 🌮 🌯 🫔 🥗 🥘 🫕 🥫 🍝 🍜 🍲 🍛 🍣 🍱 🥟 🦪 🍤 🍙 🍚 🍘 🍥 🥠 🥮 🍢 🍡 🍧 🍨 🍦 🥧 🧁 🍰 🎂 🍮 🍭 🍬 🍫 🍿 🍩 🍪 🌰 🥜 🍯 🥛 🍼 ☕ 🫖 🍵 🧃 🥤 🧋 🍶 🍺 🍻 🥂 🍷 🥃 🍸 🍹 🧉 🍾 🧊 🥄 🍴 🍽️ 🥣 🥡"),
        category("activity", "活动", "⚽ 🏀 🏈 ⚾ 🥎 🎾 🏐 🏉 🥏 🎱 🪀 🏓 🏸 🏒 🏑 🥍 🏏 🪃 🥅 ⛳ 🪁 🏹 🎣 🤿 🥊 🥋 🎽 🛹 🛼 🛷 ⛸️ 🥌 🎿 ⛷️ 🏂 🪂 🏋️ 🤼 🤸 ⛹️ 🤺 🤾 🏌️ 🏇 🧘 🏄 🏊 🤽 🚣 🧗 🚵 🚴 🏆 🥇 🥈 🥉 🏅 🎖️ 🏵️ 🎗️ 🎫 🎟️ 🎪 🤹 🎭 🩰 🎨 🎬 🎤 🎧 🎼 🎹 🥁 🪘 🎷 🎺 🪗 🎸 🪕 🎻 🎲 ♟️ 🎯 🎳 🎮 🎰 🧩"),
        category("travel", "旅行与地点", "🚗 🚕 🚙 🚌 🚎 🏎️ 🚓 🚑 🚒 🚐 🛻 🚚 🚛 🚜 🦯 🦽 🦼 🛴 🚲 🛵 🏍️ 🛺 🚨 🚔 🚍 🚘 🚖 🚡 🚠 🚟 🚃 🚋 🚞 🚝 🚄 🚅 🚈 🚂 🚆 🚇 🚊 🚉 ✈️ 🛫 🛬 🛩️ 💺 🛰️ 🚀 🛸 🚁 🛶 ⛵ 🚤 🛥️ 🛳️ ⛴️ 🚢 ⚓ 🪝 ⛽ 🚧 🚦 🚥 🗺️ 🗿 🗽 🗼 🏰 🏯 🏟️ 🎡 🎢 🎠 ⛲ ⛱️ 🏖️ 🏝️ 🏜️ 🌋 ⛰️ 🏔️ 🗻 🏕️ ⛺ 🛖 🏠 🏡 🏢 🏥 🏦 🏨 🏪 🏫 🏛️ ⛪ 🕌 🛕 🕍 ⛩️ 🕋 🌁 🌃 🏙️ 🌄 🌅 🌆 🌇 🌉 ♨️ 🎑 🏞️"),
        category("objects", "物品", "⌚ 📱 📲 💻 ⌨️ 🖥️ 🖨️ 🖱️ 🖲️ 🕹️ 🗜️ 💽 💾 💿 📀 📼 📷 📸 📹 🎥 📽️ 🎞️ 📞 ☎️ 📟 📠 📺 📻 🎙️ 🎚️ 🎛️ 🧭 ⏱️ ⏲️ ⏰ 🕰️ ⌛ ⏳ 📡 🔋 🪫 🔌 💡 🔦 🕯️ 🧯 🛢️ 💸 💵 💴 💶 💷 🪙 💳 💎 ⚖️ 🪜 🧰 🪛 🔧 🔨 ⚒️ 🛠️ ⛏️ 🪚 🔩 ⚙️ 🪤 🧱 ⛓️ 🧲 🔫 💣 🧨 🪓 🔪 🗡️ ⚔️ 🛡️ 🚬 ⚰️ 🪦 ⚱️ 🏺 🔮 📿 🧿 🪬 💈 ⚗️ 🔭 🔬 🕳️ 🩹 🩺 💊 💉 🩸 🧬 🦠 🧫 🧪 🌡️ 🧹 🪠 🧺 🧻 🚽 🚿 🛁 🧼 🪥 🪒 🧽 🪣 🧴 🛎️ 🔑 🗝️ 🚪 🪑 🛋️ 🛏️ 🧸 🪆 🖼️ 🪞 🪟 🛍️ 🛒 🎁 🎈 🎏 🎀 🪄 🪅 🎊 🎉 🪩 🎎 🏮 🎐 🧧 ✉️ 📩 📨 📧 💌 📥 📤 📦 🏷️ 🪧 📪 📫 📬 📭 📮 📯 📜 📃 📄 📑 🧾 📊 📈 📉 🗒️ 🗓️ 📆 📅 🗑️ 📇 🗃️ 🗳️ 🗄️ 📋 📁 📂 🗂️ 🗞️ 📰 📓 📔 📒 📕 📗 📘 📙 📚 📖 🔖 🧷 🔗 📎 🖇️ 📐 📏 🧮 📌 📍 ✂️ 🖊️ 🖋️ ✒️ 🖌️ 🖍️ 📝 ✏️ 🔍 🔎 🔏 🔐 🔒 🔓"),
        category("symbols", "符号", "❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟 ☮️ ✝️ ☪️ 🕉️ ☸️ ✡️ 🔯 🕎 ☯️ ☦️ 🛐 ⛎ ♈ ♉ ♊ ♋ ♌ ♍ ♎ ♏ ♐ ♑ ♒ ♓ 🆔 ⚛️ ☢️ ☣️ 📴 📳 🈶 🈚 🈸 🈺 🈷️ ✴️ 🆚 💮 🉐 ㊙️ ㊗️ 🈴 🈵 🈹 🈲 🅰️ 🅱️ 🆎 🆑 🅾️ 🆘 ❌ ⭕ 🛑 ⛔ 📛 🚫 💯 💢 ♨️ 🚷 🚯 🚳 🚱 🔞 📵 🚭 ❗ ❕ ❓ ❔ ‼️ ⁉️ 🔅 🔆 〽️ ⚠️ 🚸 🔱 ⚜️ 🔰 ♻️ ✅ 🈯 💹 ❇️ ✳️ ❎ 🌐 💠 Ⓜ️ 🌀 💤 🏧 🚾 ♿ 🅿️ 🛗 🈳 🈂️ 🛂 🛃 🛄 🛅 🚹 🚺 🚼 ⚧️ 🚻 🚮 🎦 📶 🈁 🔣 ℹ️ 🔤 🔡 🔠 🆖 🆗 🆙 🆒 🆕 🆓 0️⃣ 1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ 8️⃣ 9️⃣ 🔟 🔢 ▶️ ⏸️ ⏯️ ⏹️ ⏺️ ⏭️ ⏮️ ⏩ ⏪ 🔀 🔁 🔂 ◀️ 🔼 🔽 ⏫ ⏬ ➡️ ⬅️ ⬆️ ⬇️ ↗️ ↘️ ↙️ ↖️ ↕️ ↔️ 🔄 ↪️ ↩️ ⤴️ ⤵️ #️⃣ *️⃣ ⏏️ 🎵 🎶 ➕ ➖ ➗ ✖️ 🟰 ♾️ 💲 ©️ ®️ ™️ 🔚 🔙 🔛 🔝 🔜 ✔️ ☑️ 🔘 🔴 🟠 🟡 🟢 🔵 🟣 ⚫ ⚪ 🟤 🔺 🔻 🔸 🔹 🔶 🔷 🔳 🔲 ◼️ ◻️ ◾ ◽ ▪️ ▫️ 🟧 🟨 🟩 🟦 🟪 🟫 ⬛ ⬜"),
        category("flags", "旗帜", "🏳️ 🏴 🏁 🚩 🏳️‍🌈 🏳️‍⚧️ 🇨🇳 🇭🇰 🇲🇴 🇹🇼 🇯🇵 🇰🇷 🇸🇬 🇺🇸 🇨🇦 🇲🇽 🇧🇷 🇦🇷 🇬🇧 🇫🇷 🇩🇪 🇮🇹 🇪🇸 🇵🇹 🇳🇱 🇧🇪 🇨🇭 🇦🇹 🇸🇪 🇳🇴 🇩🇰 🇫🇮 🇮🇸 🇮🇪 🇵🇱 🇨🇿 🇬🇷 🇹🇷 🇺🇦 🇷🇺 🇮🇳 🇹🇭 🇻🇳 🇲🇾 🇮🇩 🇵🇭 🇦🇺 🇳🇿 🇿🇦 🇪🇬 🇸🇦 🇦🇪 🇮🇱 🇺🇳"),
    ]

    static var all: [String] { categories.flatMap(\.emojis) }

    private static let searchGroups: [RadialIconSearchGroup] = [
        .init("笑 开心 高兴 快乐 微笑 大笑 happy smile laugh joy xiao kaixin", "😀 😃 😄 😁 😆 😅 😂 🤣 😊 🙂 😉 😍 😎 🤩 🥳"),
        .init("哭 难过 伤心 悲伤 sad cry tears ku nanguo", "😞 😔 😟 🙁 ☹️ 😣 😖 😫 😩 🥺 😢 😭 😿 💔"),
        .init("生气 愤怒 火大 angry mad rage shengqi", "😤 😠 😡 🤬 👿 💢 🔥"),
        .init("爱 喜欢 心 红心 love heart like ai xihuan", "😍 🥰 😘 ❤️ 🧡 💛 💚 💙 💜 💕 💞 💓 💗 💖 💘 💝"),
        .init("数字 数字键 数字键帽 编号 号码 计数 number numbers numeric digit keycap 123 shuzi", "0️⃣ 1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ 8️⃣ 9️⃣ 🔟 🔢 #️⃣ *️⃣ ➕ ➖ ➗ ✖️ 🟰 💯"),
        .init("用户 人物 人 个人 账户 账号 头像 团队 user person people profile account avatar team yonghu renwu", "👤 👥 🧑 👨 👩 👦 👧 🧒 👶 🧑‍💻 🧑‍💼 👨‍💻 👩‍💻 🤝 👀 🧠"),
        .init("手 手势 点击 指向 赞 同意 反对 hand gesture click point thumb approve reject", "👋 🤚 🖐️ ✋ 🖖 👌 🤌 🤏 ✌️ 🤞 🤟 🤘 🤙 👈 👉 👆 👇 ☝️ 👍 👎 ✊ 👊 👏 🙌 🙏"),
        .init("工作 办公 电脑 键盘 鼠标 手机 文件 文件夹 图表 work office computer keyboard mouse phone file folder chart", "💻 ⌨️ 🖥️ 🖨️ 🖱️ 📱 📊 📈 📉 📋 📁 📂 🗂️ 📝 ✏️"),
        .init("搜索 查找 放大镜 search find magnifier", "🔍 🔎 🧐"),
        .init("时间 时钟 闹钟 计时 日历 time clock alarm timer calendar", "⌚ ⏱️ ⏲️ ⏰ 🕰️ ⌛ ⏳ 🗓️ 📆 📅"),
        .init("成功 完成 正确 勾选 确认 success done correct check confirm", "✅ ✔️ ☑️ 👍 🎉 🏆"),
        .init("警告 注意 危险 错误 禁止 warning alert danger error stop", "⚠️ ❗ ❕ ‼️ ⁉️ 🛑 ⛔ ❌ 🚫"),
        .init("方向 箭头 前进 后退 上 下 左 右 direction arrow forward back up down left right", "➡️ ⬅️ ⬆️ ⬇️ ↗️ ↘️ ↙️ ↖️ ↕️ ↔️ 🔄 ↪️ ↩️ ⤴️ ⤵️ ▶️ ◀️ ⏩ ⏪"),
        .init("沟通 消息 聊天 邮件 电话 通知 communication message chat mail email phone notification", "💬 🗨️ 🗯️ ✉️ 📩 📨 📧 💌 📞 ☎️ 📣 🔔"),
        .init("钱 金钱 支付 银行 卡 money cash payment bank card", "💸 💵 💴 💶 💷 🪙 💳 💎 🏦"),
        .init("音乐 声音 麦克风 耳机 music audio sound microphone headphones", "🎵 🎶 🎤 🎧 🎼 🎹 🥁 🎷 🎺 🎸 🎻 🔊"),
        .init("图片 照片 相机 摄像 视频 image photo picture camera video", "🖼️ 📷 📸 📹 🎥 📽️ 🎞️"),
        .init("设置 工具 修理 齿轮 settings tools repair gear", "⚙️ 🧰 🪛 🔧 🔨 ⚒️ 🛠️"),
        .init("锁 安全 密码 钥匙 盾牌 lock security password key shield", "🔒 🔓 🔐 🔏 🔑 🗝️ 🛡️"),
        .init("天气 太阳 月亮 云 雨 雪 闪电 weather sun moon cloud rain snow lightning", "☀️ 🌤️ ⛅ 🌥️ ☁️ 🌦️ 🌧️ ⛈️ 🌩️ 🌨️ ❄️ 🌈 ⚡"),
        .init("动物 宠物 猫 狗 animal pet cat dog", "🐶 🐱 🐭 🐰 🦊 🐻 🐼 🐯 🦁 🐸 🐵 🐧 🐦 🐴 🐝 🦋 🐢 🐍 🐬 🐳"),
        .init("食物 饮料 吃 喝 food drink eat", "🍎 🍊 🍋 🍌 🍉 🍇 🍓 🍒 🍔 🍟 🍕 🍜 🍚 🍰 ☕ 🍵 🧃 🥤"),
        .init("运动 游戏 奖杯 活动 sport game trophy activity", "⚽ 🏀 🏈 ⚾ 🎾 🏐 🏓 🏸 🏆 🥇 🎯 🎮 🧩"),
        .init("旅行 地点 汽车 飞机 火车 船 地图 家 travel location car airplane train ship map home", "🚗 🚕 🚌 🚲 ✈️ 🚀 🚁 🚂 🚆 🚇 🚢 🗺️ 🏠 🏡 🏢"),
    ]

    private static let searchCandidates: [String] = {
        var seen = Set<String>()
        return (all + searchGroups.flatMap(\.values)).filter { seen.insert($0).inserted }
    }()

    static func search(_ query: String, categoryID: String?) -> [String] {
        let source = categoryID.flatMap { id in categories.first(where: { $0.id == id })?.emojis } ?? all
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return source }

        return searchCandidates.enumerated().compactMap { offset, emoji -> (String, Int, Int)? in
            var fields = [emoji]
            for category in categories where category.emojis.contains(emoji) {
                fields.append(contentsOf: [category.title, category.id])
            }
            for group in searchGroups where group.values.contains(emoji) {
                fields.append(group.terms)
            }
            guard let score = RadialFuzzySearch.score(query: query, fields: fields) else { return nil }
            return (emoji, score, offset)
        }
        .sorted { lhs, rhs in lhs.1 == rhs.1 ? lhs.2 < rhs.2 : lhs.1 > rhs.1 }
        .map(\.0)
    }

    private static func category(_ id: String, _ title: String, _ values: String) -> RadialEmojiCategory {
        RadialEmojiCategory(id: id, title: title, emojis: values.split(separator: " ").map(String.init))
    }
}

struct RadialSymbolCategory: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let symbols: [String]
}

enum RadialSymbolCatalog {
    static let categories: [RadialSymbolCategory] = [
        category("recommended", "推荐", symbols: RadialIconCatalog.codexSymbols),
        category("general", "通用", keywords: ["command", "option", "control", "shift", "keyboard", "square", "circle", "plus", "minus", "ellipsis", "checkmark", "xmark", "questionmark", "info", "exclamationmark", "star", "heart", "bolt", "sparkles"]),
        category("application", "应用", keywords: ["app", "window", "macwindow", "sidebar", "rectangle", "menubar", "dock", "safari", "globe"]),
        category("system", "系统", keywords: ["gear", "slider", "switch", "power", "lock", "shield", "key", "wifi", "network", "icloud", "cloud", "display", "desktopcomputer", "macbook", "memorychip", "cpu", "externaldrive", "internaldrive", "battery"]),
        category("office", "办公", keywords: ["doc", "folder", "tray", "inbox", "archive", "clipboard", "paperclip", "link", "list", "table", "chart", "calendar", "clock", "timer", "bookmark", "flag", "pin", "printer"]),
        category("communication", "沟通", keywords: ["message", "bubble", "envelope", "phone", "video", "mic", "speaker", "person", "at", "paperplane", "bell"]),
        category("editing", "编辑", keywords: ["pencil", "eraser", "scissors", "crop", "rotate", "arrow.uturn", "text", "character", "paragraph", "paintbrush", "eyedropper"]),
        category("development", "开发", keywords: ["terminal", "chevron.left.forwardslash", "curlybraces", "ladybug", "hammer", "wrench", "shippingbox", "puzzlepiece", "server", "memorychip", "cpu"]),
        category("design", "设计", keywords: ["photo", "camera", "paint", "wand", "eyedropper", "viewfinder", "scope", "ruler", "scribble", "lasso", "circle.hexagon"]),
        category("media", "媒体", keywords: ["play", "pause", "stop", "forward", "backward", "record", "music", "headphones", "waveform", "film", "video", "photo", "camera"]),
        category("navigation", "导航", keywords: ["arrow", "chevron", "location", "map", "house", "building", "signpost"]),
    ]

    static var all: [String] { RadialIconCatalog.allSymbols }

    private static let searchGroups: [RadialIconSearchGroup] = [
        .init("数字 编号 号码 计数 number numeric digit 123 shuzi", "number 0.circle.fill 1.circle.fill 2.circle.fill 3.circle.fill 4.circle.fill 5.circle.fill 6.circle.fill 7.circle.fill 8.circle.fill 9.circle.fill textformat.123"),
        .init("用户 人物 个人 账户 账号 头像 团队 user person people profile account avatar team yonghu", "person.fill person.2.fill person.3.fill person.crop.circle.fill person.crop.circle.badge.plus person.2.badge.gearshape.fill shared.with.you"),
        .init("搜索 查找 放大镜 search find magnifier", "magnifyingglass doc.text.magnifyingglass plus.magnifyingglass minus.magnifyingglass"),
        .init("设置 系统 偏好 齿轮 settings system preferences gear", "gearshape.fill slider.horizontal.3 switch.2 wrench.and.screwdriver.fill"),
        .init("主页 首页 家 home house homepage", "house.fill house.circle.fill"),
        .init("文件 文档 文件夹 复制 剪贴板 file document folder copy clipboard", "doc.fill doc.text.fill doc.on.doc.fill doc.on.clipboard.fill folder.fill folder.badge.plus clipboard.fill paperclip"),
        .init("成功 完成 正确 勾选 确认 success done correct check confirm", "checkmark.circle.fill checkmark.seal.fill checklist hand.thumbsup.fill"),
        .init("错误 关闭 删除 取消 error close delete cancel", "xmark.circle.fill trash.fill minus.circle.fill exclamationmark.triangle.fill"),
        .init("警告 注意 危险 warning alert danger", "exclamationmark.triangle.fill info.circle.fill questionmark.circle.fill shield.fill"),
        .init("方向 箭头 前进 后退 上 下 左 右 direction arrow forward backward up down left right", "arrow.left arrow.right arrow.up arrow.down arrow.clockwise arrow.counterclockwise arrowshape.left.fill arrowshape.right.fill arrowshape.up.fill arrowshape.down.fill chevron.left.2 chevron.right.2"),
        .init("应用 程序 窗口 app application window", "app.fill app.badge.fill square.grid.2x2.fill macwindow macwindow.badge.plus menubar.rectangle dock.rectangle"),
        .init("聊天 消息 邮件 电话 通知 chat message mail email phone notification", "message.fill bubble.left.fill text.bubble.fill envelope.fill phone.fill bell.fill paperplane.fill"),
        .init("时间 时钟 计时 日历 time clock timer calendar", "clock.fill timer calendar calendar.badge.plus clock.arrow.circlepath"),
        .init("图片 照片 相机 视频 image photo picture camera video", "photo.fill camera.fill video.fill film.fill play.rectangle.fill"),
        .init("音乐 声音 麦克风 耳机 music audio sound microphone headphones", "music.note music.note.list headphones waveform mic.fill speaker.wave.2.fill speaker.wave.3.fill"),
        .init("开发 代码 终端 调试 bug developer code terminal debug", "terminal.fill terminal apple.terminal.fill chevron.left.forwardslash.chevron.right curlybraces.square.fill ladybug.fill"),
        .init("网络 云 无线 network cloud wifi wireless", "network wifi antenna.radiowaves.left.and.right icloud.fill cloud.fill globe"),
        .init("安全 锁 密码 钥匙 盾牌 security lock password key shield", "lock.fill lock.open.fill key.fill shield.fill network.badge.shield.half.filled"),
        .init("播放 暂停 停止 快进 后退 play pause stop forward backward media", "play.fill pause.fill stop.fill forward.fill backward.fill record.circle"),
    ]

    private static let searchCandidates: [String] = {
        var seen = Set<String>()
        return (all + searchGroups.flatMap(\.values)).filter { seen.insert($0).inserted }
    }()

    static func search(_ query: String, categoryID: String?) -> [String] {
        let source = categoryID.flatMap { id in categories.first(where: { $0.id == id })?.symbols } ?? all
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return source }

        return searchCandidates.enumerated().compactMap { offset, symbol -> (String, Int, Int)? in
            var fields = [symbol]
            for category in categories where category.symbols.contains(symbol) {
                fields.append(contentsOf: [category.title, category.id])
            }
            for group in searchGroups where group.values.contains(symbol) {
                fields.append(group.terms)
            }
            guard let score = RadialFuzzySearch.score(query: query, fields: fields) else { return nil }
            return (symbol, score, offset)
        }
        .sorted { lhs, rhs in lhs.1 == rhs.1 ? lhs.2 < rhs.2 : lhs.1 > rhs.1 }
        .map(\.0)
    }

    private static func category(_ id: String, _ title: String, symbols: [String]) -> RadialSymbolCategory {
        RadialSymbolCategory(id: id, title: title, symbols: Array(Set(symbols)).sorted())
    }

    private static func category(_ id: String, _ title: String, keywords: [String]) -> RadialSymbolCategory {
        category(
            id,
            title,
            symbols: RadialIconCatalog.allSymbols.filter { symbol in
                keywords.contains { symbol.localizedCaseInsensitiveContains($0) }
            }
        )
    }
}
