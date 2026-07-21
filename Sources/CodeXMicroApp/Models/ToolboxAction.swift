import Foundation

enum ToolboxCategory: String, CaseIterable, Identifiable, Sendable {
    case all
    case essentials
    case tasks
    case code
    case git
    case tools
    case navigation
    case view

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .essentials: "常用"
        case .tasks: "任务"
        case .code: "代码"
        case .git: "Git"
        case .tools: "工具"
        case .navigation: "导航"
        case .view: "界面"
        }
    }
}

enum ToolboxActionKind: String, Sendable {
    case shortcut
    case destination
    case workflow

    var label: String {
        switch self {
        case .shortcut: "官方快捷键"
        case .destination: "官方入口"
        case .workflow: "一键工作流"
        }
    }
}

enum ToolboxAction: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case fast
    case approve
    case decline
    case send
    case newTask
    case fork
    case plan
    case dictation
    case quickChat
    case openCodex

    case searchTasks
    case findInTask
    case previousTask
    case nextTask
    case archiveTask
    case pinTask
    case copyTaskMarkdown

    case reviewChanges
    case reviewPanel
    case terminal
    case clearTerminal
    case debug
    case runTests
    case refactor
    case explainCodebase
    case frontendPolish

    case gitStatus
    case gitCommit
    case newBranch
    case mergeBranch
    case createPullRequest
    case reviewPullRequest
    case commitAndPush

    case browser
    case attachFiles
    case addPhotos
    case openFolder
    case openAIDocs
    case skills
    case automations
    case plugins

    case commandMenu
    case historyBack
    case historyForward
    case toggleSidebar

    case settings
    case keyboardShortcuts
    case toggleBottomPanel
    case fontUp
    case fontDown
    case reasoningUp
    case reasoningDown

    var id: String { rawValue }

    var category: ToolboxCategory {
        switch self {
        case .fast, .approve, .decline, .send, .newTask, .fork, .plan, .dictation, .quickChat, .openCodex:
            .essentials
        case .searchTasks, .findInTask, .previousTask, .nextTask, .archiveTask, .pinTask, .copyTaskMarkdown:
            .tasks
        case .reviewChanges, .reviewPanel, .terminal, .clearTerminal, .debug, .runTests, .refactor, .explainCodebase, .frontendPolish:
            .code
        case .gitStatus, .gitCommit, .newBranch, .mergeBranch, .createPullRequest, .reviewPullRequest, .commitAndPush:
            .git
        case .browser, .attachFiles, .addPhotos, .openFolder, .openAIDocs, .skills, .automations, .plugins:
            .tools
        case .commandMenu, .historyBack, .historyForward, .toggleSidebar:
            .navigation
        case .settings, .keyboardShortcuts, .toggleBottomPanel, .fontUp, .fontDown, .reasoningUp, .reasoningDown:
            .view
        }
    }

    var kind: ToolboxActionKind {
        switch self {
        case .debug, .runTests, .refactor, .explainCodebase, .frontendPolish,
             .gitStatus, .newBranch, .mergeBranch, .reviewPullRequest, .commitAndPush:
            .workflow
        case .openAIDocs, .skills, .automations, .plugins, .settings:
            .destination
        default:
            .shortcut
        }
    }

    var keycap: String {
        switch self {
        case .fast: "FAST"
        case .approve: "APPR"
        case .decline: "REJ"
        case .send: "SEND"
        case .newTask: "NEW"
        case .fork: "FORK"
        case .plan: "PLAN"
        case .dictation: "VOICE"
        case .quickChat: "CHAT"
        case .openCodex: "CODEX"
        case .searchTasks: "SRCH"
        case .findInTask: "FIND"
        case .previousTask: "PREV"
        case .nextTask: "NEXT"
        case .archiveTask: "DEL"
        case .pinTask: "PIN"
        case .copyTaskMarkdown: "COPY"
        case .reviewChanges: "DIFF"
        case .reviewPanel: "REV"
        case .terminal: "TERM"
        case .clearTerminal: "CLR"
        case .debug: "BUG"
        case .runTests: "PLAY"
        case .refactor: "MAGIC"
        case .explainCodebase: "MAP"
        case .frontendPolish: "PAINT"
        case .gitStatus: "STAT"
        case .gitCommit: "GIT"
        case .newBranch: "BRCH"
        case .mergeBranch: "MRG"
        case .createPullRequest: "PR"
        case .reviewPullRequest: "RPR"
        case .commitAndPush: "YEET"
        case .browser: "NAV"
        case .attachFiles: "UPL"
        case .addPhotos: "PHOTO"
        case .openFolder: "FOLD"
        case .openAIDocs: "OAI"
        case .skills: "SKILL"
        case .automations: "TIME"
        case .plugins: "APPS"
        case .commandMenu: "CMD"
        case .historyBack: "BACK"
        case .historyForward: "FWD"
        case .toggleSidebar: "SIDE"
        case .settings: "SETUP"
        case .keyboardShortcuts: "KEYS"
        case .toggleBottomPanel: "PANEL"
        case .fontUp: "FONT+"
        case .fontDown: "FONT-"
        case .reasoningUp: "MIND+"
        case .reasoningDown: "MIND-"
        }
    }

    var title: String {
        switch self {
        case .fast: "Fast 模式"
        case .approve: "同意请求"
        case .decline: "拒绝请求"
        case .send: "发送消息"
        case .newTask: "新建任务"
        case .fork: "继续到新任务"
        case .plan: "Plan 模式"
        case .dictation: "语音听写"
        case .quickChat: "快速聊天"
        case .openCodex: "打开 Codex"
        case .searchTasks: "搜索任务"
        case .findInTask: "任务内查找"
        case .previousTask: "上一个任务"
        case .nextTask: "下一个任务"
        case .archiveTask: "归档任务"
        case .pinTask: "置顶任务"
        case .copyTaskMarkdown: "复制任务 Markdown"
        case .reviewChanges: "审阅改动"
        case .reviewPanel: "Review 面板"
        case .terminal: "终端"
        case .clearTerminal: "清空终端"
        case .debug: "诊断错误"
        case .runTests: "运行测试"
        case .refactor: "安全重构"
        case .explainCodebase: "理解代码库"
        case .frontendPolish: "打磨界面"
        case .gitStatus: "检查 Git 状态"
        case .gitCommit: "提交改动"
        case .newBranch: "创建分支"
        case .mergeBranch: "合并分支"
        case .createPullRequest: "创建 PR"
        case .reviewPullRequest: "审查 PR"
        case .commitAndPush: "验证并推送"
        case .browser: "打开浏览器"
        case .attachFiles: "添加文件"
        case .addPhotos: "添加图片"
        case .openFolder: "打开文件夹"
        case .openAIDocs: "OpenAI 文档"
        case .skills: "Skills"
        case .automations: "定时任务"
        case .plugins: "插件与 Apps"
        case .commandMenu: "命令菜单"
        case .historyBack: "后退"
        case .historyForward: "前进"
        case .toggleSidebar: "侧边栏"
        case .settings: "设置"
        case .keyboardShortcuts: "快捷键列表"
        case .toggleBottomPanel: "底部面板"
        case .fontUp: "增大字号"
        case .fontDown: "减小字号"
        case .reasoningUp: "提高推理强度"
        case .reasoningDown: "降低推理强度"
        }
    }

    var detail: String {
        switch kind {
        case .shortcut: "直接执行"
        case .destination: "打开对应页面"
        case .workflow: "新任务中执行"
        }
    }

    var systemImage: String {
        switch self {
        case .fast: "bolt.fill"
        case .approve: "checkmark.circle.fill"
        case .decline: "xmark.circle.fill"
        case .send: "paperplane.fill"
        case .newTask: "plus.square.fill"
        case .fork: "arrow.triangle.branch"
        case .plan: "list.clipboard.fill"
        case .dictation: "mic.fill"
        case .quickChat: "message.fill"
        case .openCodex: "keyboard.fill"
        case .searchTasks: "magnifyingglass"
        case .findInTask: "doc.text.magnifyingglass"
        case .previousTask: "chevron.left.2"
        case .nextTask: "chevron.right.2"
        case .archiveTask: "archivebox.fill"
        case .pinTask: "pin.fill"
        case .copyTaskMarkdown: "doc.on.doc.fill"
        case .reviewChanges: "doc.text.fill"
        case .reviewPanel: "rectangle.split.2x1.fill"
        case .terminal: "terminal.fill"
        case .clearTerminal: "trash.fill"
        case .debug: "ladybug.fill"
        case .runTests: "play.fill"
        case .refactor: "wand.and.stars"
        case .explainCodebase: "map.fill"
        case .frontendPolish: "paintbrush.fill"
        case .gitStatus: "point.3.connected.trianglepath.dotted"
        case .gitCommit: "checkmark.seal.fill"
        case .newBranch: "arrow.triangle.branch"
        case .mergeBranch: "arrow.merge"
        case .createPullRequest: "arrow.up.right.square.fill"
        case .reviewPullRequest: "checklist"
        case .commitAndPush: "paperplane.circle.fill"
        case .browser: "globe"
        case .attachFiles: "paperclip"
        case .addPhotos: "photo.fill"
        case .openFolder: "folder.fill"
        case .openAIDocs: "book.closed.fill"
        case .skills: "sparkles"
        case .automations: "clock.fill"
        case .plugins: "puzzlepiece.extension.fill"
        case .commandMenu: "command"
        case .historyBack: "arrow.left"
        case .historyForward: "arrow.right"
        case .toggleSidebar: "sidebar.left"
        case .settings: "gearshape.fill"
        case .keyboardShortcuts: "keyboard.badge.ellipsis"
        case .toggleBottomPanel: "rectangle.bottomthird.inset.filled"
        case .fontUp: "plus.magnifyingglass"
        case .fontDown: "minus.magnifyingglass"
        case .reasoningUp: "brain.head.profile.fill"
        case .reasoningDown: "brain.head.profile"
        }
    }

    var searchText: String {
        [keycap, title, detail, category.title, kind.label, rawValue].joined(separator: " ").lowercased()
    }

    var workflowPrompt: String? {
        switch self {
        case .debug:
            "请诊断当前项目最近的问题：先复现并定位根因，再做最小修复并运行相关验证。"
        case .runTests:
            "请运行当前项目最相关的测试，分析失败原因，修复由当前改动造成的问题，并报告验证结果。"
        case .refactor:
            "请找出当前项目最值得整理的一处实现，在保持行为不变的前提下做小范围重构并验证。"
        case .explainCodebase:
            "请快速梳理当前代码库的入口、核心模块、数据流与主要运行方式，给出一份可执行的代码地图。"
        case .frontendPolish:
            "请检查当前界面的视觉与交互质量，优先修复明显的布局、间距、溢出和状态反馈问题，并进行实际渲染验证。"
        case .gitStatus:
            "请检查当前仓库的 Git 状态和改动范围，按已修改、未跟踪、已暂存与潜在风险给出结论；不要改文件。"
        case .newBranch:
            "请基于当前工作创建一个语义清晰的新分支；先检查未提交改动并确保不会覆盖用户现有工作。"
        case .mergeBranch:
            "请检查当前分支与目标分支的状态，确认目标后安全合并，解决可验证的冲突并运行相关测试。"
        case .reviewPullRequest:
            "请审查当前 pull request 或最近变更，优先指出可复现的缺陷、回归风险和缺失测试。"
        case .commitAndPush:
            "请检查当前改动范围，运行相关验证，创建意图清晰的 commit，并在确认远端与分支安全后推送。"
        default:
            nil
        }
    }

    var microAction: MicroAction? {
        switch self {
        case .fast: .fast
        case .approve: .approve
        case .decline: .decline
        case .send: .send
        case .newTask: .newTask
        case .fork: .fork
        case .plan: .plan
        case .openCodex: .openCodex
        case .reasoningUp: .reasoningUp
        case .reasoningDown: .reasoningDown
        default: nil
        }
    }
}
