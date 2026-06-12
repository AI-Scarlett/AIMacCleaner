import SwiftUI
import Foundation

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case maltese = "mt"

    static var allCases: [AppLanguage] {
        [.english, .simplifiedChinese, .traditionalChinese, .japanese, .korean, .maltese]
    }

    var displayName: String {
        switch self {
        case .simplifiedChinese: return "中文"
        case .english: return "English"
        case .traditionalChinese: return "繁體中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .maltese: return "Malti"
        }
    }

    var nativeName: String {
        switch self {
        case .simplifiedChinese: return "中文"
        case .english: return "EN"
        case .traditionalChinese: return "繁體"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .maltese: return "Malti"
        }
    }

    var appName: String {
        switch self {
        case .simplifiedChinese: return "Agent卫士"
        case .english: return "AgentGuard"
        case .traditionalChinese: return "Agent衛士"
        case .japanese: return "Agentガード"
        case .korean: return "Agent가드"
        case .maltese: return "AgentGuard"
        }
    }

    var flag: String {
        switch self {
        case .simplifiedChinese: return "🇨🇳"
        case .english: return "🇺🇸"
        case .traditionalChinese: return "🇭🇰"
        case .japanese: return "🇯🇵"
        case .korean: return "🇰🇷"
        case .maltese: return "🇲🇹"
        }
    }

    var label: String {
        switch self {
        case .simplifiedChinese: return "中文"
        case .english: return "English"
        case .traditionalChinese: return "繁體"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .maltese: return "Malti"
        }
    }
}

class Localizer: ObservableObject {
    private var didFinishInit = false

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
            if didFinishInit {
                UserDefaults.standard.set(true, forKey: "appLanguageUserSelected")
            }
            objectWillChange.send()
        }
    }

    init() {
        let hasUserSelection = UserDefaults.standard.bool(forKey: "appLanguageUserSelected")
        let saved = hasUserSelection ? (UserDefaults.standard.string(forKey: "appLanguage") ?? "en") : "en"
        language = AppLanguage(rawValue: saved) ?? .english
        didFinishInit = true
    }

    func t(_ zh: String, en: String, zhHant: String? = nil, ja: String? = nil, ko: String? = nil, mt: String? = nil) -> String {
        switch language {
        case .english: return en
        case .traditionalChinese: return zhHant ?? zh
        case .japanese: return ja ?? en
        case .korean: return ko ?? en
        case .maltese: return mt ?? en
        default: return zh
        }
    }

    var appName: String { language.appName }

    func localizedSubCategory(_ cat: String) -> String {
        switch cat {
        case "包管理", "Package Manager": return t("包管理", en: "Package Manager", zhHant: "包管理", ja: "パッケージ管理", ko: "패키지 관리", mt: "Package Manager")
        case "开发", "Development": return t("开发", en: "Development", zhHant: "開發", ja: "開発", ko: "개발", mt: "Development")
        case "项目产物", "Project Artifacts": return t("项目产物", en: "Project Artifacts", zhHant: "項目產物", ja: "プロジェクト成果物", ko: "프로젝트 산출물", mt: "Project Artifacts")
        case "安装包", "Installers": return t("安装包", en: "Installers", zhHant: "安裝套件", ja: "インストーラ", ko: "설치 패키지", mt: "Installers")
        case "应用", "Apps": return t("应用", en: "Apps", zhHant: "應用", ja: "アプリ", ko: "앱", mt: "Apps")
        case "其它", "Other": return t("其它", en: "Other", zhHant: "其它", ja: "その他", ko: "기타", mt: "Other")
        case "浏览器", "Browser": return t("浏览器", en: "Browser", zhHant: "瀏覽器", ja: "ブラウザ", ko: "브라우저", mt: "Browser")
        case "办公", "Office": return t("办公", en: "Office", zhHant: "辦公", ja: "オフィス", ko: "오피스", mt: "Office")
        case "AI Agent": return "AI Agent"
        case "系统", "System": return t("系统", en: "System", zhHant: "系統", ja: "システム", ko: "시스템", mt: "System")
        case "社交", "Social": return t("社交", en: "Social", zhHant: "社交", ja: "ソーシャル", ko: "소셜", mt: "Social")
        case "CLI": return "CLI"
        default: return cat
        }
    }

    func localizedAppDisplayName(_ name: String) -> String {
        switch name {
        case "Homebrew 包管理器": return t("Homebrew 包管理器", en: "Homebrew Package Manager", zhHant: "Homebrew 套件管理器", ja: "Homebrew パッケージマネージャー", ko: "Homebrew 패키지 관리자", mt: "Homebrew Package Manager")
        case "Node.js 运行环境": return t("Node.js 运行环境", en: "Node.js Runtime", zhHant: "Node.js 執行環境", ja: "Node.js ランタイム", ko: "Node.js 런타임", mt: "Node.js Runtime")
        case "Python 版本管理": return t("Python 版本管理", en: "Python Version Manager", zhHant: "Python 版本管理", ja: "Python バージョン管理", ko: "Python 버전 관리자", mt: "Python Version Manager")
        case "Rust 工具链": return t("Rust 工具链", en: "Rust Toolchain", zhHant: "Rust 工具鏈", ja: "Rust ツールチェーン", ko: "Rust 툴체인", mt: "Rust Toolchain")
        case "Go 语言环境": return t("Go 语言环境", en: "Go Language Environment", zhHant: "Go 語言環境", ja: "Go 言語環境", ko: "Go 언어 환경", mt: "Go Language Environment")
        case "Docker 容器": return t("Docker 容器", en: "Docker Containers", zhHant: "Docker 容器", ja: "Docker コンテナ", ko: "Docker 컨테이너", mt: "Docker Containers")
        case "Trae AI 编程助手": return t("Trae AI 编程助手", en: "Trae AI Coding Assistant", zhHant: "Trae AI 編程助手", ja: "Trae AI コーディングアシスタント", ko: "Trae AI 코딩 도우미", mt: "Trae AI Coding Assistant")
        case "CodeBuddy 编程助手": return t("CodeBuddy 编程助手", en: "CodeBuddy Coding Assistant", zhHant: "CodeBuddy 編程助手", ja: "CodeBuddy コーディングアシスタント", ko: "CodeBuddy 코딩 도우미", mt: "CodeBuddy Coding Assistant")
        case "Cursor AI 编辑器": return t("Cursor AI 编辑器", en: "Cursor AI Editor", zhHant: "Cursor AI 編輯器", ja: "Cursor AI エディタ", ko: "Cursor AI 에디터", mt: "Cursor AI Editor")
        case "Windsurf 编辑器": return t("Windsurf 编辑器", en: "Windsurf Editor", zhHant: "Windsurf 編輯器", ja: "Windsurf エディタ", ko: "Windsurf 에디터", mt: "Windsurf Editor")
        case "豆包 AI 助手": return t("豆包 AI 助手", en: "Doubao AI Assistant", zhHant: "豆包 AI 助手", ja: "Doubao AI アシスタント", ko: "Doubao AI 어시스턴트", mt: "Doubao AI Assistant")
        case "通义千问 AI": return t("通义千问 AI", en: "Qianwen AI", zhHant: "通義千問 AI", ja: "Qianwen AI", ko: "Qianwen AI", mt: "Qianwen AI")
        case "Xcode 开发者数据": return t("Xcode 开发者数据", en: "Xcode Developer Data", zhHant: "Xcode 開發者資料", ja: "Xcode 開発者データ", ko: "Xcode 개발자 데이터", mt: "Xcode Developer Data")
        case "Unity 引擎": return t("Unity 引擎", en: "Unity Engine", zhHant: "Unity 引擎", ja: "Unity エンジン", ko: "Unity 엔진", mt: "Unity Engine")
        case "Gradle 构建工具": return t("Gradle 构建工具", en: "Gradle Build Tool", zhHant: "Gradle 建置工具", ja: "Gradle ビルドツール", ko: "Gradle 빌드 도구", mt: "Gradle Build Tool")
        case "Maven 构建工具": return t("Maven 构建工具", en: "Maven Build Tool", zhHant: "Maven 建置工具", ja: "Maven ビルドツール", ko: "Maven 빌드 도구", mt: "Maven Build Tool")
        case "CocoaPods 依赖管理": return t("CocoaPods 依赖管理", en: "CocoaPods Dependency Manager", zhHant: "CocoaPods 依賴管理", ja: "CocoaPods 依存関係管理", ko: "CocoaPods 의존성 관리자", mt: "CocoaPods Dependency Manager")
        case "NVM (Node版本管理)": return t("NVM (Node版本管理)", en: "NVM (Node Version Manager)", zhHant: "NVM (Node 版本管理)", ja: "NVM (Node バージョン管理)", ko: "NVM (Node 버전 관리자)", mt: "NVM (Node Version Manager)")
        case "npm 全局缓存": return t("npm 全局缓存", en: "npm Global Cache", zhHant: "npm 全域快取", ja: "npm グローバルキャッシュ", ko: "npm 전역 캐시", mt: "npm Global Cache")
        case "pnpm 存储": return t("pnpm 存储", en: "pnpm Store", zhHant: "pnpm 儲存區", ja: "pnpm ストア", ko: "pnpm 저장소", mt: "pnpm Store")
        case "Cargo (Rust包管理)": return t("Cargo (Rust包管理)", en: "Cargo (Rust Package Manager)", zhHant: "Cargo (Rust 套件管理)", ja: "Cargo (Rust パッケージ管理)", ko: "Cargo (Rust 패키지 관리자)", mt: "Cargo (Rust Package Manager)")
        case "Conda (Python环境)": return t("Conda (Python环境)", en: "Conda (Python Environment)", zhHant: "Conda (Python 環境)", ja: "Conda (Python 環境)", ko: "Conda (Python 환경)", mt: "Conda (Python Environment)")
        case "用户本地安装": return t("用户本地安装", en: "User-local Installs", zhHant: "使用者本機安裝", ja: "ユーザーのローカルインストール", ko: "사용자 로컬 설치", mt: "User-local Installs")
        case "用户缓存目录": return t("用户缓存目录", en: "User Cache Directory", zhHant: "使用者快取目錄", ja: "ユーザーキャッシュディレクトリ", ko: "사용자 캐시 디렉터리", mt: "User Cache Directory")
        case "Docker 配置": return t("Docker 配置", en: "Docker Config", zhHant: "Docker 配置", ja: "Docker 設定", ko: "Docker 설정", mt: "Docker Config")
        case "Android SDK 配置": return t("Android SDK 配置", en: "Android SDK Config", zhHant: "Android SDK 配置", ja: "Android SDK 設定", ko: "Android SDK 설정", mt: "Android SDK Config")
        case "IntelliJ IDEA 配置": return t("IntelliJ IDEA 配置", en: "IntelliJ IDEA Config", zhHant: "IntelliJ IDEA 配置", ja: "IntelliJ IDEA 設定", ko: "IntelliJ IDEA 설정", mt: "IntelliJ IDEA Config")
        case "ohpm 包管理": return t("ohpm 包管理", en: "ohpm Package Manager", zhHant: "ohpm 套件管理", ja: "ohpm パッケージ管理", ko: "ohpm 패키지 관리자", mt: "ohpm Package Manager")
        case "Hvigor 构建工具": return t("Hvigor 构建工具", en: "Hvigor Build Tool", zhHant: "Hvigor 建置工具", ja: "Hvigor ビルドツール", ko: "Hvigor 빌드 도구", mt: "Hvigor Build Tool")
        case "VS Code 配置": return t("VS Code 配置", en: "VS Code Config", zhHant: "VS Code 配置", ja: "VS Code 設定", ko: "VS Code 설정", mt: "VS Code Config")
        case "PM2 进程管理": return t("PM2 进程管理", en: "PM2 Process Manager", zhHant: "PM2 程序管理", ja: "PM2 プロセスマネージャー", ko: "PM2 프로세스 관리자", mt: "PM2 Process Manager")
        case "华为开发工具": return t("华为开发工具", en: "Huawei Developer Tools", zhHant: "華為開發工具", ja: "Huawei 開発ツール", ko: "Huawei 개발 도구", mt: "Huawei Developer Tools")
        case "搜狗输入法": return t("搜狗输入法", en: "Sogou Input Method", zhHant: "搜狗輸入法", ja: "Sogou 入力メソッド", ko: "Sogou 입력기", mt: "Sogou Input Method")
        case "下载器": return t("下载器", en: "Downloader", zhHant: "下載器", ja: "ダウンローダー", ko: "다운로더", mt: "Downloader")
        case "Chromium 快照": return t("Chromium 快照", en: "Chromium Snapshots", zhHant: "Chromium 快照", ja: "Chromium スナップショット", ko: "Chromium 스냅샷", mt: "Chromium Snapshots")
        case "智谱AI": return t("智谱AI", en: "Zhipu AI", zhHant: "智譜AI", ja: "Zhipu AI", ko: "Zhipu AI", mt: "Zhipu AI")
        case "讯飞星火": return t("讯飞星火", en: "iFlytek Spark", zhHant: "訊飛星火", ja: "iFlytek Spark", ko: "iFlytek Spark", mt: "iFlytek Spark")
        case "通义灵码": return t("通义灵码", en: "Tongyi Lingma", zhHant: "通義靈碼", ja: "Tongyi Lingma", ko: "Tongyi Lingma", mt: "Tongyi Lingma")
        case "阶跃星辰": return t("阶跃星辰", en: "StepFun", zhHant: "階躍星辰", ja: "StepFun", ko: "StepFun", mt: "StepFun")
        default:
            guard language == .english || language == .maltese else { return name }
            return englishDisplayNameFallback(name)
        }
    }

    private func englishDisplayNameFallback(_ name: String) -> String {
        var output = name
        let replacements = [
            ("包管理器", "Package Manager"),
            ("包管理", "Package Manager"),
            ("运行环境", "Runtime"),
            ("版本管理", "Version Manager"),
            ("工具链", "Toolchain"),
            ("语言环境", "Language Environment"),
            ("编程助手", "Coding Assistant"),
            ("AI 助手", "AI Assistant"),
            ("AI 编辑器", "AI Editor"),
            ("编辑器", "Editor"),
            ("开发者数据", "Developer Data"),
            ("开发工具包", "Development Kit"),
            ("开发工具", "Developer Tools"),
            ("构建工具", "Build Tool"),
            ("依赖管理", "Dependency Manager"),
            ("全局缓存", "Global Cache"),
            ("缓存", "Cache"),
            ("存储", "Store"),
            ("配置", "Config"),
            ("快照", "Snapshots"),
            ("容器", "Containers"),
            ("引擎", "Engine")
        ]
        for (from, to) in replacements {
            output = output.replacingOccurrences(of: from, with: to)
        }
        return output
    }

    func localizedAppDescription(_ desc: String, name: String = "") -> String {
        let n = name.isEmpty ? "" : name
        if desc.contains("npm 全局安装") { return t("npm 全局安装的 \(n) 包", en: "Globally installed npm package \(n)", zhHant: "npm 全域安裝的 \(n) 套件", ja: "グローバルにインストールされた npm パッケージ \(n)", ko: "전역 설치된 npm 패키지 \(n)", mt: "Globally installed npm package \(n)") }
        if desc.contains("pip 安装") { return t("pip 安装的 \(n) 包", en: "pip package \(n)", zhHant: "pip 安裝的 \(n) 套件", ja: "pip パッケージ \(n)", ko: "pip 패키지 \(n)", mt: "pip package \(n)") }
        if desc.contains("通过 Homebrew 安装") { return t("通过 Homebrew 安装的 \(n)", en: "\(n) installed by Homebrew", zhHant: "透過 Homebrew 安裝的 \(n)", ja: "Homebrew でインストールされた \(n)", ko: "Homebrew로 설치된 \(n)", mt: "\(n) installed by Homebrew") }
        if desc.contains("AI代码编辑器") { return t("AI 代码编辑器", en: "AI code editor", zhHant: "AI 程式碼編輯器", ja: "AI コードエディタ", ko: "AI 코드 에디터", mt: "AI code editor") }
        if desc.contains("AI代码补全") { return t("AI 代码补全工具", en: "AI code completion tool", zhHant: "AI 程式碼補全工具", ja: "AI コード補完ツール", ko: "AI 코드 자동완성 도구", mt: "AI code completion tool") }
        if desc.contains("AI终端") { return t("AI 终端", en: "AI terminal", zhHant: "AI 終端機", ja: "AI ターミナル", ko: "AI 터미널", mt: "AI terminal") }
        if desc.contains("AI大模型客户端") { return t("AI 大模型客户端", en: "AI model client", zhHant: "AI 大模型用戶端", ja: "AI モデルクライアント", ko: "AI 모델 클라이언트", mt: "AI model client") }
        if desc.contains("本地大模型运行环境") { return t("本地大模型运行环境", en: "Local model runtime", zhHant: "本機大模型執行環境", ja: "ローカルモデル実行環境", ko: "로컬 모델 런타임", mt: "Local model runtime") }
        if desc.contains("AI浏览器自动化") { return t("AI 浏览器自动化", en: "AI browser automation", zhHant: "AI 瀏覽器自動化", ja: "AI ブラウザ自動化", ko: "AI 브라우저 자동화", mt: "AI browser automation") }
        if desc.contains("AI技能平台") { return t("AI 技能平台", en: "AI skills platform", zhHant: "AI 技能平台", ja: "AI スキルプラットフォーム", ko: "AI 스킬 플랫폼", mt: "AI skills platform") }
        if desc.contains("MCP工具") { return t("MCP 工具", en: "MCP tool", zhHant: "MCP 工具", ja: "MCP ツール", ko: "MCP 도구", mt: "MCP tool") }
        if desc.contains("AI编程助手") { return t("AI 编程助手", en: "AI coding assistant", zhHant: "AI 編程助手", ja: "AIコーディングアシスタント", ko: "AI 코딩 도우미", mt: "AI coding assistant") }
        if desc.contains("AI助手") { return t("AI 助手", en: "AI assistant", zhHant: "AI 助手", ja: "AI アシスタント", ko: "AI 어시스턴트", mt: "AI assistant") }
        if desc.contains("命令行工具") { return t("命令行工具", en: "Command line tool", zhHant: "命令列工具", ja: "コマンドラインツール", ko: "명령줄 도구", mt: "Command line tool") }
        if desc.contains("容器化平台") { return t("容器化平台，包含镜像和容器数据", en: "Container platform with image and container data", zhHant: "容器化平台，包含映像與容器資料", ja: "イメージとコンテナデータを含むコンテナプラットフォーム", ko: "이미지 및 컨테이너 데이터를 포함한 컨테이너 플랫폼", mt: "Container platform with image and container data") }
        if desc.contains("编译缓存") { return t("编译缓存、派生数据和归档", en: "Build cache, derived data, and archives", zhHant: "編譯快取、衍生資料與封存", ja: "ビルドキャッシュ、派生データ、アーカイブ", ko: "빌드 캐시, 파생 데이터 및 아카이브", mt: "Build cache, derived data, and archives") }
        if desc.contains("开发工具包") { return t("开发工具包", en: "Development kit", zhHant: "開發工具包", ja: "開発キット", ko: "개발 키트", mt: "Development kit") }
        if desc.contains("构建工具") { return t("构建工具和缓存", en: "Build tool and cache", zhHant: "建置工具與快取", ja: "ビルドツールとキャッシュ", ko: "빌드 도구 및 캐시", mt: "Build tool and cache") }
        if desc.contains("编程语言和构建缓存") { return t("编程语言和构建缓存", en: "Programming language and build cache", zhHant: "程式語言與建置快取", ja: "プログラミング言語とビルドキャッシュ", ko: "프로그래밍 언어 및 빌드 캐시", mt: "Programming language and build cache") }
        if desc.contains("版本管理") { return t("多版本管理工具和缓存", en: "Version manager and cache", zhHant: "多版本管理工具與快取", ja: "バージョン管理ツールとキャッシュ", ko: "버전 관리자 및 캐시", mt: "Version manager and cache") }
        if desc.contains("用户目录") { return t("用户目录 \(n)", en: "User directory \(n)", zhHant: "使用者目錄 \(n)", ja: "ユーザーディレクトリ \(n)", ko: "사용자 디렉터리 \(n)", mt: "User directory \(n)") }
        if desc.contains("包管理") { return t("包管理工具", en: "Package management tool", zhHant: "套件管理工具", ja: "パッケージ管理ツール", ko: "패키지 관리 도구", mt: "Package management tool") }
        return desc
    }

    func localizedRiskDescription(_ desc: String, name: String = "") -> String {
        let n = name.isEmpty ? "" : name
        if desc.contains("卸载后依赖此包的Python项目将无法运行") { return t("卸载后依赖此包的 Python 项目将无法运行", en: "Python projects depending on this package may stop working after uninstall.", zhHant: "解除安裝後，依賴此套件的 Python 專案可能無法執行。", ja: "アンインストール後、このパッケージに依存する Python プロジェクトが動作しなくなる可能性があります。", ko: "제거 후 이 패키지에 의존하는 Python 프로젝트가 동작하지 않을 수 있습니다.", mt: "Python projects depending on this package may stop working after uninstall.") }
        if desc.contains("卸载后依赖此包的项目将无法运行") { return t("卸载后依赖此包的项目将无法运行", en: "Projects depending on this package may stop working after uninstall.", zhHant: "解除安裝後，依賴此套件的專案可能無法執行。", ja: "アンインストール後、このパッケージに依存するプロジェクトが動作しなくなる可能性があります。", ko: "제거 후 이 패키지에 의존하는 프로젝트가 동작하지 않을 수 있습니다.", mt: "Projects depending on this package may stop working after uninstall.") }
        if desc.contains("将无法运行") { return t("卸载后相关项目可能无法运行", en: "Related projects may stop working after uninstall.", zhHant: "解除安裝後相關專案可能無法執行。", ja: "アンインストール後、関連プロジェクトが動作しなくなる可能性があります。", ko: "제거 후 관련 프로젝트가 동작하지 않을 수 있습니다.", mt: "Related projects may stop working after uninstall.") }
        if desc.contains("将无法编译") { return t("卸载后相关项目可能无法编译", en: "Related projects may fail to compile after uninstall.", zhHant: "解除安裝後相關專案可能無法編譯。", ja: "アンインストール後、関連プロジェクトのコンパイルに失敗する可能性があります。", ko: "제거 후 관련 프로젝트 컴파일에 실패할 수 있습니다.", mt: "Related projects may fail to compile after uninstall.") }
        if desc.contains("需重新编译项目") { return t("清理后项目可能需要重新编译", en: "Projects may need to be rebuilt after cleanup.", zhHant: "清理後專案可能需要重新編譯。", ja: "クリーンアップ後、プロジェクトの再ビルドが必要になる場合があります。", ko: "정리 후 프로젝트를 다시 빌드해야 할 수 있습니다.", mt: "Projects may need to be rebuilt after cleanup.") }
        if desc.contains("需重新下载所有依赖") { return t("删除后需重新下载所有依赖", en: "All dependencies must be downloaded again after deletion.", zhHant: "刪除後需重新下載所有依賴。", ja: "削除後、すべての依存関係を再ダウンロードする必要があります。", ko: "삭제 후 모든 의존성을 다시 다운로드해야 합니다.", mt: "All dependencies must be downloaded again after deletion.") }
        if desc.contains("将丢失") { return t("删除后相关数据将丢失", en: "Related data will be lost after deletion.", zhHant: "刪除後相關資料將會遺失。", ja: "削除後、関連データは失われます。", ko: "삭제 후 관련 데이터가 손실됩니다.", mt: "Related data will be lost after deletion.") }
        if desc.contains("可安全清理") { return t("可安全清理，需要时会重新生成或下载", en: "Safe to clean; data can be regenerated or downloaded again when needed.", zhHant: "可安全清理，需要時會重新產生或下載。", ja: "安全にクリーンアップできます。必要に応じて再生成または再ダウンロードされます。", ko: "안전하게 정리할 수 있으며 필요 시 다시 생성되거나 다운로드됩니다.", mt: "Safe to clean; data can be regenerated or downloaded again when needed.") }
        if desc.contains("可安全卸载") { return t("可安全卸载，重新安装后需重新配置", en: "Safe to uninstall; configuration may be required after reinstall.", zhHant: "可安全解除安裝，重新安裝後需重新配置。", ja: "安全にアンインストールできます。再インストール後に再設定が必要な場合があります。", ko: "안전하게 제거할 수 있으며 재설치 후 재설정이 필요할 수 있습니다.", mt: "Safe to uninstall; configuration may be required after reinstall.") }
        if desc.contains("未知目录") { return t("未知目录，删除前请确认其用途", en: "Unknown directory. Confirm its purpose before deleting.", zhHant: "未知目錄，刪除前請確認用途。", ja: "不明なディレクトリです。削除前に用途を確認してください。", ko: "알 수 없는 디렉터리입니다. 삭제 전 용도를 확인하세요.", mt: "Unknown directory. Confirm its purpose before deleting.") }
        if desc.contains("将不可用") { return t("卸载后 \(n) 可能不可用", en: "\(n) may stop working after uninstall.", zhHant: "解除安裝後 \(n) 可能無法使用。", ja: "アンインストール後、\(n) が使用できなくなる可能性があります。", ko: "제거 후 \(n)이 동작하지 않을 수 있습니다.", mt: "\(n) may stop working after uninstall.") }
        if desc.contains("仅删除缓存") { return t("仅删除缓存，不影响书签、密码、历史记录。删除后网页首次加载会稍慢。", en: "Only cached data is removed. Bookmarks, passwords, and history stay intact. Initial page loads may be slightly slower afterward.", zhHant: "僅刪除快取，不影響書籤、密碼與歷史記錄。刪除後網頁首次載入可能稍慢。", ja: "キャッシュのみを削除します。ブックマーク、パスワード、履歴には影響しません。削除後は最初の読み込みがやや遅くなる場合があります。", ko: "캐시만 삭제합니다. 북마크, 비밀번호, 기록에는 영향이 없습니다. 이후 첫 페이지 로딩이 약간 느려질 수 있습니다.", mt: "Only cached data is removed. Bookmarks, passwords, and history stay intact. Initial page loads may be slightly slower afterward.") }
        if desc.contains("需重新登录") { return t("包含 IndexedDB 和 Local Storage，部分网站登录状态可能丢失，需重新登录。", en: "Includes IndexedDB and Local Storage. Some website sign-ins may be lost and require logging in again.", zhHant: "包含 IndexedDB 與 Local Storage，部分網站登入狀態可能遺失，需重新登入。", ja: "IndexedDB と Local Storage を含むため、一部サイトのログイン状態が失われ、再ログインが必要になる場合があります。", ko: "IndexedDB 및 Local Storage를 포함하므로 일부 사이트 로그인 상태가 사라져 다시 로그인해야 할 수 있습니다.", mt: "Includes IndexedDB and Local Storage. Some website sign-ins may be lost and require logging in again.") }
        if desc.contains("首次启动会稍慢") { return t("删除后首次启动会稍慢。", en: "The first launch after cleanup may be slightly slower.", zhHant: "刪除後首次啟動可能稍慢。", ja: "削除後の初回起動はやや遅くなる場合があります。", ko: "정리 후 첫 실행이 약간 느려질 수 있습니다.", mt: "The first launch after cleanup may be slightly slower.") }
        if desc.contains("会自动重建") { return t("删除后会自动重建，不影响正常使用。", en: "It will be rebuilt automatically after deletion and should not affect normal use.", zhHant: "刪除後會自動重建，不影響正常使用。", ja: "削除後は自動的に再構築され、通常の使用には影響しません。", ko: "삭제 후 자동으로 다시 생성되며 정상 사용에는 영향이 없습니다.", mt: "It will be rebuilt automatically after deletion and should not affect normal use.") }
        if desc.contains("下次") && desc.contains("会重新下载") { return t("删除后，下次使用时会重新下载。", en: "After deletion, the data will be downloaded again the next time it is needed.", zhHant: "刪除後，下次使用時會重新下載。", ja: "削除後、次回必要になった際に再ダウンロードされます。", ko: "삭제 후 필요할 때 다시 다운로드됩니다.", mt: "After deletion, the data will be downloaded again the next time it is needed.") }
        if desc.contains("不影响聊天记录") { return t("删除后不影响聊天记录。", en: "Deleting this will not affect chat history.", zhHant: "刪除後不影響聊天記錄。", ja: "削除してもチャット履歴には影響しません。", ko: "삭제해도 채팅 기록에는 영향이 없습니다.", mt: "Deleting this will not affect chat history.") }
        if desc.contains("不影响文档") { return t("删除后不影响文档。", en: "Deleting this will not affect documents.", zhHant: "刪除後不影響文件。", ja: "削除しても書類には影響しません。", ko: "삭제해도 문서에는 영향이 없습니다.", mt: "Deleting this will not affect documents.") }
        if desc.contains("无法回溯历史版本") { return t("删除后将无法回溯历史归档版本。", en: "After deletion, historical archived versions can no longer be restored.", zhHant: "刪除後將無法回溯歷史封存版本。", ja: "削除後、過去のアーカイブ版に戻せなくなります。", ko: "삭제 후 과거 아카이브 버전으로 되돌릴 수 없습니다.", mt: "After deletion, historical archived versions can no longer be restored.") }
        return desc
    }

    func localizedScanRule(_ rule: ScanRule) -> (name: String, category: String, app: String, riskDesc: String) {
        let category = localizedSubCategory(rule.category)
        let app: String
        switch rule.app {
        case "多个 Agent":
            app = t("多个 Agent", en: "Multiple Agents", zhHant: "多個 Agent", ja: "複数のAgent", ko: "여러 Agent", mt: "Multiple Agents")
        case "飞书/Lark":
            app = "Lark/Feishu"
        default:
            app = rule.app
        }

        let name: String
        switch rule.id {
        case "cache_browser_chrome": name = t("Chrome 浏览器缓存", en: "Chrome browser cache", zhHant: "Chrome 瀏覽器快取", ja: "Chrome ブラウザキャッシュ", ko: "Chrome 브라우저 캐시", mt: "Chrome browser cache")
        case "cache_browser_chrome_data": name = t("Chrome 用户数据缓存", en: "Chrome user data cache", zhHant: "Chrome 使用者資料快取", ja: "Chrome ユーザーデータキャッシュ", ko: "Chrome 사용자 데이터 캐시", mt: "Chrome user data cache")
        case "cache_lark": name = t("飞书缓存", en: "Lark cache", zhHant: "飛書快取", ja: "Lark キャッシュ", ko: "Lark 캐시", mt: "Lark cache")
        case "data_lark_deployments": name = t("飞书更新包", en: "Lark update packages", zhHant: "飛書更新包", ja: "Lark 更新パッケージ", ko: "Lark 업데이트 패키지", mt: "Lark update packages")
        case "data_lark_aha": name = t("飞书运行时数据", en: "Lark runtime data", zhHant: "飛書執行時資料", ja: "Lark ランタイムデータ", ko: "Lark 런타임 데이터", mt: "Lark runtime data")
        case "cache_claude_vm": name = t("Claude Code 虚拟机沙箱", en: "Claude Code VM sandbox", zhHant: "Claude Code 虛擬機沙箱", ja: "Claude Code VM サンドボックス", ko: "Claude Code VM 샌드박스", mt: "Claude Code VM sandbox")
        case "cache_claude": name = t("Claude Code 缓存", en: "Claude Code cache", zhHant: "Claude Code 快取", ja: "Claude Code キャッシュ", ko: "Claude Code 캐시", mt: "Claude Code cache")
        case "cache_photo_analysis": name = t("照片分析索引缓存", en: "Photos analysis index cache", zhHant: "照片分析索引快取", ja: "写真分析インデックスキャッシュ", ko: "사진 분석 인덱스 캐시", mt: "Photos analysis index cache")
        case "cache_updater_packages": name = t("Agent 更新包缓存", en: "Agent updater package cache", zhHant: "Agent 更新包快取", ja: "Agent 更新パッケージキャッシュ", ko: "Agent 업데이트 패키지 캐시", mt: "Agent updater package cache")
        case "log_trae": name = t("Trae CN 日志", en: "Trae CN logs", zhHant: "Trae CN 日誌", ja: "Trae CN ログ", ko: "Trae CN 로그", mt: "Trae CN logs")
        case "log_codebuddy": name = t("CodeBuddy CN 日志", en: "CodeBuddy CN logs", zhHant: "CodeBuddy CN 日誌", ja: "CodeBuddy CN ログ", ko: "CodeBuddy CN 로그", mt: "CodeBuddy CN logs")
        case "cache_trae": name = t("Trae CN 缓存", en: "Trae CN cache", zhHant: "Trae CN 快取", ja: "Trae CN キャッシュ", ko: "Trae CN 캐시", mt: "Trae CN cache")
        case "cache_codebuddy": name = t("CodeBuddy CN 缓存", en: "CodeBuddy CN cache", zhHant: "CodeBuddy CN 快取", ja: "CodeBuddy CN キャッシュ", ko: "CodeBuddy CN 캐시", mt: "CodeBuddy CN cache")
        case "cache_electron": name = t("Electron 框架缓存", en: "Electron framework cache", zhHant: "Electron 框架快取", ja: "Electron フレームワークキャッシュ", ko: "Electron 프레임워크 캐시", mt: "Electron framework cache")
        case "cache_pip": name = t("pip 缓存", en: "pip cache", zhHant: "pip 快取", ja: "pip キャッシュ", ko: "pip 캐시", mt: "pip cache")
        case "cache_homebrew": name = t("Homebrew 下载缓存", en: "Homebrew download cache", zhHant: "Homebrew 下載快取", ja: "Homebrew ダウンロードキャッシュ", ko: "Homebrew 다운로드 캐시", mt: "Homebrew download cache")
        case "cache_npm": name = t("npm 缓存", en: "npm cache", zhHant: "npm 快取", ja: "npm キャッシュ", ko: "npm 캐시", mt: "npm cache")
        case "cache_pnpm": name = t("pnpm 缓存", en: "pnpm cache", zhHant: "pnpm 快取", ja: "pnpm キャッシュ", ko: "pnpm 캐시", mt: "pnpm cache")
        case "cache_quark": name = t("夸克浏览器缓存", en: "Quark browser cache", zhHant: "夸克瀏覽器快取", ja: "Quark ブラウザキャッシュ", ko: "Quark 브라우저 캐시", mt: "Quark browser cache")
        case "cache_wechat": name = t("微信缓存", en: "WeChat cache", zhHant: "微信快取", ja: "WeChat キャッシュ", ko: "WeChat 캐시", mt: "WeChat cache")
        case "cache_qq": name = t("QQ 缓存", en: "QQ cache", zhHant: "QQ 快取", ja: "QQ キャッシュ", ko: "QQ 캐시", mt: "QQ cache")
        case "cache_wps": name = t("WPS 缓存", en: "WPS cache", zhHant: "WPS 快取", ja: "WPS キャッシュ", ko: "WPS 캐시", mt: "WPS cache")
        case "system_logs": name = t("系统日志", en: "System logs", zhHant: "系統日誌", ja: "システムログ", ko: "시스템 로그", mt: "System logs")
        case "cache_geoservices": name = t("地理位置服务缓存", en: "Location services cache", zhHant: "定位服務快取", ja: "位置情報サービスキャッシュ", ko: "위치 서비스 캐시", mt: "Location services cache")
        case "cache_huawei": name = t("华为相关缓存", en: "Huawei-related cache", zhHant: "華為相關快取", ja: "Huawei 関連キャッシュ", ko: "Huawei 관련 캐시", mt: "Huawei-related cache")
        case "cache_hap_installer": name = t("HAP 安装器缓存", en: "HAP installer cache", zhHant: "HAP 安裝器快取", ja: "HAP インストーラキャッシュ", ko: "HAP 설치 프로그램 캐시", mt: "HAP installer cache")
        case "data_trae_solo": name = t("Trae SOLO 数据", en: "Trae SOLO data", zhHant: "Trae SOLO 資料", ja: "Trae SOLO データ", ko: "Trae SOLO 데이터", mt: "Trae SOLO data")
        case "cache_doubao": name = t("豆包缓存", en: "Doubao cache", zhHant: "豆包快取", ja: "Doubao キャッシュ", ko: "Doubao 캐시", mt: "Doubao cache")
        case "cache_qianwen": name = t("通义千问缓存", en: "Qianwen cache", zhHant: "通義千問快取", ja: "Qianwen キャッシュ", ko: "Qianwen 캐시", mt: "Qianwen cache")
        case "cache_crebee": name = t("Crebee 缓存", en: "Crebee cache", zhHant: "Crebee 快取", ja: "Crebee キャッシュ", ko: "Crebee 캐시", mt: "Crebee cache")
        case "cache_codebuddy_ext": name = t("CodeBuddy 扩展缓存", en: "CodeBuddy extension cache", zhHant: "CodeBuddy 擴充快取", ja: "CodeBuddy 拡張キャッシュ", ko: "CodeBuddy 확장 캐시", mt: "CodeBuddy extension cache")
        case "cache_codearts": name = t("CodeArts Agent 缓存", en: "CodeArts Agent cache", zhHant: "CodeArts Agent 快取", ja: "CodeArts Agent キャッシュ", ko: "CodeArts Agent 캐시", mt: "CodeArts Agent cache")
        case "cache_master_desktop": name = t("Master Desktop 缓存", en: "Master Desktop cache", zhHant: "Master Desktop 快取", ja: "Master Desktop キャッシュ", ko: "Master Desktop 캐시", mt: "Master Desktop cache")
        case "cache_qclaw": name = t("QClaw 缓存", en: "QClaw cache", zhHant: "QClaw 快取", ja: "QClaw キャッシュ", ko: "QClaw 캐시", mt: "QClaw cache")
        case "cache_dingtalk": name = t("钉钉缓存", en: "DingTalk cache", zhHant: "釘釘快取", ja: "DingTalk キャッシュ", ko: "DingTalk 캐시", mt: "DingTalk cache")
        case "cache_xmind": name = t("XMind 缓存", en: "XMind cache", zhHant: "XMind 快取", ja: "XMind キャッシュ", ko: "XMind 캐시", mt: "XMind cache")
        case "cache_yarn": name = t("Yarn 缓存", en: "Yarn cache", zhHant: "Yarn 快取", ja: "Yarn キャッシュ", ko: "Yarn 캐시", mt: "Yarn cache")
        case "cache_cargo": name = t("Cargo 缓存", en: "Cargo cache", zhHant: "Cargo 快取", ja: "Cargo キャッシュ", ko: "Cargo 캐시", mt: "Cargo cache")
        case "cache_gradle": name = t("Gradle 缓存", en: "Gradle cache", zhHant: "Gradle 快取", ja: "Gradle キャッシュ", ko: "Gradle 캐시", mt: "Gradle cache")
        case "cache_maven": name = t("Maven 缓存", en: "Maven cache", zhHant: "Maven 快取", ja: "Maven キャッシュ", ko: "Maven 캐시", mt: "Maven cache")
        case "cache_cocoapods": name = t("CocoaPods 缓存", en: "CocoaPods cache", zhHant: "CocoaPods 快取", ja: "CocoaPods キャッシュ", ko: "CocoaPods 캐시", mt: "CocoaPods cache")
        case "cache_go_build": name = t("Go 构建缓存", en: "Go build cache", zhHant: "Go 建置快取", ja: "Go ビルドキャッシュ", ko: "Go 빌드 캐시", mt: "Go build cache")
        case "cache_docker": name = t("Docker 镜像和容器", en: "Docker images and containers", zhHant: "Docker 映像與容器", ja: "Docker イメージとコンテナ", ko: "Docker 이미지 및 컨테이너", mt: "Docker images and containers")
        case "cache_xcode_derived": name = t("Xcode DerivedData", en: "Xcode DerivedData", zhHant: "Xcode DerivedData", ja: "Xcode DerivedData", ko: "Xcode DerivedData", mt: "Xcode DerivedData")
        case "cache_xcode_archives": name = t("Xcode Archives", en: "Xcode archives", zhHant: "Xcode 封存", ja: "Xcode アーカイブ", ko: "Xcode 아카이브", mt: "Xcode archives")
        case "cache_android": name = t("Android SDK 缓存", en: "Android SDK cache", zhHant: "Android SDK 快取", ja: "Android SDK キャッシュ", ko: "Android SDK 캐시", mt: "Android SDK cache")
        case "cache_unity": name = t("Unity 缓存", en: "Unity cache", zhHant: "Unity 快取", ja: "Unity キャッシュ", ko: "Unity 캐시", mt: "Unity cache")
        default: name = rule.name
        }

        let riskDesc = localizedRiskDescription(rule.riskDesc, name: app)
        return (name, category, app, riskDesc)
    }

    func localizedConfidence(_ level: String) -> String {
        switch level {
        case "高": return highConf
        case "中": return medConf
        case "低": return lowConf
        default: return level
        }
    }

    var langToggleText: String {
        switch language {
        case .simplifiedChinese: return "EN"
        case .english: return "中文"
        case .traditionalChinese: return "EN"
        case .japanese: return "EN"
        case .korean: return "EN"
        case .maltese: return "中文"
        }
    }
}

extension Localizer {
    var settingsTitle: String { t("设置", en: "Settings", zhHant: "設定", ja: "設定", ko: "설정", mt: "Settings") }
    var aiSettings: String { t("AI 设置", en: "AI Settings", zhHant: "AI 設定", ja: "AI 設定", ko: "AI 설정", mt: "AI Settings") }
    var aiSettingsDesc: String { t("使用本地样例和规则分析目录结构，不需要登录或外部凭据。", en: "Uses local samples and rule-based analysis. No sign-in or external credentials are required.", zhHant: "使用本地樣例和規則分析目錄結構，不需要登入或外部憑據。", ja: "ローカルサンプルとルールベース分析を使用します。サインインや外部認証情報は不要です。", ko: "로컬 샘플과 규칙 기반 분석을 사용합니다. 로그인이나 외부 자격 증명이 필요하지 않습니다.", mt: "Uses local samples and rule-based analysis. No sign-in or external credentials are required.") }
    var appReviewDemoMode: String { t("本地 AI 分析", en: "Local AI Analysis", zhHant: "本地 AI 分析", ja: "ローカルAI分析", ko: "로컬 AI 분석", mt: "Local AI Analysis") }
    var appReviewDemoModeDesc: String { t("所有分析都在本机使用样例数据和规则完成，不连接第三方模型服务。", en: "Analysis runs locally with sample data and rules, without connecting to third-party model services.", zhHant: "所有分析都在本機使用樣例資料和規則完成，不連接第三方模型服務。", ja: "分析はサンプルデータとルールでローカル実行され、第三者モデルサービスには接続しません。", ko: "분석은 샘플 데이터와 규칙으로 로컬에서 실행되며 타사 모델 서비스에 연결하지 않습니다.", mt: "Analysis runs locally with sample data and rules, without connecting to third-party model services.") }

    var featureToggles: String { t("功能开关", en: "Feature Toggles", zhHant: "功能開關", ja: "機能切替", ko: "기능 토글", mt: "Feature Toggles") }
    var labSettingsTitle: String { t("实验室说明", en: "Lab Overview", zhHant: "實驗室說明", ja: "ラボ概要", ko: "실험실 안내", mt: "Lab Overview") }
    var labSettingsDesc: String { t("实验室中的功能处于持续迭代阶段，交互、能力范围和入口位置都可能根据反馈进行调整。", en: "Features in Lab are still evolving. Their interaction model, capability scope, and entry points may change based on feedback.", zhHant: "實驗室中的功能仍在持續迭代，互動方式、能力範圍與入口位置都可能依據回饋調整。", ja: "ラボ内の機能は継続的に進化中です。操作方法、対応範囲、導線はフィードバックに応じて変更される場合があります。", ko: "실험실 기능은 계속 개선 중입니다. 상호작용 방식, 기능 범위, 진입 경로는 피드백에 따라 바뀔 수 있습니다.", mt: "Features in Lab are still evolving. Their interaction model, capability scope, and entry points may change based on feedback.") }
    var labSettingsNotice: String { t("这些功能可能随时调整、下线，或移动到其他入口。", en: "These features may be adjusted, removed, or moved to another entry point at any time.", zhHant: "這些功能可能隨時調整、下線，或移動到其他入口。", ja: "これらの機能は、随時調整・終了、または別の導線へ移動される場合があります。", ko: "이 기능들은 언제든 조정, 제거 또는 다른 진입 경로로 이동될 수 있습니다.", mt: "These features may be adjusted, removed, or moved to another entry point at any time.") }
    var labFeaturesOverview: String { t("当前实验室包含以下 5 个功能：", en: "The current Lab includes these 5 features:", zhHant: "目前實驗室包含以下 5 個功能：", ja: "現在のラボには次の5機能が含まれます。", ko: "현재 실험실에는 다음 5개 기능이 포함됩니다.", mt: "The current Lab includes these 5 features:") }
    var labFeatureAgentCenterDesc: String { t("统一查看 Agent 接入状态、Hook 安装情况、审批记录和会话流转。", en: "A central place to review agent integrations, hook installation status, approvals, and session flows.", zhHant: "統一查看 Agent 接入狀態、Hook 安裝情況、審批記錄與會話流轉。", ja: "Agent連携、Hook導入状況、承認履歴、セッション遷移をまとめて確認できます。", ko: "Agent 연동 상태, Hook 설치 현황, 승인 기록, 세션 흐름을 한곳에서 확인합니다.", mt: "A central place to review agent integrations, hook installation status, approvals, and session flows.") }
    var labFeatureCleanerDesc: String { t("扫描缓存、日志、更新包和其它可清理数据，帮助释放磁盘空间。", en: "Scans caches, logs, updater packages, and other removable data to help free disk space.", zhHant: "掃描快取、日誌、更新包與其它可清理資料，協助釋放磁碟空間。", ja: "キャッシュ、ログ、更新パッケージなどをスキャンし、空き容量の確保を支援します。", ko: "캐시, 로그, 업데이트 패키지 등 정리 가능한 데이터를 스캔해 디스크 공간 확보를 돕습니다.", mt: "Scans caches, logs, updater packages, and other removable data to help free disk space.") }
    var labFeatureAppDesc: String { t("管理已安装应用，并提供卸载、重置或缓存清理等实验性操作。", en: "Manages installed apps and offers experimental actions such as uninstall, reset, or cache cleanup.", zhHant: "管理已安裝應用，並提供解除安裝、重置或快取清理等實驗性操作。", ja: "インストール済みアプリを管理し、アンインストール、リセット、キャッシュ整理などの実験的操作を提供します。", ko: "설치된 앱을 관리하고 제거, 초기화, 캐시 정리 같은 실험적 작업을 제공합니다.", mt: "Manages installed apps and offers experimental actions such as uninstall, reset, or cache cleanup.") }
    var labFeatureDependencyDesc: String { t("识别开发环境中的依赖和工具链，辅助做清理、重置与风险判断。", en: "Identifies development dependencies and toolchains to support cleanup, reset, and risk assessment.", zhHant: "識別開發環境中的依賴與工具鏈，輔助進行清理、重置與風險判斷。", ja: "開発環境の依存関係やツールチェーンを識別し、整理・リセット・リスク判断を支援します。", ko: "개발 환경의 의존성과 툴체인을 식별해 정리, 초기화, 위험 판단을 돕습니다.", mt: "Identifies development dependencies and toolchains to support cleanup, reset, and risk assessment.") }
    var labFeatureOtherDesc: String { t("集中管理命令行工具和零散组件，适合处理不属于标准应用的数据目录。", en: "Manages CLI tools and miscellaneous components that do not fit neatly into standard app categories.", zhHant: "集中管理命令列工具與零散元件，適合處理不屬於標準應用分類的資料目錄。", ja: "CLIツールや雑多なコンポーネントをまとめて管理し、標準的なアプリ分類に入らないデータを扱えます。", ko: "CLI 도구와 기타 구성요소를 관리하며 일반 앱 분류에 들어가지 않는 데이터 디렉터리를 다룹니다.", mt: "Manages CLI tools and miscellaneous components that do not fit neatly into standard app categories.") }
    var labFeatureMigrationDesc: String { t("检查应用和组件对 Apple Silicon 的适配情况，帮助识别 Rosetta 依赖与架构问题。", en: "Checks Apple Silicon compatibility to help identify Rosetta dependencies and architecture issues.", zhHant: "檢查應用與元件對 Apple Silicon 的適配情況，協助識別 Rosetta 依賴與架構問題。", ja: "Apple Silicon への対応状況を確認し、Rosetta依存やアーキテクチャ問題の特定を支援します。", ko: "Apple Silicon 호환성을 점검해 Rosetta 의존성과 아키텍처 문제를 식별합니다.", mt: "Checks Apple Silicon compatibility to help identify Rosetta dependencies and architecture issues.") }
    var menuBarMonitor: String { t("菜单栏监控", en: "Menu Bar Monitor", zhHant: "選單欄監控", ja: "メニューバーモニター", ko: "메뉴 막대 모니터", mt: "Menu Bar Monitor") }
    var menuBarMonitorDesc: String { t("在菜单栏显示系统资源监控", en: "Show system resource monitoring in the menu bar", zhHant: "在選單欄顯示系統資源監控", ja: "メニューバーにシステムリソースモニタリングを表示", ko: "메뉴 막대에 시스템 리소스 모니터링 표시", mt: "Show system resource monitoring in the menu bar") }
    var sensorMonitor: String { t("设备监控", en: "Device Monitor", zhHant: "裝置監控", ja: "デバイスモニター", ko: "장치 모니터", mt: "Device Monitor") }
    var sensorMonitorDesc: String { t("监控摄像头和麦克风调用", en: "Monitor camera and microphone usage", zhHant: "監控攝像頭和麥克風呼叫", ja: "カメラとマイクの使用をモニタリング", ko: "카메라 및 마이크 사용 모니터링", mt: "Monitor camera and microphone usage") }
    var operationMonitor: String { t("操作记录", en: "Operation Monitor", zhHant: "操作記錄", ja: "操作記録", ko: "작업 기록", mt: "Operation Monitor") }
    var operationMonitorDesc: String { t("监控 AI Agent 的文件操作", en: "Monitor AI Agent file operations", zhHant: "監控 AI Agent 的檔案操作", ja: "AI Agentのファイル操作をモニタリング", ko: "AI Agent 파일 작업 모니터링", mt: "Monitor AI Agent file operations") }

    var monitorSettings: String { t("监控设置", en: "Monitor Settings", zhHant: "監控設定", ja: "モニター設定", ko: "모니터 설정", mt: "Monitor Settings") }
    var storageAlertThreshold: String { t("存储警告阈值", en: "Storage Alert Threshold", zhHant: "儲存警告閾值", ja: "ストレージ警告しきい値", ko: "저장소 경고 임계값", mt: "Storage Alert Threshold") }
    var trashInsteadOfDelete: String { t("使用回收站", en: "Use Trash", zhHant: "使用回收站", ja: "ゴミ箱を使用", ko: "휴지통 사용", mt: "Use Trash") }
    var trashInsteadOfDeleteDesc: String { t("删除文件时移入回收站而非直接删除", en: "Move files to Trash instead of permanent delete", zhHant: "刪除檔案時移入回收站而非直接刪除", ja: "ファイルを完全削除ではなくゴミ箱に移動", ko: "영구 삭제 대신 휴지통으로 파일 이동", mt: "Move files to Trash instead of permanent delete") }
    var maxOperationRecords: String { t("操作记录保留时间", en: "Operation Record Retention", zhHant: "操作記錄保留時間", ja: "操作記録の保持時間", ko: "작업 기록 보관 시간", mt: "Operation Record Retention") }
    var customHours: String { t("自定义小时", en: "Custom Hours", zhHant: "自訂小時", ja: "カスタム時間", ko: "사용자 지정 시간", mt: "Custom Hours") }
    var retentionHoursHint: String { t("最多 360 小时，超出会自动限制", en: "Up to 360 hours; larger values are limited automatically", zhHant: "最多 360 小時，超出會自動限制", ja: "最大360時間、超過分は自動制限", ko: "최대 360시간, 초과 값은 자동 제한됨", mt: "Up to 360 hours; larger values are limited automatically") }
    var hoursUnit: String { t("小时", en: "h", zhHant: "小時", ja: "時間", ko: "시간", mt: "h") }

    var versionUpdate: String { t("版本与更新", en: "Version & Updates", zhHant: "版本與更新", ja: "バージョンと更新", ko: "버전 및 업데이트", mt: "Version & Updates") }
    var currentVersion: String { t("当前版本", en: "Current Version", zhHant: "當前版本", ja: "現在のバージョン", ko: "현재 버전", mt: "Current Version") }
    var checkUpdate: String { t("检查更新", en: "Check Update", zhHant: "檢查更新", ja: "アップデートを確認", ko: "업데이트 확인", mt: "Check Update") }
    var downloadingUpdate: String { t("正在检查更新...", en: "Checking for updates...", zhHant: "正在檢查更新...", ja: "アップデートを確認中...", ko: "업데이트 확인 중...", mt: "Checking for updates...") }
    var newVersionAvailable: String { t("发现新版本 v", en: "New version available v", zhHant: "發現新版本 v", ja: "新バージョンがあります v", ko: "새 버전 사용 가능 v", mt: "New version available v") }
    var downloadUpdate: String { t("下载更新", en: "Download Update", zhHant: "下載更新", ja: "アップデートをダウンロード", ko: "업데이트 다운로드", mt: "Download Update") }

    var cancel: String { t("取消", en: "Cancel", zhHant: "取消", ja: "キャンセル", ko: "취소", mt: "Cancel") }
    var save: String { t("保存设置", en: "Save Settings", zhHant: "儲存設定", ja: "設定を保存", ko: "설정 저장", mt: "Save Settings") }

    var languageLabel: String { t("语言", en: "Language", zhHant: "語言", ja: "言語", ko: "언어", mt: "Language") }

    var macCleanerTitle: String { t("Mac 清理", en: "Mac Cleaner", zhHant: "Mac 清理", ja: "Mac クリーナー", ko: "Mac 클리너", mt: "Mac Cleaner") }
    var macCleanerSubtitle: String { t("扫描并清理存储空间", en: "Scan and clean up storage space", zhHant: "掃描並清理儲存空間", ja: "ストレージをスキャンしてクリーンアップ", ko: "저장 공간 스캔 및 정리", mt: "Scan and clean up storage space") }
    var localScan: String { t("本地扫描", en: "Local Scan", zhHant: "本地掃描", ja: "ローカルスキャン", ko: "로컬 스캔", mt: "Local Scan") }
    var aiScan: String { t("AI 扫描", en: "AI Scan", zhHant: "AI 掃描", ja: "AIスキャン", ko: "AI 스캔", mt: "AI Scan") }
    var enhancedScan: String { t("增强扫描", en: "Enhanced Scan", zhHant: "增強掃描", ja: "拡張スキャン", ko: "향상된 스캔", mt: "Enhanced Scan") }
    var diskSpace: String { t("磁盘空间", en: "Disk Space", zhHant: "磁碟空間", ja: "ディスク容量", ko: "디스크 공간", mt: "Disk Space") }
    var used: String { t("已使用", en: "Used", zhHant: "已使用", ja: "使用済み", ko: "사용됨", mt: "Used") }
    var scanning: String { t("正在扫描存储空间...", en: "Scanning storage space...", zhHant: "正在掃描儲存空間...", ja: "ストレージをスキャン中...", ko: "저장 공간 스캔 중...", mt: "Scanning storage space...") }
    var scanningSubtitle: String { t("请稍候，正在分析可清理的文件", en: "Please wait, analyzing cleanable files", zhHant: "請稍候，正在分析可清理的檔案", ja: "お待ちください、クリーンアップ可能なファイルを分析中", ko: "잠시만 기다려 주세요, 정리 가능한 파일 분석 중", mt: "Please wait, analyzing cleanable files") }
    var searchFiles: String { t("搜索文件...", en: "Search files...", zhHant: "搜尋檔案...", ja: "ファイルを検索...", ko: "파일 검색...", mt: "Search files...") }
    var allCategories: String { t("全部分类", en: "All Categories", zhHant: "全部分類", ja: "すべてのカテゴリ", ko: "모든 카테고리", mt: "All Categories") }
    var allApps: String { t("全部应用", en: "All Apps", zhHant: "全部應用", ja: "すべてのアプリ", ko: "모든 앱", mt: "All Apps") }
    var riskLabel: String { t("风险", en: "Risk", zhHant: "風險", ja: "リスク", ko: "위험", mt: "Risk") }
    var smartClean: String { t("智能清理", en: "Smart Clean", zhHant: "智慧清理", ja: "スマートクリーン", ko: "스마트 정리", mt: "Smart Clean") }
    var selectAll: String { t("全选", en: "Select All", zhHant: "全選", ja: "すべて選択", ko: "전체 선택", mt: "Select All") }
    var safeOnly: String { t("仅安全", en: "Safe Only", zhHant: "僅安全", ja: "安全のみ", ko: "안전만", mt: "Safe Only") }
    var cancelSelection: String { t("取消选择", en: "Deselect", zhHant: "取消選擇", ja: "選択解除", ko: "선택 해제", mt: "Deselect") }
    var ignoreSelected: String { t("忽略选中", en: "Ignore Selected", zhHant: "忽略選中", ja: "選択を無視", ko: "선택 무시", mt: "Ignore Selected") }
    var deleteSelected: String { t("删除选中", en: "Delete Selected", zhHant: "刪除選中", ja: "選択を削除", ko: "선택 삭제", mt: "Delete Selected") }
    var noMatches: String { t("当前筛选条件下没有匹配项", en: "No matches under current filters", zhHant: "當前篩選條件下沒有匹配項", ja: "現在のフィルター条件に一致する項目がありません", ko: "현재 필터 조건에 일치하는 항목이 없습니다", mt: "No matches under current filters") }
    var clearRiskFilter: String { t("清除风险筛选", en: "Clear risk filter", zhHant: "清除風險篩選", ja: "リスクフィルターをクリア", ko: "위험 필터 지우기", mt: "Clear risk filter") }
    var clearCategoryFilter: String { t("清除分类筛选", en: "Clear category filter", zhHant: "清除分類篩選", ja: "カテゴリフィルターをクリア", ko: "카테고리 필터 지우기", mt: "Clear category filter") }
    var clearSearch: String { t("清除搜索", en: "Clear search", zhHant: "清除搜尋", ja: "検索をクリア", ko: "검색 지우기", mt: "Clear search") }
    var cleanComplete: String { t("🎉 清理完成", en: "🎉 Clean Complete", zhHant: "🎉 清理完成", ja: "🎉 クリーンアップ完了", ko: "🎉 정리 완료", mt: "🎉 Clean Complete") }
    var cleanCompleteMsg: String { t("本次清理释放了", en: "This cleanup freed up", zhHant: "本次清理釋放了", ja: "今回のクリーンアップで解放しました", ko: "이번 정리로 확보됨", mt: "This cleanup freed up") }
    var confirmDelete: String { t("确认删除", en: "Confirm Delete", zhHant: "確認刪除", ja: "削除の確認", ko: "삭제 확인", mt: "Confirm Delete") }
    var deleteBtn: String { t("删除", en: "Delete", zhHant: "刪除", ja: "削除", ko: "삭제", mt: "Delete") }
    var ok: String { t("确定", en: "OK", zhHant: "確定", ja: "OK", ko: "확인", mt: "OK") }

    var storageAnalysisTitle: String { t("存储分析", en: "Storage Analysis", zhHant: "儲存分析", ja: "ストレージ分析", ko: "저장소 분석", mt: "Storage Analysis") }
    var storageAnalysisSubtitle: String { t("存储空间分析与AI建议", en: "Storage analysis with AI recommendations", zhHant: "儲存空間分析與AI建議", ja: "ストレージ分析とAIレコメンデーション", ko: "저장 공간 분석 및 AI 추천", mt: "Storage analysis with AI recommendations") }
    var startScan: String { t("开始扫描", en: "Start Scan", zhHant: "開始掃描", ja: "スキャン開始", ko: "스캔 시작", mt: "Start Scan") }
    var aiAnalysis: String { t("AI 分析", en: "AI Analysis", zhHant: "AI 分析", ja: "AI分析", ko: "AI 분석", mt: "AI Analysis") }
    var aiAnalysisResult: String { t("AI 分析结果", en: "AI Analysis Result", zhHant: "AI 分析結果", ja: "AI分析結果", ko: "AI 분석 결과", mt: "AI Analysis Result") }
    var storageCategories: String { t("存储分类", en: "Storage Categories", zhHant: "儲存分類", ja: "ストレージカテゴリ", ko: "저장소 카테고리", mt: "Storage Categories") }
    var usedLabel: String { t("已使用", en: "Used", zhHant: "已使用", ja: "使用済み", ko: "사용됨", mt: "Used") }
    var noLargeFiles: String { t("无大文件（>1MB）", en: "No large files (>1MB)", zhHant: "無大檔案（>1MB）", ja: "大きなファイルなし（>1MB）", ko: "큰 파일 없음（>1MB）", mt: "No large files (>1MB)") }
    var selectCatView: String { t("选择左侧分类查看文件列表", en: "Select a category on the left to view files", zhHant: "選擇左側分類檢視檔案列表", ja: "左側のカテゴリを選択してファイル一覧を表示", ko: "왼쪽 카테고리를 선택하여 파일 목록 보기", mt: "Select a category on the left to view files") }

    var opCreate: String { t("创建", en: "Create", zhHant: "建立", ja: "作成", ko: "생성", mt: "Create") }
    var opModify: String { t("修改", en: "Modify", zhHant: "修改", ja: "変更", ko: "수정", mt: "Modify") }
    var opDelete: String { t("删除", en: "Delete", zhHant: "刪除", ja: "削除", ko: "삭제", mt: "Delete") }
    var opMove: String { t("移动", en: "Move", zhHant: "移動", ja: "移動", ko: "이동", mt: "Move") }
    var opRename: String { t("重命名", en: "Rename", zhHant: "重新命名", ja: "名前変更", ko: "이름 변경", mt: "Rename") }
    var opRead: String { t("读取", en: "Read", zhHant: "讀取", ja: "読み取り", ko: "읽기", mt: "Read") }

    var riskSafe: String { t("安全", en: "Safe", zhHant: "安全", ja: "安全", ko: "안전", mt: "Safe") }
    var riskCaution: String { t("注意", en: "Caution", zhHant: "注意", ja: "注意", ko: "주의", mt: "Caution") }
    var riskDangerous: String { t("危险", en: "Dangerous", zhHant: "危險", ja: "危険", ko: "위험", mt: "Dangerous") }

    var sourceAI: String { t("AI", en: "AI", zhHant: "AI", ja: "AI", ko: "AI", mt: "AI") }
    var sourceLocal: String { t("本地", en: "Local", zhHant: "本地", ja: "ローカル", ko: "로컬", mt: "Local") }

    var typeApp: String { t("应用", en: "Apps", zhHant: "應用", ja: "アプリ", ko: "앱", mt: "Apps") }
    var typeDependency: String { t("依赖", en: "Dependencies", zhHant: "依賴", ja: "依存関係", ko: "의존성", mt: "Dependencies") }
    var typeOther: String { t("其它", en: "Other Tools", zhHant: "其它", ja: "その他", ko: "기타", mt: "Other Tools") }

    var timeAll: String { t("全部", en: "All", zhHant: "全部", ja: "すべて", ko: "전체", mt: "All") }
    var timeToday: String { t("今天", en: "Today", zhHant: "今天", ja: "今日", ko: "오늘", mt: "Today") }
    var time1h: String { t("1小时", en: "1 Hour", zhHant: "1小時", ja: "1時間", ko: "1시간", mt: "1 Hour") }
    var time6h: String { t("6小时", en: "6 Hours", zhHant: "6小時", ja: "6時間", ko: "6시간", mt: "6 Hours") }
    var time24h: String { t("24小时", en: "24 Hours", zhHant: "24小時", ja: "24時間", ko: "24시간", mt: "24 Hours") }
    var time7d: String { t("7天", en: "7 Days", zhHant: "7天", ja: "7日間", ko: "7일", mt: "7 Days") }

    var hardwareMonitor: String { t("硬件监控", en: "Hardware Monitor", zhHant: "硬體監控", ja: "ハードウェアモニター", ko: "하드웨어 모니터", mt: "Hardware Monitor") }
    var diskSpaceLabel: String { t("磁盘空间", en: "Disk Space", zhHant: "磁碟空間", ja: "ディスク容量", ko: "디스크 공간", mt: "Disk Space") }
    var usedPct: String { t("已使用", en: "Used", zhHant: "已使用", ja: "使用済み", ko: "사용됨", mt: "Used") }
    var totalCapacity: String { t("总容量", en: "Total", zhHant: "總容量", ja: "合計容量", ko: "총 용량", mt: "Total") }
    var available: String { t("可用", en: "Available", zhHant: "可用", ja: "利用可能", ko: "사용 가능", mt: "Available") }
    var storageWarning: String { t("存储空间不足！建议立即清理", en: "Low storage! Clean up recommended", zhHant: "儲存空間不足！建議立即清理", ja: "ストレージ容量不足！クリーンアップをお勧めします", ko: "저장 공간 부족! 즉시 정리 권장", mt: "Low storage! Clean up recommended") }
    var alertThreshold: String { t("警报阈值", en: "Alert Threshold", zhHant: "警報閾值", ja: "アラートしきい値", ko: "알림 임계값", mt: "Alert Threshold") }
    var remainingPct: String { t("剩余", en: "Remaining", zhHant: "剩餘", ja: "残り", ko: "남은", mt: "Remaining") }

    var operationSettings: String { t("操作监控", en: "Operation Monitor", zhHant: "操作監控", ja: "操作モニター", ko: "작업 모니터", mt: "Operation Monitor") }
    var moveToTrash: String { t("删除移入回收站", en: "Move to Trash", zhHant: "刪除移入回收站", ja: "ゴミ箱に移動", ko: "휴지통으로 이동", mt: "Move to Trash") }
    var preventAutoEmptyTrash: String { t("禁止自动清空废纸篓", en: "Prevent Auto Empty Trash", zhHant: "禁止自動清空垃圾桶", ja: "ゴミ箱を自動で空にしない", ko: "휴지통 자동 비우기 방지", mt: "Prevent Auto Empty Trash") }
    var pauseMonitoring: String { t("暂停监控", en: "Pause Monitoring", zhHant: "暫停監控", ja: "モニタリング一時停止", ko: "모니터링 일시정지", mt: "Pause Monitoring") }
    var startMonitoringBtn: String { t("开始监控", en: "Start Monitoring", zhHant: "開始監控", ja: "モニタリング開始", ko: "모니터링 시작", mt: "Start Monitoring") }
    var clearRecords: String { t("清空", en: "Clear", zhHant: "清空", ja: "クリア", ko: "지우기", mt: "Clear") }
    var clearResults: String { t("清除结果", en: "Clear Results", zhHant: "清除結果", ja: "結果をクリア", ko: "결과 지우기", mt: "Clear Results") }
    var viewFullLog: String { t("查看完整记录", en: "View Full Log", zhHant: "檢視完整記錄", ja: "完全なログを表示", ko: "전체 기록 보기", mt: "View Full Log") }
    var quitApp: String { t("退出", en: "Quit", zhHant: "退出", ja: "終了", ko: "종료", mt: "Quit") }
    var openAIMacCleaner: String { t("打开 Agent卫士", en: "Open AgentGuard", zhHant: "打開 Agent衛士", ja: "AgentGuardを開く", ko: "AgentGuard 열기", mt: "Open AgentGuard") }
    var checkForUpdate: String { t("检查更新", en: "Check for Updates", zhHant: "檢查更新", ja: "アップデートを確認", ko: "업데이트 확인", mt: "Check for Updates") }
    var checkingUpdate: String { t("检查中...", en: "Checking...", zhHant: "檢查中...", ja: "確認中...", ko: "확인 중...", mt: "Checking...") }
    var running: String { t("运行中", en: "Running", zhHant: "執行中", ja: "実行中", ko: "실행 중", mt: "Running") }
    var notEnabled: String { t("未启用", en: "Not Enabled", zhHant: "未啟用", ja: "未有効", ko: "미활성화", mt: "Not Enabled") }
    var noData: String { t("暂无数据", en: "No Data", zhHant: "暫無資料", ja: "データなし", ko: "데이터 없음", mt: "No Data") }
    var noOpRecords: String { t("暂无操作记录", en: "No Operation Records", zhHant: "暫無操作記錄", ja: "操作記録なし", ko: "작업 기록 없음", mt: "No Operation Records") }
    var startMonitorHint: String { t("开启监控后将自动记录 Agent 操作", en: "Agent operations will be recorded once monitoring starts", zhHant: "開啟監控後將自動記錄 Agent 操作", ja: "モニタリング開始後、Agentの操作を自動記録します", ko: "모니터링 시작 후 Agent 작업을 자동 기록합니다", mt: "Agent operations will be recorded once monitoring starts") }
    var totalOps: String { t("总操作", en: "Total Ops", zhHant: "總操作", ja: "合計操作", ko: "총 작업", mt: "Total Ops") }
    var todayOps: String { t("今日", en: "Today", zhHant: "今日", ja: "今日", ko: "오늘", mt: "Today") }
    var hourOps: String { t("1小时", en: "1 Hour", zhHant: "1小時", ja: "1時間", ko: "1시간", mt: "1 Hour") }
    var agentActivity: String { t("Agent 活跃度", en: "Agent Activity", zhHant: "Agent 活躍度", ja: "Agent アクティビティ", ko: "Agent 활동", mt: "Agent Activity") }
    var noOpRecordsShort: String { t("暂无操作记录", en: "No Records", zhHant: "暫無操作記錄", ja: "操作記録なし", ko: "작업 기록 없음", mt: "No Records") }
    var opTypeDist: String { t("操作类型分布", en: "Operation Types", zhHant: "操作型別分佈", ja: "操作タイプ分布", ko: "작업 유형 분포", mt: "Operation Types") }
    var recentOps: String { t("最近操作", en: "Recent Operations", zhHant: "最近操作", ja: "最近の操作", ko: "최근 작업", mt: "Recent Operations") }

    var cpuLabel: String { t("CPU", en: "CPU", zhHant: "CPU", ja: "CPU", ko: "CPU", mt: "CPU") }
    var memoryLabel: String { t("内存", en: "Memory", zhHant: "記憶體", ja: "メモリ", ko: "메모리", mt: "Memory") }
    var cpuTempLabel: String { t("CPU 温度", en: "CPU Temp", zhHant: "CPU 溫度", ja: "CPU温度", ko: "CPU 온도", mt: "CPU Temp") }
    var batteryLabel: String { t("电池", en: "Battery", zhHant: "電池", ja: "バッテリー", ko: "배터리", mt: "Battery") }
    var networkLabel: String { t("网络", en: "Network", zhHant: "網路", ja: "ネットワーク", ko: "네트워크", mt: "Network") }
    var coresLabel: String { t("核", en: "Cores", zhHant: "核", ja: "コア", ko: "코어", mt: "Cores") }
    var processesLabel: String { t("进程", en: "Processes", zhHant: "程序", ja: "プロセス", ko: "프로세스", mt: "Processes") }
    var threadsLabel: String { t("线程", en: "Threads", zhHant: "執行緒", ja: "スレッド", ko: "스레드", mt: "Threads") }
    var runtimeLabel: String { t("运行", en: "Running", zhHant: "執行", ja: "実行中", ko: "실행 중", mt: "Running") }
    var overheating: String { t("过热", en: "Overheating", zhHant: "過熱", ja: "過熱", ko: "과열", mt: "Overheating") }
    var high: String { t("偏高", en: "High", zhHant: "偏高", ja: "高め", ko: "높음", mt: "High") }
    var normal: String { t("正常", en: "Normal", zhHant: "正常", ja: "正常", ko: "정상", mt: "Normal") }
    var charging: String { t("充电中", en: "Charging", zhHant: "充電中", ja: "充電中", ko: "충전 중", mt: "Charging") }
    var inUse: String { t("使用中", en: "In Use", zhHant: "使用中", ja: "使用中", ko: "사용 중", mt: "In Use") }

    var sortSize: String { t("大小", en: "Size", zhHant: "大小", ja: "サイズ", ko: "크기", mt: "Size") }
    var sortCreated: String { t("添加日期", en: "Date Added", zhHant: "新增日期", ja: "追加日", ko: "추가일", mt: "Date Added") }
    var sortModified: String { t("修改日期", en: "Modified", zhHant: "修改日期", ja: "更新日", ko: "수정일", mt: "Modified") }
    var sortName: String { t("名称", en: "Name", zhHant: "名稱", ja: "名前", ko: "이름", mt: "Name") }

    var sort: String { t("排序", en: "Sort", zhHant: "排序", ja: "並べ替え", ko: "정렬", mt: "Sort") }
    var analyze: String { t("分析", en: "Analyze", zhHant: "分析", ja: "分析", ko: "분석", mt: "Analyze") }
    var copyPath: String { t("复制路径", en: "Copy path", zhHant: "複製路徑", ja: "パスをコピー", ko: "경로 복사", mt: "Copy path") }

    var appManagerTitle: String { t("APP 管理", en: "App Manager", zhHant: "APP 管理", ja: "アプリ管理", ko: "앱 관리", mt: "App Manager") }
    var appManagerSubtitle: String { t("管理已安装的应用", en: "Manage installed applications", zhHant: "管理已安裝的應用", ja: "インストール済みアプリを管理", ko: "설치된 앱 관리", mt: "Manage installed applications") }
    var dependencyTitle: String { t("依赖管理", en: "Dependency Manager", zhHant: "依賴管理", ja: "依存関係管理", ko: "의존성 관리", mt: "Dependency Manager") }
    var dependencySubtitle: String { t("管理开发依赖", en: "Manage development dependencies", zhHant: "管理開發依賴", ja: "開発依存関係を管理", ko: "개발 의존성 관리", mt: "Manage development dependencies") }
    var otherToolsTitle: String { t("其它工具", en: "Other Tools", zhHant: "其它工具", ja: "その他ツール", ko: "기타 도구", mt: "Other Tools") }
    var otherToolsSubtitle: String { t("管理命令行工具", en: "Manage command line tools", zhHant: "管理命令列工具", ja: "CLIツールを管理", ko: "CLI 도구 관리", mt: "Manage command line tools") }
    var refresh: String { t("刷新", en: "Refresh", zhHant: "重新整理", ja: "更新", ko: "새로고침", mt: "Refresh") }
    var autoRefresh: String { t("自动刷新", en: "Auto Refresh", zhHant: "自動重新整理", ja: "自動更新", ko: "자동 새로고침", mt: "Auto Refresh") }
    var off: String { t("关闭", en: "Off", zhHant: "關閉", ja: "オフ", ko: "끄기", mt: "Off") }
    var all: String { t("全部", en: "All", zhHant: "全部", ja: "すべて", ko: "전체", mt: "All") }
    var actionConfirm: String { t("确认操作", en: "Confirm Action", zhHant: "確認操作", ja: "操作の確認", ko: "작업 확인", mt: "Confirm Action") }
    var actionComplete: String { t("操作完成", en: "Action Complete", zhHant: "操作完成", ja: "操作完了", ko: "작업 완료", mt: "Action Complete") }
    var searchingApps: String { t("搜索应用...", en: "Search apps...", zhHant: "搜尋應用...", ja: "アプリを検索...", ko: "앱 검색...", mt: "Search apps...") }
    var searchingScanning: String { t("正在扫描...", en: "Scanning...", zhHant: "正在掃描...", ja: "スキャン中...", ko: "스캔 중...", mt: "Scanning...") }

    var agentMonitorTitle: String { t("Agent 监控", en: "Agent Monitor", zhHant: "Agent 監控", ja: "Agent モニター", ko: "Agent 모니터", mt: "Agent Monitor") }
    var systemMonitorTitle: String { t("系统监控", en: "System Monitor", zhHant: "系統監控", ja: "システムモニター", ko: "시스템 모니터", mt: "System Monitor") }
    var agentMonitorSubtitle: String { t("监控 AI Agent 的实时操作、历史会话和本机审计记录", en: "Monitor live AI agent operations, local session history, and audit records", zhHant: "監控 AI Agent 的即時操作、歷史會話和本機審計記錄", ja: "AI Agentのリアルタイム操作、ローカルセッション履歴、監査記録をモニタリング", ko: "AI Agent의 실시간 작업, 로컬 세션 기록, 감사 기록 모니터링", mt: "Monitor live AI agent operations, local session history, and audit records") }
    var monitoring: String { t("监控中", en: "Monitoring", zhHant: "監控中", ja: "モニタリング中", ko: "모니터링 중", mt: "Monitoring") }
    var startMonitoring: String { t("开始监控", en: "Start Monitoring", zhHant: "開始監控", ja: "モニタリング開始", ko: "모니터링 시작", mt: "Start Monitoring") }
    var clear: String { t("清空", en: "Clear", zhHant: "清空", ja: "クリア", ko: "지우기", mt: "Clear") }
    var records: String { t("条记录", en: "records", zhHant: "條記錄", ja: "件の記録", ko: "건의 기록", mt: "records") }
    var noRecords: String { t("暂无操作记录", en: "No operation records yet", zhHant: "暫無操作記錄", ja: "操作記録なし", ko: "작업 기록 없음", mt: "No operation records yet") }
    var noRecordsHint: String { t("启动监控后将自动记录 AI Agent 的文件操作", en: "AI Agent file operations will be recorded once monitoring starts", zhHant: "啟動監控後將自動記錄 AI Agent 的檔案操作", ja: "モニタリング開始後、AI Agentのファイル操作を自動記録します", ko: "모니터링 시작 후 AI Agent 파일 작업을 자동 기록합니다", mt: "AI Agent file operations will be recorded once monitoring starts") }

    var settings: String { t("设置", en: "Settings", zhHant: "設定", ja: "設定", ko: "설정", mt: "Settings") }
    var collapseSidebar: String { t("收起", en: "Collapse", zhHant: "收起", ja: "折りたたむ", ko: "접기", mt: "Collapse") }
    var expandSidebar: String { t("展开侧边栏", en: "Expand sidebar", zhHant: "展開側邊欄", ja: "サイドバーを展開", ko: "사이드바 펼치기", mt: "Expand sidebar") }
    var features: String { t("功能", en: "Features", zhHant: "功能", ja: "機能", ko: "기능", mt: "Features") }

    var settingsTabAI: String { t("AI", en: "AI", zhHant: "AI", ja: "AI", ko: "AI", mt: "AI") }
    var settingsTabFeatures: String { t("功能", en: "Features", zhHant: "功能", ja: "機能", ko: "기능", mt: "Features") }
    var settingsTabLab: String { t("实验室", en: "Lab", zhHant: "實驗室", ja: "ラボ", ko: "실험실", mt: "Lab") }
    var settingsTabMonitor: String { t("监控", en: "Monitor", zhHant: "監控", ja: "モニター", ko: "모니터", mt: "Monitor") }
    var settingsTabLanguage: String { t("语言", en: "Language", zhHant: "語言", ja: "言語", ko: "언어", mt: "Language") }
    var settingsTabVersion: String { t("版本", en: "Version", zhHant: "版本", ja: "版本", ko: "Version", mt: "Version") }

    var navCleaner: String { t("Mac 清理", en: "Mac Cleaner", zhHant: "Mac 清理", ja: "Mac クリーナー", ko: "Mac 클리너", mt: "Mac Cleaner") }
    var navOverview: String { t("概览", en: "Overview", zhHant: "概覽", ja: "概要", ko: "개요", mt: "Overview") }
    var navApp: String { t("APP 管理", en: "App Manager", zhHant: "APP 管理", ja: "アプリ管理", ko: "앱 관리", mt: "App Manager") }
    var navDependency: String { t("依赖管理", en: "Dependency", zhHant: "依賴管理", ja: "依存関係管理", ko: "의존성 관리", mt: "Dependency") }
    var navOther: String { t("其它工具", en: "Other Tools", zhHant: "其它工具", ja: "その他ツール", ko: "기타 도구", mt: "Other Tools") }
    var navOperations: String { t("Agent 监控", en: "Agent Monitor", zhHant: "Agent 監控", ja: "Agent モニター", ko: "Agent 모니터", mt: "Agent Monitor") }

    var subCleaner: String { t("扫描并清理存储空间", en: "Scan and clean storage", zhHant: "掃描並清理儲存空間", ja: "ストレージをスキャンしてクリーンアップ", ko: "저장 공간 스캔 및 정리", mt: "Scan and clean storage") }
    var subOverview: String { t("Agent Top、实时会话与本机风险概览", en: "Agent Top, live sessions, and local risk overview", zhHant: "Agent Top、即時會話與本機風險概覽", ja: "Agent Top、ライブセッション、ローカルリスク概要", ko: "Agent Top, 실시간 세션 및 로컬 위험 개요", mt: "Agent Top, live sessions, and local risk overview") }
    var subApp: String { t("管理已安装的应用", en: "Manage installed apps", zhHant: "管理已安裝的應用", ja: "インストール済みアプリを管理", ko: "설치된 앱 관리", mt: "Manage installed apps") }
    var subDependency: String { t("管理开发依赖", en: "Manage dev dependencies", zhHant: "管理開發依賴", ja: "開発依存関係を管理", ko: "개발 의존성 관리", mt: "Manage dev dependencies") }
    var subOther: String { t("管理命令行工具", en: "Manage CLI tools", zhHant: "管理命令列工具", ja: "CLIツールを管理", ko: "CLI 도구 관리", mt: "Manage CLI tools") }
    var subOperations: String { t("实时操作、历史会话与本机审计", en: "Live operations, session history, and local audit", zhHant: "即時操作、歷史會話與本機審計", ja: "リアルタイム操作、セッション履歴、ローカル監査", ko: "실시간 작업, 세션 기록, 로컬 감사", mt: "Live operations, session history, and local audit") }

    var searching: String { t("搜索...", en: "Search...", zhHant: "搜尋...", ja: "検索...", ko: "검색...", mt: "Search...") }
    var notFound: String { t("未发现", en: "Not found", zhHant: "未發現", ja: "見つかりません", ko: "찾을 수 없음", mt: "Not found") }
    var selected: String { t("已选", en: "Selected", zhHant: "已選", ja: "選択済み", ko: "선택됨", mt: "Selected") }
    var selectAllBtn: String { t("全选", en: "Select All", zhHant: "全選", ja: "すべて選択", ko: "전체 선택", mt: "Select All") }
    var cancelBtn: String { t("取消", en: "Cancel", zhHant: "取消", ja: "キャンセル", ko: "취소", mt: "Cancel") }
    var reviewOnly: String { t("仅查看", en: "Review only", zhHant: "僅查看", ja: "表示のみ", ko: "검토 전용", mt: "Review only") }
    var resetAction: String { t("重置", en: "Reset", zhHant: "重置", ja: "リセット", ko: "재설정", mt: "Reset") }
    var basicUninstall: String { t("基础卸载", en: "Basic Uninstall", zhHant: "基礎解除安裝", ja: "基本アンインストール", ko: "기본 제거", mt: "Basic Uninstall") }
    var fullUninstall: String { t("完全卸载", en: "Full Uninstall", zhHant: "完全解除安裝", ja: "完全アンインストール", ko: "완전 제거", mt: "Full Uninstall") }
    var resetDesc: String { t("清除缓存和历史数据，恢复为全新安装状态（APP本身保留）", en: "Clear cache and data, restore to fresh install state", zhHant: "清除快取和歷史資料，恢復為全新安裝狀態（APP本身保留）", ja: "キャッシュとデータをクリアし、新規インストール状態に復元", ko: "캐시와 데이터를 지우고 새 설치 상태로 복원", mt: "Clear cache and data, restore to fresh install state") }
    var basicUninstallDesc: String { t("仅卸载安装文件，保留缓存和历史数据（重新安装后可恢复）", en: "Uninstall only, keep cache and data", zhHant: "僅解除安裝安裝檔案，保留快取和歷史資料（重新安裝後可恢復）", ja: "アンインストールのみ、キャッシュとデータを保持", ko: "제거만 하고 캐시와 데이터 유지", mt: "Uninstall only, keep cache and data") }
    var fullUninstallDesc: String { t("此 App Store 版本不提供完全卸载操作", en: "Full uninstall is not available in this App Store build", zhHant: "此 App Store 版本不提供完全解除安裝操作", ja: "このApp Store版では完全アンインストールは利用できません", ko: "이 App Store 빌드에서는 전체 제거를 사용할 수 없습니다", mt: "Full uninstall is not available in this App Store build") }
    var confirmAction: String { t("确认操作", en: "Confirm Action", zhHant: "確認操作", ja: "操作の確認", ko: "작업 확인", mt: "Confirm Action") }
    var actionDone: String { t("操作完成", en: "Action Done", zhHant: "操作完成", ja: "操作完了", ko: "작업 완료", mt: "Action Done") }
    var confirmBtn: String { t("确认", en: "Confirm", zhHant: "確認", ja: "確認", ko: "확인", mt: "Confirm") }
    var willAction: String { t("将", en: "Will", zhHant: "將", ja: "実行", ko: "실행", mt: "Will") }
    var total: String { t("共", en: "Total", zhHant: "共", ja: "合計", ko: "총", mt: "Total") }

    var nameCol: String { t("名称", en: "Name", zhHant: "名稱", ja: "名前", ko: "이름", mt: "Name") }
    var status: String { t("状态", en: "Status", zhHant: "狀態", ja: "状態", ko: "상태", mt: "Status") }
    var sourceCol: String { t("来源", en: "Source", zhHant: "來源", ja: "ソース", ko: "소스", mt: "Source") }
    var categoryCol: String { t("分类", en: "Category", zhHant: "分類", ja: "カテゴリ", ko: "분류", mt: "Category") }
    var descriptionCol: String { t("说明", en: "Description", zhHant: "說明", ja: "説明", ko: "설명", mt: "Description") }
    var versionCol: String { t("版本", en: "Version", zhHant: "版本", ja: "バージョン", ko: "버전", mt: "Version") }
    var archCol: String { t("架构", en: "Arch", zhHant: "架構", ja: "アーキテクチャ", ko: "아키텍처", mt: "Arch") }
    var riskCol: String { t("风险", en: "Risk", zhHant: "風險", ja: "リスク", ko: "위험", mt: "Risk") }
    var impactCol: String { t("影响说明", en: "Impact", zhHant: "影響說明", ja: "影響", ko: "영향", mt: "Impact") }
    var sizeCol: String { t("大小", en: "Size", zhHant: "大小", ja: "サイズ", ko: "크기", mt: "Size") }
    var actionCol: String { t("操作", en: "Action", zhHant: "操作", ja: "操作", ko: "작업", mt: "Action") }
    var safe: String { t("安全", en: "Safe", zhHant: "安全", ja: "安全", ko: "안전", mt: "Safe") }
    var dangerous: String { t("危险", en: "Dangerous", zhHant: "危險", ja: "危険", ko: "위험", mt: "Dangerous") }
    var warning: String { t("注意", en: "Warning", zhHant: "注意", ja: "注意", ko: "주의", mt: "Warning") }

    var timeCol: String { t("时间", en: "Time", zhHant: "時間", ja: "時間", ko: "시간", mt: "Time") }
    var agentCol: String { t("Agent", en: "Agent", zhHant: "Agent", ja: "Agent", ko: "Agent", mt: "Agent") }
    var opCol: String { t("操作", en: "Operation", zhHant: "操作", ja: "操作", ko: "작업", mt: "Operation") }
    var pathCol: String { t("目标路径", en: "Target Path", zhHant: "目標路徑", ja: "対象パス", ko: "대상 경로", mt: "Target Path") }
    var fileSizeCol: String { t("大小", en: "Size", zhHant: "大小", ja: "サイズ", ko: "크기", mt: "Size") }
    var allAgents: String { t("全部 Agent", en: "All Agents", zhHant: "全部 Agent", ja: "すべてのAgent", ko: "모든 Agent", mt: "All Agents") }
    var allTypes: String { t("全部类型", en: "All Types", zhHant: "全部型別", ja: "すべてのタイプ", ko: "모든 유형", mt: "All Types") }
    var timeRange: String { t("时间范围", en: "Time Range", zhHant: "時間範圍", ja: "時間範囲", ko: "시간 범위", mt: "Time Range") }
    var opTypeLabel: String { t("操作类型", en: "Operation Type", zhHant: "操作型別", ja: "操作タイプ", ko: "작업 유형", mt: "Operation Type") }
    var agentLabel: String { t("Agent", en: "Agent", zhHant: "Agent", ja: "Agent", ko: "Agent", mt: "Agent") }
    var recordsCount: String { t("条", en: "records", zhHant: "條", ja: "件", ko: "건", mt: "records") }

    var allCats: String { t("全部分类", en: "All Categories", zhHant: "全部分類", ja: "すべてのカテゴリ", ko: "모든 카테고리", mt: "All Categories") }

    var internetStatus: String { t("互联网", en: "Internet", zhHant: "網際網路", ja: "インターネット", ko: "인터넷", mt: "Internet") }
    var offlineStatus: String { t("离线", en: "Offline", zhHant: "離線", ja: "オフライン", ko: "오프라인", mt: "Offline") }

    var quitBehaviorTitle: String { t("退出行为", en: "Quit Behavior", zhHant: "退出行為", ja: "終了動作", ko: "종료 동작", mt: "Quit Behavior") }
    var quitBehaviorDesc: String { t("控制点击 Dock 退出按钮或 Cmd+Q 时的行为", en: "Control behavior when clicking Dock quit or pressing Cmd+Q", zhHant: "控制點選 Dock 退出按鈕或 Cmd+Q 時的行為", ja: "Dockの終了ボタンまたはCmd+Qの動作を設定", ko: "Dock 종료 버튼 또는 Cmd+Q 동작 설정", mt: "Control behavior when clicking Dock quit or pressing Cmd+Q") }
    var quitAppAndMenu: String { t("退出应用和菜单栏（默认）", en: "Quit App & Menu Bar (Default)", zhHant: "退出應用和選單欄（預設）", ja: "アプリとメニューバーを終了（デフォルト）", ko: "앱 및 메뉴 막대 종료（기본값）", mt: "Quit App & Menu Bar (Default)") }
    var quitAppKeepMenu: String { t("仅退出应用，保留菜单栏监控", en: "Quit App Only, Keep Menu Bar", zhHant: "僅退出應用，保留選單欄監控", ja: "アプリのみ終了、メニューバーモニターを維持", ko: "앱만 종료, 메뉴 막대 모니터 유지", mt: "Quit App Only, Keep Menu Bar")}

    var liveMonitor: String { t("实时监控", en: "Live Monitor", zhHant: "實時監控", ja: "リアルタイムモニター", ko: "실시간 모니터", mt: "Live Monitor") }
    var overviewCleanupByCategory: String { t("清理分类", en: "Cleanup Categories", zhHant: "清理分類", ja: "クリーンアップ分類", ko: "정리 분류", mt: "Cleanup Categories") }
    var overviewAppCounts: String { t("应用数量", en: "App Counts", zhHant: "應用數量", ja: "アプリ数", ko: "앱 수", mt: "App Counts") }
    var overviewAgentOperations: String { t("Agent 审计操作", en: "Agent Audit Operations", zhHant: "Agent 審計操作", ja: "Agent 監査操作", ko: "Agent 감사 작업", mt: "Agent Audit Operations") }
    var overviewTokenUsage: String { t("按 Agent 的 Token 用量", en: "Token Usage by Agent", zhHant: "按 Agent 的 Token 用量", ja: "Agent 別 Token 使用量", ko: "Agent별 Token 사용량", mt: "Token Usage by Agent") }
    var overviewAgentRuntime: String { t("Agent 运行状态", en: "Agent Runtime", zhHant: "Agent 執行狀態", ja: "Agent 実行状態", ko: "Agent 실행 상태", mt: "Agent Runtime") }
    var overviewSubtitle: String { t("会话、上下文、Token、项目和本机服务", en: "Sessions, context, tokens, projects, and local services", zhHant: "會話、上下文、Token、專案與本機服務", ja: "セッション、コンテキスト、トークン、プロジェクト、ローカルサービス", ko: "세션, 컨텍스트, 토큰, 프로젝트 및 로컬 서비스", mt: "Sessions, context, tokens, projects, and local services") }
    var commandCenterTitle: String { t("AgentGuard 指挥中心", en: "AgentGuard Command Center", zhHant: "AgentGuard 指揮中心", ja: "AgentGuard コマンドセンター", ko: "AgentGuard 명령 센터", mt: "AgentGuard Command Center") }
    var monitoringLive: String { t("实时监控中", en: "Monitoring Live", zhHant: "即時監控中", ja: "ライブ監視中", ko: "실시간 모니터링 중", mt: "Monitoring Live") }
    var workspaceSection: String { t("工作区", en: "Workspace", zhHant: "工作區", ja: "ワークスペース", ko: "작업 공간", mt: "Workspace") }
    var protectionOn: String { t("保护已开启", en: "Protection on", zhHant: "保護已開啟", ja: "保護オン", ko: "보호 켜짐", mt: "Protection on") }
    var overviewScanningAgentData: String { t("正在扫描 Agent 数据", en: "Scanning Agent data", zhHant: "正在掃描 Agent 資料", ja: "Agent データをスキャン中", ko: "Agent 데이터 스캔 중", mt: "Scanning Agent data") }
    var overviewAgentSessionsLoaded: String { t("已读取到 Agent 会话", en: "Agent sessions loaded", zhHant: "已讀取到 Agent 會話", ja: "Agent セッションを読み込みました", ko: "Agent 세션을 불러왔습니다", mt: "Agent sessions loaded") }
    var overviewAuthorizedNoSessions: String { t("已授权，但没有找到会话文件", en: "Authorized, but no session files found", zhHant: "已授權，但沒有找到會話檔案", ja: "許可済みですがセッションファイルは見つかりません", ko: "승인되었지만 세션 파일을 찾지 못했습니다", mt: "Authorized, but no session files found") }
    var overviewNoAgentFolders: String { t("还没有授权 Agent 数据目录", en: "No Agent data folders authorized", zhHant: "尚未授權 Agent 資料目錄", ja: "Agent データフォルダは未許可です", ko: "승인된 Agent 데이터 폴더가 없습니다", mt: "No Agent data folders authorized") }
    var overviewScanningDetail: String { t("正在读取授权目录、进程和最近会话文件。", en: "Reading authorized folders, processes, and recent session files.", zhHant: "正在讀取授權目錄、程序與最近會話檔案。", ja: "許可済みフォルダ、プロセス、最近のセッションファイルを読み込んでいます。", ko: "승인된 폴더, 프로세스, 최근 세션 파일을 읽는 중입니다.", mt: "Reading authorized folders, processes, and recent session files.") }
    var overviewChooseAgentFolders: String { t("请选择 ~/.codex、~/.claude，或按住 Command 多选需要监控的 Agent 数据目录。", en: "Choose ~/.codex, ~/.claude, or Command-select the Agent data folders to monitor.", zhHant: "請選擇 ~/.codex、~/.claude，或按住 Command 多選要監控的 Agent 資料目錄。", ja: "~/.codex、~/.claude、または監視する Agent データフォルダを Command キーで複数選択してください。", ko: "~/.codex, ~/.claude 또는 모니터링할 Agent 데이터 폴더를 Command 키로 다중 선택하세요.", mt: "Choose ~/.codex, ~/.claude, or Command-select the Agent data folders to monitor.") }
    var overviewSuggestedFolders: String { t("建议选择 ~/.codex、~/.claude 或包含这些目录的主目录。", en: "Choose ~/.codex, ~/.claude, or the home folder containing them.", zhHant: "建議選擇 ~/.codex、~/.claude 或包含這些目錄的主目錄。", ja: "~/.codex、~/.claude、またはそれらを含むホームフォルダを選択してください。", ko: "~/.codex, ~/.claude 또는 이를 포함하는 홈 폴더를 선택하세요.", mt: "Choose ~/.codex, ~/.claude, or the home folder containing them.") }
    var overviewNeverScanned: String { t("尚未扫描", en: "Not scanned yet", zhHant: "尚未掃描", ja: "未スキャン", ko: "아직 스캔하지 않음", mt: "Not scanned yet") }
    var overviewLastScan: String { t("上次扫描", en: "Last scan", zhHant: "上次掃描", ja: "前回スキャン", ko: "마지막 스캔", mt: "Last scan") }
    var overviewNotAuthorized: String { t("未检测到授权目录", en: "No authorized folders", zhHant: "未偵測到授權目錄", ja: "許可済みフォルダなし", ko: "승인된 폴더 없음", mt: "No authorized folders") }
    var overviewAuthorizedFolders: String { t("已授权", en: "Authorized", zhHant: "已授權", ja: "許可済み", ko: "승인됨", mt: "Authorized") }
    var overviewFoldersUnit: String { t("个目录", en: " folders", zhHant: "個目錄", ja: "件", ko: "개 폴더", mt: " folders") }
    var overviewWaitingForSelection: String { t("等待选择目录", en: "Waiting for folder selection", zhHant: "等待選擇目錄", ja: "フォルダ選択待ち", ko: "폴더 선택 대기 중", mt: "Waiting for folder selection") }
    var overviewScanningAuthorizedFolders: String { t("正在扫描授权目录", en: "Scanning authorized folders", zhHant: "正在掃描授權目錄", ja: "許可済みフォルダをスキャン中", ko: "승인된 폴더 스캔 중", mt: "Scanning authorized folders") }
    var overviewRescanning: String { t("正在重新扫描", en: "Rescanning", zhHant: "正在重新掃描", ja: "再スキャン中", ko: "다시 스캔 중", mt: "Rescanning") }
    var overviewScanning: String { t("正在扫描", en: "Scanning", zhHant: "正在掃描", ja: "スキャン中", ko: "스캔 중", mt: "Scanning") }
    var overviewWaitingSessions: String { t("等待会话", en: "Waiting for sessions", zhHant: "等待會話", ja: "セッション待ち", ko: "세션 대기 중", mt: "Waiting for sessions") }
    var overviewAuthorizeFolder: String { t("授权目录", en: "Authorize Folder", zhHant: "授權目錄", ja: "フォルダを許可", ko: "폴더 승인", mt: "Authorize Folder") }
    var overviewReauthorizeFolder: String { t("重新授权", en: "Re-authorize", zhHant: "重新授權", ja: "再認証", ko: "다시 승인", mt: "Re-authorize") }
    var overviewSessions: String { t("会话", en: "Sessions", zhHant: "會話", ja: "セッション", ko: "세션", mt: "Sessions") }
    var overviewSession: String { t("会话", en: "Session", zhHant: "會話", ja: "セッション", ko: "세션", mt: "Session") }
    var overviewTokensTotal: String { t("Token 总量", en: "Total Tokens", zhHant: "Token 總量", ja: "トークン合計", ko: "총 토큰", mt: "Total Tokens") }
    var overviewLiveActivity: String { t("实时活动", en: "Live activity", zhHant: "即時活動", ja: "ライブアクティビティ", ko: "실시간 활동", mt: "Live activity") }
    var overviewRealtimeConversations: String { t("实时对话数", en: "Live Conversations", zhHant: "即時對話數", ja: "ライブ会話数", ko: "실시간 대화 수", mt: "Live Conversations") }
    var overviewRealtimeToolCalls: String { t("实时工具调用数", en: "Live Tool Calls", zhHant: "即時工具呼叫數", ja: "ライブツール呼び出し", ko: "실시간 도구 호출 수", mt: "Live Tool Calls") }
    var overviewRealtimeAgentRuns: String { t("实时 Agent 运行数", en: "Live Agent Runs", zhHant: "即時 Agent 執行數", ja: "ライブ Agent 実行数", ko: "실시간 Agent 실행 수", mt: "Live Agent Runs") }
    var overviewLiveAndHistory: String { t("实时 + 最近历史", en: "Live + recent history", zhHant: "即時 + 最近歷史", ja: "ライブ + 最近の履歴", ko: "실시간 + 최근 기록", mt: "Live + recent history") }
    var overviewWaitingOrStartAgent: String { t("等待授权或启动 Agent", en: "Authorize or start an Agent", zhHant: "等待授權或啟動 Agent", ja: "許可または Agent 起動待ち", ko: "승인 또는 Agent 시작 대기", mt: "Authorize or start an Agent") }
    var overviewInputOutputCache: String { t("输入、输出和缓存读", en: "Input, output, and cache read", zhHant: "輸入、輸出與快取讀取", ja: "入力、出力、キャッシュ読み取り", ko: "입력, 출력 및 캐시 읽기", mt: "Input, output, and cache read") }
    var overviewTokenUse: String { t("Token 使用", en: "Token Usage", zhHant: "Token 使用", ja: "トークン使用量", ko: "토큰 사용량", mt: "Token Usage") }
    var overviewInput: String { t("输入", en: "Input", zhHant: "輸入", ja: "入力", ko: "입력", mt: "Input") }
    var overviewOutput: String { t("输出", en: "Output", zhHant: "輸出", ja: "出力", ko: "출력", mt: "Output") }
    var overviewCacheRead: String { t("缓存读", en: "Cache Read", zhHant: "快取讀取", ja: "キャッシュ読み取り", ko: "캐시 읽기", mt: "Cache Read") }
    var overviewTotal: String { t("总计", en: "Total", zhHant: "總計", ja: "合計", ko: "합계", mt: "Total") }
    var overviewRefreshRate: String { t("刷新速率", en: "Refresh Rate", zhHant: "刷新速率", ja: "更新速度", ko: "새로고침 속도", mt: "Refresh Rate") }
    var overviewCurrentTurn: String { t("当前轮次", en: "Current Turn", zhHant: "目前輪次", ja: "現在のターン", ko: "현재 턴", mt: "Current Turn") }
    var overviewModel: String { t("模型", en: "Model", zhHant: "模型", ja: "モデル", ko: "모델", mt: "Model") }
    var overviewProjectContext: String { t("项目上下文", en: "Project Context", zhHant: "專案上下文", ja: "プロジェクトコンテキスト", ko: "프로젝트 컨텍스트", mt: "Project Context") }
    var overviewNoProject: String { t("暂无项目", en: "No projects yet", zhHant: "暫無專案", ja: "プロジェクトなし", ko: "아직 프로젝트 없음", mt: "No projects yet") }
    var overviewNoProjectHint: String { t("授权数据目录后会按项目聚合上下文和 Token。", en: "Authorize data folders to group context and tokens by project.", zhHant: "授權資料目錄後會按專案彙總上下文與 Token。", ja: "データフォルダを許可すると、プロジェクト別にコンテキストとトークンを集計します。", ko: "데이터 폴더를 승인하면 프로젝트별 컨텍스트와 토큰을 집계합니다.", mt: "Authorize data folders to group context and tokens by project.") }
    var overviewSessionList: String { t("会话列表", en: "Session List", zhHant: "會話列表", ja: "セッション一覧", ko: "세션 목록", mt: "Session List") }
    var overviewSearchPlaceholder: String { t("搜索项目、模型或任务", en: "Search projects, models, or tasks", zhHant: "搜尋專案、模型或任務", ja: "プロジェクト、モデル、タスクを検索", ko: "프로젝트, 모델 또는 작업 검색", mt: "Search projects, models, or tasks") }
    var overviewNoSessions: String { t("没有可显示的会话", en: "No sessions to show", zhHant: "沒有可顯示的會話", ja: "表示するセッションなし", ko: "표시할 세션 없음", mt: "No sessions to show") }
    var overviewNoSessionsHint: String { t("授权 ~/.codex / ~/.claude，或启动一个 Agent 会话。", en: "Authorize ~/.codex / ~/.claude, or start an Agent session.", zhHant: "授權 ~/.codex / ~/.claude，或啟動一個 Agent 會話。", ja: "~/.codex / ~/.claude を許可するか、Agent セッションを開始してください。", ko: "~/.codex / ~/.claude를 승인하거나 Agent 세션을 시작하세요.", mt: "Authorize ~/.codex / ~/.claude, or start an Agent session.") }
    var overviewNoActiveSession: String { t("当前没有活跃会话", en: "No active sessions", zhHant: "目前沒有活躍會話", ja: "アクティブなセッションはありません", ko: "현재 활성 세션 없음", mt: "No active sessions") }
    var overviewNoActiveSessionHint: String { t("实时监听已就绪；当 Agent 进入思考、执行或等待输入时，会显示在这里。", en: "Live monitoring is ready. Sessions appear here when an Agent is thinking, executing, or waiting for input.", zhHant: "即時監聽已就緒；當 Agent 進入思考、執行或等待輸入時，會顯示在這裡。", ja: "ライブ監視は準備完了です。Agent が思考、実行、入力待ちになるとここに表示されます。", ko: "실시간 모니터링이 준비되었습니다. Agent가 사고, 실행 또는 입력 대기 상태가 되면 여기에 표시됩니다.", mt: "Live monitoring is ready. Sessions appear here when an Agent is thinking, executing, or waiting for input.") }
    var overviewAuthorizeAgentData: String { t("授权 Agent 数据目录", en: "Authorize Agent Data Folder", zhHant: "授權 Agent 資料目錄", ja: "Agent データフォルダを許可", ko: "Agent 데이터 폴더 승인", mt: "Authorize Agent Data Folder") }
    var overviewPreviousSession: String { t("上一条会话", en: "Previous session", zhHant: "上一條會話", ja: "前のセッション", ko: "이전 세션", mt: "Previous session") }
    var overviewNextSession: String { t("下一条会话", en: "Next session", zhHant: "下一條會話", ja: "次のセッション", ko: "다음 세션", mt: "Next session") }
    var overviewWaitingAgentSession: String { t("等待 Agent 会话", en: "Waiting for Agent session", zhHant: "等待 Agent 會話", ja: "Agent セッション待ち", ko: "Agent 세션 대기 중", mt: "Waiting for Agent session") }
    var overviewContextWindow: String { t("上下文窗口", en: "Context Window", zhHant: "上下文視窗", ja: "コンテキストウィンドウ", ko: "컨텍스트 창", mt: "Context Window") }
    var overviewProject: String { t("项目", en: "Project", zhHant: "專案", ja: "プロジェクト", ko: "프로젝트", mt: "Project") }
    var overviewLocation: String { t("位置", en: "Location", zhHant: "位置", ja: "場所", ko: "위치", mt: "Location") }
    var overviewSummary: String { t("摘要", en: "Summary", zhHant: "摘要", ja: "概要", ko: "요약", mt: "Summary") }
    var overviewMemory: String { t("内存", en: "Memory", zhHant: "記憶體", ja: "メモリ", ko: "메모리", mt: "Memory") }
    var overviewTurns: String { t("轮", en: "Turns", zhHant: "輪", ja: "ターン", ko: "턴", mt: "Turns") }
    var overviewNeedAuthorize: String { t("需要授权 Agent 数据目录", en: "Agent data folder authorization needed", zhHant: "需要授權 Agent 資料目錄", ja: "Agent データフォルダの許可が必要です", ko: "Agent 데이터 폴더 승인이 필요합니다", mt: "Agent data folder authorization needed") }
    var overviewNeedAuthorizeHint: String { t("授权 ~/.codex、~/.claude 或项目目录后，才能读取历史命令、审计记录并持续实时监控。", en: "Authorize ~/.codex, ~/.claude, or a project folder to read command history, audit records, and live monitor data.", zhHant: "授權 ~/.codex、~/.claude 或專案目錄後，才能讀取歷史命令、審計記錄並持續即時監控。", ja: "~/.codex、~/.claude、またはプロジェクトフォルダを許可すると、コマンド履歴、監査記録、ライブ監視データを読み取れます。", ko: "~/.codex, ~/.claude 또는 프로젝트 폴더를 승인하면 명령 기록, 감사 기록, 실시간 모니터링 데이터를 읽을 수 있습니다.", mt: "Authorize ~/.codex, ~/.claude, or a project folder to read command history, audit records, and live monitor data.") }
    var overviewStatusWaiting: String { t("等待", en: "Waiting", zhHant: "等待", ja: "待機", ko: "대기", mt: "Waiting") }
    var overviewStatusThinking: String { t("思考", en: "Thinking", zhHant: "思考", ja: "思考中", ko: "생각 중", mt: "Thinking") }
    var overviewStatusExecuting: String { t("执行", en: "Executing", zhHant: "執行", ja: "実行中", ko: "실행 중", mt: "Executing") }
    var overviewStatusHistory: String { t("历史", en: "History", zhHant: "歷史", ja: "履歴", ko: "기록", mt: "History") }
    var overviewStatusDone: String { t("完成", en: "Done", zhHant: "完成", ja: "完了", ko: "완료", mt: "Done") }
    var overviewStatusUnknown: String { t("未知", en: "Unknown", zhHant: "未知", ja: "不明", ko: "알 수 없음", mt: "Unknown") }
    var overviewContextHealthy: String { t("健康", en: "Healthy", zhHant: "健康", ja: "正常", ko: "정상", mt: "Healthy") }
    var overviewContextWatch: String { t("需要关注", en: "Watch", zhHant: "需要關注", ja: "注意", ko: "주의 필요", mt: "Watch") }
    var overviewContextNearLimit: String { t("接近上限", en: "Near limit", zhHant: "接近上限", ja: "上限に近い", ko: "한도 근접", mt: "Near limit") }
    var systemHealth: String { t("系统健康", en: "System Health", zhHant: "系統健康", ja: "システム健全性", ko: "시스템 상태", mt: "System Health") }
    var cleanupRisk: String { t("清理风险", en: "Cleanup Risk", zhHant: "清理風險", ja: "クリーンアップリスク", ko: "정리 위험", mt: "Cleanup Risk") }
    var appFootprint: String { t("应用占用", en: "App Footprint", zhHant: "應用占用", ja: "アプリ使用量", ko: "앱 사용량", mt: "App Footprint") }
    var activityMix: String { t("活动构成", en: "Activity Mix", zhHant: "活動構成", ja: "アクティビティ構成", ko: "활동 구성", mt: "Activity Mix") }
    var diskUsage: String { t("磁盘使用", en: "Disk Usage", zhHant: "磁碟使用", ja: "ディスク使用量", ko: "디스크 사용량", mt: "Disk Usage") }
    var freeSpace: String { t("剩余", en: "free", zhHant: "剩餘", ja: "空き", ko: "남음", mt: "free") }
    var memoryUsage: String { t("内存使用", en: "Memory Usage", zhHant: "記憶體使用", ja: "メモリ使用量", ko: "메모리 사용량", mt: "Memory Usage") }
    var cpuUsage: String { t("CPU 使用", en: "CPU Usage", zhHant: "CPU 使用", ja: "CPU 使用量", ko: "CPU 사용량", mt: "CPU Usage") }
    var cpuCores: String { t("核心", en: "cores", zhHant: "核心", ja: "コア", ko: "코어", mt: "cores") }
    var cleanupCandidates: String { t("可清理项", en: "Cleanup Items", zhHant: "可清理項", ja: "クリーンアップ候補", ko: "정리 항목", mt: "Cleanup Items") }
    var totalSizeLabel: String { t("总大小", en: "Total Size", zhHant: "總大小", ja: "合計サイズ", ko: "총 크기", mt: "Total Size") }
    var activeAgents: String { t("活跃 Agent", en: "Active Agents", zhHant: "活躍 Agent", ja: "アクティブ Agent", ko: "활성 Agent", mt: "Active Agents") }
    var contextWindow: String { t("上下文", en: "Context", zhHant: "上下文", ja: "コンテキスト", ko: "컨텍스트", mt: "Context") }
    var openPorts: String { t("端口", en: "Ports", zhHant: "連接埠", ja: "ポート", ko: "포트", mt: "Ports") }
    var latestActivity: String { t("最近活动", en: "Latest", zhHant: "最近活動", ja: "最新", ko: "최근", mt: "Latest") }
    var audit: String { t("审计", en: "Audit", zhHant: "審計", ja: "監査", ko: "감사", mt: "Audit") }
    var auditColon: String { t("审计: ", en: "Audit: ", zhHant: "審計: ", ja: "監査: ", ko: "감사: ", mt: "Audit: ") }
    var auditRecordCount: String { t("条记录", en: "records", zhHant: "條記錄", ja: "件の記録", ko: "건의 기록", mt: "records") }
    var back: String { t("返回", en: "Back", zhHant: "返回", ja: "戻る", ko: "뒤로", mt: "Back") }
    var aiAnalyzing: String { t("分析中...", en: "Analyzing...", zhHant: "分析中...", ja: "分析中...", ko: "분석 중...", mt: "Analyzing...") }
    var aiSummaryTitle: String { t("AI 分析总结", en: "AI Analysis Summary", zhHant: "AI 分析總結", ja: "AI分析サマリー", ko: "AI 분석 요약", mt: "AI Analysis Summary") }
    var aiLearning: String { t("AI 学习中", en: "AI Learning", zhHant: "AI 學習中", ja: "AI学習中", ko: "AI 학습 중", mt: "AI Learning") }
    var closeAI: String { t("关闭 AI", en: "Close AI", zhHant: "關閉 AI", ja: "AIを閉じる", ko: "AI 닫기", mt: "Close AI") }
    var noCuratedData: String { t("暂无梳理数据", en: "No curated data", zhHant: "暫無梳理資料", ja: "整理データなし", ko: "정리 데이터 없음", mt: "No curated data") }
    var noCuratedHint: String { t("点击\"立即梳理\"通过 AI 分析原始监控数据", en: "Click \"Curate Now\" to analyze raw data with AI", zhHant: "點擊\"立即梳理\"通過 AI 分析原始監控資料", ja: "「今すぐ整理」をクリックしてAIで生データを分析", ko: "\"지금 정리\"를 클릭하여 AI로 원본 데이터 분석", mt: "Click \"Curate Now\" to analyze raw data with AI") }
    var agentOpAudit: String { t("Agent 操作审计", en: "Agent Operation Audit", zhHant: "Agent 操作審計", ja: "Agent操作監査", ko: "Agent 작업 감사", mt: "Agent Operation Audit") }
    var scanToDiscover: String { t("点击\"刷新扫描\"发现本机的 Agent 会话记录", en: "Click \"Scan\" to discover Agent sessions", zhHant: "點擊\"刷新掃描\"發現本機的 Agent 會話記錄", ja: "「スキャン」をクリックしてAgentセッションを検出", ko: "\"스캔\"을 클릭하여 Agent 세션 감지", mt: "Click \"Scan\" to discover Agent sessions") }
    var supportedAgents: String { t("支持 Claude Code、Codex、Trae、Cursor、CodeBuddy、Aider、Cline 等 20+ 种 Agent", en: "Supports Claude Code, Codex, Trae, Cursor, CodeBuddy, Aider, Cline and 20+ agents", zhHant: "支援 Claude Code、Codex、Trae、Cursor、CodeBuddy、Aider、Cline 等 20+ 種 Agent", ja: "Claude Code、Codex、Trae、Cursor、CodeBuddy、Aider、Cline等20+のAgentに対応", ko: "Claude Code, Codex, Trae, Cursor, CodeBuddy, Aider, Cline 등 20+ Agent 지원", mt: "Supports Claude Code, Codex, Trae, Cursor, CodeBuddy, Aider, Cline and 20+ agents") }
    var scanRefresh: String { t("刷新扫描", en: "Refresh Scan", zhHant: "重新整理掃描", ja: "スキャン更新", ko: "스캔 새로고침", mt: "Refresh Scan") }
    var customBadge: String { t("自定义", en: "Custom", zhHant: "自定義", ja: "カスタム", ko: "사용자 정의", mt: "Custom") }
    var addCustomAgent: String { t("添加自定义 Agent", en: "Add Custom Agent", zhHant: "新增自定義 Agent", ja: "カスタムAgentを追加", ko: "사용자 정의 Agent 추가", mt: "Add Custom Agent") }
    var selectFromInstalled: String { t("从已安装的 APP/依赖/工具中选择", en: "Select from installed apps/deps/tools", zhHant: "從已安裝的 APP/依賴/工具中選擇", ja: "インストール済みアプリ/依存/ツールから選択", ko: "설치된 앱/의존성/도구에서 선택", mt: "Select from installed apps/deps/tools") }
    var customAgentName: String { t("名称", en: "Name", zhHant: "名稱", ja: "名前", ko: "이름", mt: "Name") }
    var sessionPathHint: String { t("会话目录路径 (如 ~/.trae/sessions)", en: "Session directory path (e.g. ~/.trae/sessions)", zhHant: "會話目錄路徑 (如 ~/.trae/sessions)", ja: "セッションディレクトリパス（例: ~/.trae/sessions）", ko: "세션 디렉토리 경로（예: ~/.trae/sessions）", mt: "Session directory path (e.g. ~/.trae/sessions)") }
    var removeCustomAgent: String { t("移除自定义 Agent", en: "Remove Custom Agent", zhHant: "移除自定義 Agent", ja: "カスタムAgentを削除", ko: "사용자 정의 Agent 제거", mt: "Remove Custom Agent") }
    var highFreqFiles: String { t("高频文件:", en: "Top Files:", zhHant: "高頻檔案:", ja: "高頻度ファイル:", ko: "고빈도 파일:", mt: "Top Files:") }
    var filterColon: String { t("筛选: ", en: "Filter: ", zhHant: "篩選: ", ja: "フィルター: ", ko: "필터: ", mt: "Filter: ") }
    var scanAgentSession: String { t("正在扫描 Agent 会话...", en: "Scanning Agent sessions...", zhHant: "正在掃描 Agent 會話...", ja: "Agentセッションをスキャン中...", ko: "Agent 세션 스캔 중...", mt: "Scanning Agent sessions...") }
    var parsingAgentOps: String { t("正在解析", en: "Parsing", zhHant: "正在解析", ja: "解析中", ko: "파싱 중", mt: "Parsing") }
    var operationsRecord: String { t("的操作记录...", en: "operations...", zhHant: "的操作記錄...", ja: "の操作記録...", ko: "의 작업 기록...", mt: "operations...") }
    var monitoringStarted: String { t("监控已启动，等待文件操作事件...", en: "Monitoring started, waiting for file events...", zhHant: "監控已啟動，等待檔案操作事件...", ja: "モニタリング開始、ファイルイベントを待機中...", ko: "모니터링 시작, 파일 이벤트 대기 중...", mt: "Monitoring started, waiting for file events...") }
    var monitoringHint: String { t("请在其他应用中创建、修改或删除文件以产生记录", en: "Create, modify or delete files in other apps to generate records", zhHant: "請在其他應用中建立、修改或刪除檔案以產生記錄", ja: "他のアプリでファイルを作成・変更・削除して記録を生成してください", ko: "다른 앱에서 파일을 생성, 수정 또는 삭제하여 기록을 생성하세요", mt: "Create, modify or delete files in other apps to generate records") }
    var searchingLabel: String { t("搜索", en: "Search", zhHant: "搜尋", ja: "検索", ko: "검색", mt: "Search") }
    var searchingPlaceholder: String { t("搜索...", en: "Search...", zhHant: "搜尋...", ja: "検索...", ko: "검색...", mt: "Search...") }
    var checkUpdates: String { t("检查更新", en: "Check Updates", zhHant: "檢查更新", ja: "アップデートを確認", ko: "업데이트 확인", mt: "Check Updates") }

    var deviceMonitor: String { t("设备监控", en: "Device Monitor", zhHant: "裝置監控", ja: "デバイスモニター", ko: "장치 모니터", mt: "Device Monitor") }
    var deviceMonitorSubtitle: String { t("摄像头与麦克风使用监控", en: "Camera & Microphone Monitor", zhHant: "攝像頭與麥克風使用監控", ja: "カメラとマイクの使用モニタリング", ko: "카메라 및 마이크 사용 모니터링", mt: "Camera & Microphone Monitor") }
    var camera: String { t("摄像头", en: "Camera", zhHant: "攝像頭", ja: "カメラ", ko: "카메라", mt: "Camera") }
    var microphone: String { t("麦克风", en: "Microphone", zhHant: "麥克風", ja: "マイク", ko: "마이크", mt: "Microphone") }
    var stopMonitor: String { t("停止监控", en: "Stop Monitor", zhHant: "停止監控", ja: "モニタリング停止", ko: "모니터링 중지", mt: "Stop Monitor") }
    var deviceMonitorStopped: String { t("设备监控未启动", en: "Device Monitor Stopped", zhHant: "裝置監控未啟動", ja: "デバイスモニター未起動", ko: "장치 모니터 미시작", mt: "Device Monitor Stopped") }
    var deviceMonitorHint: String { t("启动后将监控摄像头和麦克风的使用情况", en: "Monitor camera and microphone usage after start", zhHant: "啟動後將監控攝像頭和麥克風的使用情況", ja: "起動後、カメラとマイクの使用状況をモニタリング", ko: "시작 후 카메라와 마이크 사용 현황 모니터링", mt: "Monitor camera and microphone usage after start") }
    var noDeviceCall: String { t("未检测到设备调用", en: "No Device Call Detected", zhHant: "未檢測到裝置呼叫", ja: "デバイスの使用を検出できません", ko: "장치 사용 감지 안 됨", mt: "No Device Call Detected") }
    var noDeviceCallHint: String { t("摄像头和麦克风均未被使用", en: "Camera and microphone are not in use", zhHant: "攝像頭和麥克風均未被使用", ja: "カメラとマイクは使用されていません", ko: "카메라와 마이크 모두 사용되지 않음", mt: "Camera and microphone are not in use") }

    var scanningStorage: String { t("正在扫描存储空间...", en: "Scanning storage...", zhHant: "正在掃描儲存空間...", ja: "ストレージをスキャン中...", ko: "저장 공간 스캔 중...", mt: "Scanning storage...") }
    var scanningStorageHint: String { t("请稍候，正在分析可清理的文件", en: "Please wait, analyzing cleanable files", zhHant: "請稍候，正在分析可清理的檔案", ja: "お待ちください、クリーンアップ可能なファイルを分析中", ko: "잠시만 기다려 주세요, 정리 가능한 파일 분석 중", mt: "Please wait, analyzing cleanable files") }
    var noMatchesHint: String { t("当前筛选条件下没有匹配项", en: "No matches under current filters", zhHant: "當前篩選條件下沒有匹配項", ja: "現在のフィルター条件に一致する項目がありません", ko: "현재 필터 조건에 일치하는 항목이 없습니다", mt: "No matches under current filters") }
    var smartCleanDesc: String { t("智能清理 Mac 存储空间", en: "Intelligently clean Mac storage", zhHant: "智慧清理 Mac 儲存空間", ja: "Macストレージをスマートにクリーンアップ", ko: "Mac 저장 공간 스마트 정리", mt: "Intelligently clean Mac storage") }

    var installingUpdate: String { t("正在安装更新，应用即将重启...", en: "Installing update, app will restart...", zhHant: "正在安裝更新，應用即將重啟...", ja: "アップデートをインストール中、アプリが再起動します...", ko: "업데이트 설치 중, 앱이 재시작됩니다...", mt: "Installing update, app will restart...") }
    var updateDownloaded: String { t("更新已下载完成", en: "Update download complete", zhHant: "更新已下載完成", ja: "アップデートのダウンロード完了", ko: "업데이트 다운로드 완료", mt: "Update download complete") }
    var quitAndInstall: String { t("退出并安装", en: "Quit & Install", zhHant: "退出並安裝", ja: "終了してインストール", ko: "종료 후 설치", mt: "Quit & Install") }
    var retryDownload: String { t("重试下载", en: "Retry Download", zhHant: "重試下載", ja: "ダウンロードを再試行", ko: "다운로드 재시도", mt: "Retry Download") }
    var updateToVersion: String { t("更新到", en: "Update to", zhHant: "更新到", ja: "アップデート", ko: "업데이트", mt: "Update to") }
    var scanningAppList: String { t("正在扫描已安装应用列表...", en: "Scanning installed app list...", zhHant: "正在掃描已安裝應用列表...", ja: "インストール済みアプリをスキャン中...", ko: "설치된 앱 목록 스캔 중...", mt: "Scanning installed app list...") }
    var confirmUninstallMsg: String { t("确定要卸载", en: "Are you sure you want to uninstall", zhHant: "確定要解除安裝", ja: "アンインストールしますか", ko: "제거하시겠습니까", mt: "Are you sure you want to uninstall") }
    var irreversibleMsg: String { t("此操作不可撤销。", en: "This action is irreversible.", zhHant: "此操作不可撤銷。", ja: "この操作は元に戻せません。", ko: "이 작업은 되돌릴 수 없습니다.", mt: "This action is irreversible.") }
    var willUninstallIntel: String { t("将卸载", en: "Will uninstall", zhHant: "將解除安裝", ja: "アンインストールします", ko: "제거합니다", mt: "Will uninstall") }
    var intelVersionMsg: String { t("的 Intel 版本，并尝试安装 ARM 原生版本。", en: "Intel version and try to install ARM native version.", zhHant: "的 Intel 版本，並嘗試安裝 ARM 原生版本。", ja: "のIntel版をアンインストールし、ARMネイティブ版のインストールを試みます。", ko: "의 Intel 버전을 제거하고 ARM 네이티브 버전 설치를 시도합니다.", mt: "Intel version and try to install ARM native version.") }
    var scannedCount: String { t("已扫描", en: "Scanned", zhHant: "已掃描", ja: "スキャン済み", ko: "스캔됨", mt: "Scanned") }
    var itemsLabel: String { t("项", en: "items", zhHant: "項", ja: "項目", ko: "항목", mt: "items") }
    var clickScanToDetect: String { t("点击\"扫描\"开始检测", en: "Click \"Scan\" to start detection", zhHant: "點擊\"掃描\"開始檢測", ja: "「スキャン」をクリックして検出開始", ko: "\"스캔\"을 클릭하여 감지 시작", mt: "Click \"Scan\" to start detection") }
    var scanDesc1: String { t("将扫描所有已安装的APP、依赖和CLI工具的CPU架构", en: "Scan CPU architecture of all installed apps, deps and CLI tools", zhHant: "將掃描所有已安裝的APP、依賴和CLI工具的CPU架構", ja: "インストール済みアプリ、依存、CLIツールのCPUアーキテクチャをスキャン", ko: "설치된 모든 앱, 의존성, CLI 도구의 CPU 아키텍처를 스캔", mt: "Scan CPU architecture of all installed apps, deps and CLI tools") }
    var scanDesc2: String { t("检测哪些需要适配当前 Apple Silicon 芯片", en: "Detect which need adaptation for the current Apple Silicon chip", zhHant: "檢測哪些需要適配當前 Apple Silicon 晶片", ja: "現在のApple Siliconチップに適応が必要なものを検出", ko: "현재 Apple Silicon 칩에 적응이 필요한 항목 감지", mt: "Detect which need adaptation for the current Apple Silicon chip") }
    var firstScanHint: String { t("请稍候，首次扫描需要获取所有应用信息", en: "Please wait, first scan needs to fetch all app info", zhHant: "請稍候，首次掃描需要獲取所有應用資訊", ja: "お待ちください、初回スキャンは全アプリ情報を取得します", ko: "잠시만 기다려 주세요, 첫 스캔은 모든 앱 정보를 가져옵니다", mt: "Please wait, first scan needs to fetch all app info") }
    var detectingArch: String { t("正在检测CPU架构...", en: "Detecting CPU architecture...", zhHant: "正在檢測CPU架構...", ja: "CPUアーキテクチャを検出中...", ko: "CPU 아키텍처 감지 중...", mt: "Detecting CPU architecture...") }
    var allAdapted: String { t("所有应用均已适配 Apple Silicon", en: "All apps are adapted for Apple Silicon", zhHant: "所有應用均已適配 Apple Silicon", ja: "すべてのアプリがApple Siliconに適応済み", ko: "모든 앱이 Apple Silicon에 적응됨", mt: "All apps are adapted for Apple Silicon") }
    var noIntelApps: String { t("您的 Mac 上没有需要适配的 Intel 应用", en: "No Intel apps need adaptation on your Mac", zhHant: "您的 Mac 上沒有需要適配的 Intel 應用", ja: "Macに適応が必要なIntelアプリはありません", ko: "Mac에 적응이 필요한 Intel 앱이 없습니다", mt: "No Intel apps need adaptation on your Mac") }
    var needAdapt: String { t("需适配", en: "Needs Adaptation", zhHant: "需適配", ja: "要適応", ko: "적응 필요", mt: "Needs Adaptation") }
    var replaceBtn: String { t("替换", en: "Replace", zhHant: "替換", ja: "置換", ko: "교체", mt: "Replace") }
    var confirmUninstall: String { t("确认卸载", en: "Confirm Uninstall", zhHant: "確認解除安裝", ja: "アンインストール確認", ko: "제거 확인", mt: "Confirm Uninstall") }
    var replaceARMVersion: String { t("替换为 ARM 版本", en: "Replace with ARM Version", zhHant: "替換為 ARM 版本", ja: "ARM版に置換", ko: "ARM 버전으로 교체", mt: "Replace with ARM Version") }
    var uninstallBtn: String { t("卸载", en: "Uninstall", zhHant: "解除安裝", ja: "アンインストール", ko: "제거", mt: "Uninstall") }
    var confidence: String { t("置信度", en: "Confidence", zhHant: "置信度", ja: "信頼度", ko: "신뢰도", mt: "Confidence") }
    var unitAgent: String { t("个 Agent", en: " agents", zhHant: "個 Agent", ja: "Agent", ko: "개 Agent", mt: " agents") }
    var unitSession: String { t("个会话", en: " sessions", zhHant: "個會話", ja: "セッション", ko: "개 세션", mt: " sessions") }
    var recentLabel: String { t("最近", en: "Recent", zhHant: "最近", ja: "最近", ko: "최근", mt: "Recent") }
    var addAndScan: String { t("添加并扫描", en: "Add & Scan", zhHant: "新增並掃描", ja: "追加してスキャン", ko: "추가 후 스캔", mt: "Add & Scan") }
    var tabApps: String { t("应用", en: "Apps", zhHant: "應用", ja: "アプリ", ko: "앱", mt: "Apps") }
    var tabDeps: String { t("依赖", en: "Deps", zhHant: "依賴", ja: "依存", ko: "의존성", mt: "Deps") }
    var tabOther: String { t("其它", en: "Other", zhHant: "其它", ja: "その他", ko: "기타", mt: "Other") }
    var tabManual: String { t("手动", en: "Manual", zhHant: "手動", ja: "手動", ko: "수동", mt: "Manual") }
    var selectAgentToAdd: String { t("选择要添加的 Agent / APP / 工具", en: "Select Agent / App / Tool to add", zhHant: "選擇要新增的 Agent / APP / 工具", ja: "追加するAgent/アプリ/ツールを選択", ko: "추가할 Agent/앱/도구 선택", mt: "Select Agent / App / Tool to add") }
    var noMatchingApp: String { t("没有找到匹配的 APP", en: "No matching app found", zhHant: "沒有找到匹配的 APP", ja: "一致するアプリが見つかりません", ko: "일치하는 앱을 찾을 수 없음", mt: "No matching app found") }
    var alreadyAdded: String { t("已添加", en: "Already added", zhHant: "已新增", ja: "追加済み", ko: "추가됨", mt: "Already added") }
    var selectAppFromList: String { t("点击列表选择一个 APP", en: "Click list to select an app", zhHant: "點選列表選擇一個 APP", ja: "リストからアプリを選択", ko: "목록에서 앱을 선택하세요", mt: "Click list to select an app") }
    var confirmDeleteMsg: String { t("确定删除", en: "Confirm delete", zhHant: "確定刪除", ja: "削除の確認", ko: "삭제 확인", mt: "Confirm delete") }
    var releasable: String { t("可释放", en: "Releasable", zhHant: "可釋放", ja: "解放可能", ko: "해제 가능", mt: "Releasable") }
    var operationCol: String { t("操作", en: "Operation", zhHant: "操作", ja: "操作", ko: "작업", mt: "Operation") }
    var instructionCol: String { t("指令", en: "Instruction", zhHant: "指令", ja: "コマンド", ko: "명령", mt: "Instruction") }
    var targetPathCol: String { t("目标路径", en: "Target Path", zhHant: "目標路徑", ja: "対象パス", ko: "대상 경로", mt: "Target Path") }
    var projectCol: String { t("项目", en: "Project", zhHant: "專案", ja: "プロジェクト", ko: "프로젝트", mt: "Project") }
    var detailCol: String { t("详情", en: "Detail", zhHant: "詳情", ja: "詳細", ko: "상세", mt: "Detail") }
    var localScanSubtitle: String { t("扫描系统缓存、日志等已知可清理目录", en: "Scan known cleanable directories like system caches and logs", zhHant: "掃描系統快取、日誌等已知可清理目錄", ja: "システムキャッシュやログ等の既知のクリーンアップ可能ディレクトリをスキャン", ko: "시스템 캐시, 로그 등 알려진 정리 가능 디렉토리 스캔", mt: "Scan known cleanable directories like system caches and logs") }
    var aiScanSubtitle: String { t("大模型补充发现本地规则遗漏的清理项", en: "AI supplements local rules to find missed items", zhHant: "大模型補充發現本地規則遺漏的清理項", ja: "AIがローカルルールで見落としたクリーンアップ項目を補完", ko: "AI가 로컬 규칙에서 누락된 정리 항목을 보완", mt: "AI supplements local rules to find missed items") }
    var enhancedScanSubtitle: String { t("本地 + AI 双重检测，覆盖最全面", en: "Local + AI dual detection, most comprehensive coverage", zhHant: "本地 + AI 雙重檢測，覆蓋最全面", ja: "ローカル+AIの二重検出、最も包括的なカバレッジ", ko: "로컬 + AI 이중 감지, 가장 포괄적인 커버리지", mt: "Local + AI dual detection, most comprehensive coverage") }

    var navMigration: String { t("适配检测", en: "Adaptation Check", zhHant: "適配檢測", ja: "適応チェック", ko: "적응 확인", mt: "Adaptation Check") }
    var subMigration: String { t("Apple Silicon 架构适配", en: "Apple Silicon Architecture Adaptation", zhHant: "Apple Silicon 架構適配", ja: "Apple Siliconアーキテクチャ適応", ko: "Apple Silicon 아키텍처 적응", mt: "Apple Silicon Architecture Adaptation") }
    var processHelp: String { t("进程: ", en: "Process: ", zhHant: "程序: ", ja: "プロセス: ", ko: "프로세스: ", mt: "Process: ") }
    var openInFinder: String { t("在 Finder 中打开", en: "Open in Finder", zhHant: "在 Finder 中開啟", ja: "Finderで開く", ko: "Finder에서 열기", mt: "Open in Finder") }
    var opWrite: String { t("写入", en: "Write", zhHant: "寫入", ja: "書き込み", ko: "쓰기", mt: "Write") }
    var opEdit: String { t("编辑", en: "Edit", zhHant: "編輯", ja: "編集", ko: "편집", mt: "Edit") }
    var opRead2: String { t("读取", en: "Read", zhHant: "讀取", ja: "読み取り", ko: "읽기", mt: "Read") }
    var opDelete2: String { t("删除", en: "Delete", zhHant: "刪除", ja: "削除", ko: "삭제", mt: "Delete") }
    var opExec: String { t("执行命令", en: "Execute", zhHant: "執行命令", ja: "コマンド実行", ko: "명령 실행", mt: "Execute") }
    var opSearch: String { t("搜索", en: "Search", zhHant: "搜尋", ja: "検索", ko: "검색", mt: "Search") }
    var opOpen: String { t("打开", en: "Open", zhHant: "開啟", ja: "開く", ko: "열기", mt: "Open") }
    var opClose: String { t("关闭", en: "Close", zhHant: "關閉", ja: "閉じる", ko: "닫기", mt: "Close") }
    var opDialogue: String { t("对话", en: "Chat", zhHant: "對話", ja: "チャット", ko: "채팅", mt: "Chat") }
    var opAction: String { t("操作", en: "Action", zhHant: "操作", ja: "操作", ko: "작업", mt: "Action") }
    var opNew: String { t("新增", en: "New", zhHant: "新增", ja: "新規", ko: "새로 만들기", mt: "New") }
    var opSave: String { t("保存", en: "Save", zhHant: "儲存", ja: "保存", ko: "저장", mt: "Save") }
    var unknownAgent: String { t("未知", en: "Unknown", zhHant: "未知", ja: "不明", ko: "알 수 없음", mt: "Unknown") }
    var timesUnit: String { t("次", en: "times", zhHant: "次", ja: "回", ko: "회", mt: "times") }
    var unitItems: String { t("个", en: "items", zhHant: "個", ja: "件", ko: "개", mt: "items") }
    var apiConfigInvalid: String { t("API 配置无效", en: "Invalid API configuration", zhHant: "API 配置無效", ja: "API設定が無効", ko: "API 설정이 유효하지 않음", mt: "Invalid API configuration") }
    var apiRequestFailed: String { t("API 请求失败", en: "API request failed", zhHant: "API 請求失敗", ja: "APIリクエスト失敗", ko: "API 요청 실패", mt: "API request failed") }
    var aiFormatError: String { t("AI 返回格式异常", en: "AI response format error", zhHant: "AI 返回格式異常", ja: "AI応答形式エラー", ko: "AI 응답 형식 오류", mt: "AI response format error") }
    var requestFailed: String { t("请求失败", en: "Request failed", zhHant: "請求失敗", ja: "リクエスト失敗", ko: "요청 실패", mt: "Request failed") }
    var successCount: String { t("成功", en: "Success", zhHant: "成功", ja: "成功", ko: "성공", mt: "Success") }
    var failCount: String { t("失败", en: "Failed", zhHant: "失敗", ja: "失敗", ko: "실패", mt: "Failed") }
    var scanningDisk: String { t("正在扫描磁盘...", en: "Scanning disk...", zhHant: "正在掃描磁碟...", ja: "ディスクをスキャン中...", ko: "디스크 스캔 중...", mt: "Scanning disk...") }
    var scanningApps: String { t("扫描应用程序...", en: "Scanning applications...", zhHant: "掃描應用程式...", ja: "アプリケーションをスキャン中...", ko: "애플리케이션 스캔 중...", mt: "Scanning applications...") }
    var scanningDocs: String { t("扫描文稿...", en: "Scanning documents...", zhHant: "掃描文稿...", ja: "ドキュメントをスキャン中...", ko: "문서 스캔 중...", mt: "Scanning documents...") }
    var calcSystemData: String { t("计算系统数据...", en: "Calculating system data...", zhHant: "計算系統資料...", ja: "システムデータを計算中...", ko: "시스템 데이터 계산 중...", mt: "Calculating system data...") }
    var scanningOther: String { t("扫描其它...", en: "Scanning other...", zhHant: "掃描其它...", ja: "その他をスキャン中...", ko: "기타 스캔 중...", mt: "Scanning other...") }
    var appNameApps: String { t("应用程序", en: "Applications", zhHant: "應用程式", ja: "アプリケーション", ko: "애플리케이션", mt: "Applications") }
    var appNameDocs: String { t("文稿", en: "Documents", zhHant: "文稿", ja: "ドキュメント", ko: "문서", mt: "Documents") }
    var appNameSystem: String { t("系统数据", en: "System Data", zhHant: "系統資料", ja: "システムデータ", ko: "시스템 데이터", mt: "System Data") }
    var appNameOther: String { t("其它", en: "Other", zhHant: "其它", ja: "その他", ko: "기타", mt: "Other") }
    var gettingHardwareInfo: String { t("正在获取硬件信息...", en: "Getting hardware info...", zhHant: "正在獲取硬體資訊...", ja: "ハードウェア情報を取得中...", ko: "하드웨어 정보 가져오는 중...", mt: "Getting hardware info...") }
    var downloadingUpdateFmt: String { t("正在下载更新", en: "Downloading update", zhHant: "正在下載更新", ja: "アップデートをダウンロード中", ko: "업데이트 다운로드 중", mt: "Downloading update") }
    var storageAlert: String { t("存储警报", en: "Storage Alert", zhHant: "儲存警報", ja: "ストレージアラート", ko: "저장소 알림", mt: "Storage Alert") }
    var alertThresholdLabel: String { t("警报阈值", en: "Alert Threshold", zhHant: "警報閾值", ja: "アラートしきい値", ko: "알림 임계값", mt: "Alert Threshold") }
    var remainingLabel: String { t("剩余", en: "Remaining", zhHant: "剩餘", ja: "残り", ko: "남은", mt: "Remaining") }
    var thresholdLabel: String { t("阈值", en: "Threshold", zhHant: "閾值", ja: "しきい値", ko: "임계값", mt: "Threshold") }
    var opMonitorLabel: String { t("操作监控", en: "Operation Monitor", zhHant: "操作監控", ja: "操作モニター", ko: "작업 모니터", mt: "Operation Monitor") }
    var opStatsLabel: String { t("操作统计", en: "Operation Stats", zhHant: "操作統計", ja: "操作統計", ko: "작업 통계", mt: "Operation Stats") }
    var monitoringLabel: String { t("监控中", en: "Monitoring", zhHant: "監控中", ja: "モニタリング中", ko: "모니터링 중", mt: "Monitoring") }
    var notEnabledLabel: String { t("未启用", en: "Not Enabled", zhHant: "未啟用", ja: "未有効", ko: "미활성화", mt: "Not Enabled") }
    var totalOpsLabel: String { t("总操作", en: "Total Ops", zhHant: "總操作", ja: "合計操作", ko: "총 작업", mt: "Total Ops") }
    var todayLabel: String { t("今日", en: "Today", zhHant: "今日", ja: "今日", ko: "오늘", mt: "Today") }
    var hourLabel: String { t("1小时", en: "1 Hour", zhHant: "1小時", ja: "1時間", ko: "1시간", mt: "1 Hour") }
    var agentActivityLabel: String { t("Agent 活跃度", en: "Agent Activity", zhHant: "Agent 活躍度", ja: "Agent アクティビティ", ko: "Agent 활동", mt: "Agent Activity") }
    var noOpRecordsLabel: String { t("暂无操作记录", en: "No Operation Records", zhHant: "暫無操作記錄", ja: "操作記録なし", ko: "작업 기록 없음", mt: "No Operation Records") }
    var opTypeDistLabel: String { t("操作类型分布", en: "Operation Types", zhHant: "操作型別分佈", ja: "操作タイプ分布", ko: "작업 유형 분포", mt: "Operation Types") }
    var recentOpsLabel: String { t("最近操作", en: "Recent Operations", zhHant: "最近操作", ja: "最近の操作", ko: "최근 작업", mt: "Recent Operations") }
    var recordsUnit: String { t("条", en: "records", zhHant: "條", ja: "件", ko: "건", mt: "records") }
    var startMonitorHint2: String { t("开启监控后将自动记录 Agent 操作", en: "Agent operations will be recorded once monitoring starts", zhHant: "開啟監控後將自動記錄 Agent 操作", ja: "モニタリング開始後、Agentの操作を自動記録します", ko: "모니터링 시작 후 Agent 작업을 자동 기록합니다", mt: "Agent operations will be recorded once monitoring starts") }
    var permissionExpired: String { t("需要授权 Agent 数据目录，才能读取历史命令、审计记录并继续实时监控", en: "Authorize agent data folders to read command history, audit records, and continue live monitoring.", zhHant: "需要授權 Agent 資料目錄，才能讀取歷史命令、審計記錄並繼續即時監控", ja: "コマンド履歴、監査記録、リアルタイム監視を有効にするにはAgentデータフォルダの許可が必要です。", ko: "명령 기록, 감사 기록, 실시간 모니터링을 위해 Agent 데이터 폴더 권한이 필요합니다.", mt: "Authorize agent data folders to read command history, audit records, and continue live monitoring.") }
    var reauthorize: String { t("重新授权", en: "Re-authorize", zhHant: "重新授權", ja: "再認証", ko: "다시 인증", mt: "Re-authorize") }
    var selectMonitorDirs: String { t("请选择主目录或 Agent 数据目录（例如 ~/.codex、~/.claude，也可按住 ⌘ 多选需要监控的项目目录）", en: "Select your Home folder or agent data folders such as ~/.codex and ~/.claude. Hold ⌘ to select multiple project folders.", zhHant: "請選擇主目錄或 Agent 資料目錄（例如 ~/.codex、~/.claude，也可按住 ⌘ 多選需要監控的專案目錄）", ja: "ホームフォルダ、または ~/.codex や ~/.claude などのAgentデータフォルダを選択してください。⌘キーで複数のプロジェクトフォルダも選択できます。", ko: "홈 폴더 또는 ~/.codex, ~/.claude 같은 Agent 데이터 폴더를 선택하세요. ⌘ 키로 여러 프로젝트 폴더를 선택할 수 있습니다.", mt: "Select your Home folder or agent data folders such as ~/.codex and ~/.claude. Hold ⌘ to select multiple project folders.") }
    var totalCount: String { t("总次数", en: "Total", zhHant: "總次數", ja: "合計", ko: "총횟수", mt: "Total") }
    var todayCount: String { t("当日", en: "Today", zhHant: "當日", ja: "今日", ko: "오늘", mt: "Today") }
    var lastCalledBy: String { t("调用者", en: "Called by", zhHant: "調用者", ja: "呼出元", ko: "호출자", mt: "Called by") }
    var batchDeleteDesc: String { t("在指定时间窗口内删除文件数超过此阈值时触发告警", en: "Alert when files deleted within the time window exceed this threshold", zhHant: "在指定時間窗口內刪除檔案數超過此閾值時觸發告警", ja: "指定時間内に削除されたファイル数がこの閾値を超えた時にアラート", ko: "지정된 시간 내 삭제 파일 수가 이 임계값을 초과하면 알림", mt: "Alert when files deleted within the time window exceed this threshold") }
    var batchModifyDesc: String { t("在指定时间窗口内修改文件数超过此阈值时触发告警", en: "Alert when files modified within the time window exceed this threshold", zhHant: "在指定時間窗口內修改檔案數超過此閾值時觸發告警", ja: "指定時間内に変更されたファイル数がこの閾値を超えた時にアラート", ko: "지정된 시간 내 수정 파일 수가 이 임계값을 초과하면 알림", mt: "Alert when files modified within the time window exceed this threshold") }
    var timeWindowDesc: String { t("批量操作告警的统计时间窗口（秒）", en: "Time window (seconds) for counting batch operations", zhHant: "批量操作告警的統計時間窗口（秒）", ja: "一括操作アラートの集計時間枠（秒）", ko: "일괄 작업 알림의 통계 시간 범위(초)", mt: "Time window (seconds) for counting batch operations") }
    var alertCooldownDesc: String { t("同一类型告警的最小间隔时间，避免频繁告警", en: "Minimum interval between same-type alerts to avoid spam", zhHant: "同一類型告警的最小間隔時間，避免頻繁告警", ja: "同じタイプのアラートの最小間隔時間", ko: "동일 유형 알림의 최소 간격 시간", mt: "Minimum interval between same-type alerts to avoid spam") }
    var sensitiveFileDesc: String { t("检测AI Agent对敏感文件（密钥、证书、配置等）的访问操作", en: "Detect AI Agent access to sensitive files (keys, certs, configs, etc.)", zhHant: "檢測AI Agent對敏感檔案（密鑰、證書、配置等）的存取操作", ja: "AIエージェントによる機密ファイル（鍵、証明書、設定など）へのアクセスを検出", ko: "AI 에이전트의 민감한 파일(키, 인증서, 설정 등) 접근 감지", mt: "Detect AI Agent access to sensitive files (keys, certs, configs, etc.)") }
    var sensitiveContentDesc: String { t("检测AI Agent执行的高风险命令（如rm -rf、chmod 777等）", en: "Detect high-risk commands executed by AI Agents (e.g., rm -rf, chmod 777)", zhHant: "檢測AI Agent執行的高風險命令（如rm -rf、chmod 777等）", ja: "AIエージェントによる高リスクコマンド（rm -rf、chmod 777など）を検出", ko: "AI 에이전트의 고위험 명령(rm -rf, chmod 777 등) 감지", mt: "Detect high-risk commands executed by AI Agents (e.g., rm -rf, chmod 777)") }
    var processAlertDesc: String { t("当检测到新的AI Agent进程启动时发送通知", en: "Send notification when a new AI Agent process is detected", zhHant: "當檢測到新的AI Agent進程啟動時發送通知", ja: "新しいAIエージェントプロセスを検出した時に通知", ko: "새로운 AI 에이전트 프로세스 감지 시 알림", mt: "Send notification when a new AI Agent process is detected") }
    var protectedDirDesc: String { t("监控受保护目录中的文件操作，未经授权的访问将触发告警", en: "Monitor file operations in protected directories; unauthorized access triggers alerts", zhHant: "監控受保護目錄中的檔案操作，未經授權的存取將觸發告警", ja: "保護対象ディレクトリのファイル操作を監視し、不正アクセス時にアラート", ko: "보호된 디렉토리의 파일 작업 모니터링, 무단 접근 시 알림", mt: "Monitor file operations in protected directories; unauthorized access triggers alerts") }
    var notificationDesc: String { t("启用系统通知推送告警信息", en: "Enable system notifications for alert messages", zhHant: "啟用系統通知推送告警資訊", ja: "アラートメッセージのシステム通知を有効化", ko: "알림 메시지에 대한 시스템 알림 활성화", mt: "Enable system notifications for alert messages") }
    var doNotDisturbDesc: String { t("开启后暂停所有告警通知，监控仍继续记录", en: "Pause all alert notifications; monitoring continues recording in background", zhHant: "開啟後暫停所有告警通知，監控仍繼續記錄", ja: "すべてのアラート通知を一時停止（監視は記録を継続）", ko: "모든 알림 일시정지, 모니터링은 계속 기록됨", mt: "Pause all alert notifications; monitoring continues recording in background") }
    var hour: String { t("时", en: "Hour", zhHant: "時", ja: "時間", ko: "시간", mt: "Hour") }
    var pauseMonitorLabel: String { t("暂停监控", en: "Pause Monitoring", zhHant: "暫停監控", ja: "モニタリング一時停止", ko: "모니터링 일시정지", mt: "Pause Monitoring") }
    var startMonitorLabel: String { t("开始监控", en: "Start Monitoring", zhHant: "開始監控", ja: "モニタリング開始", ko: "모니터링 시작", mt: "Start Monitoring") }
    var closeAILabel: String { t("关闭 AI", en: "Close AI", zhHant: "關閉 AI", ja: "AIを閉じる", ko: "AI 닫기", mt: "Close AI") }
    var aiAnalysisLabel: String { t("AI分析", en: "AI Analysis", zhHant: "AI分析", ja: "AI分析", ko: "AI Analysis", mt: "AI Analysis") }
    var aiSelfLearning: String { t("AI 自学习 Agent 识别", en: "AI Self-Learning Agent Detection", zhHant: "AI 自學習 Agent 識別", ja: "AI 自學習 Agent 識別", ko: "AI 자기학습 Agent 감지", mt: "AI Self-Learning Agent Detection") }
    var aiSelfLearningDesc: String { t("调用 AI 自动分析未知进程和目录，持续优化 Agent 监控准确性", en: "Auto-analyze unknown processes and directories with AI to improve monitoring accuracy", zhHant: "呼叫 AI 自動分析未知程序和目錄，持續最佳化 Agent 監控準確性", ja: "AIで未知のプロセスとディレクトリを自動分析し、モニタリング精度を継続改善", ko: "AI로 알 수 없는 프로세스와 디렉토리를 자동 분석하여 모니터링 정확도 지속 개선", mt: "Auto-analyze unknown processes and directories with AI to improve monitoring accuracy") }
    var aiSelfLearningStatus: String { t("AI 自学习中...", en: "AI Self-Learning...", zhHant: "AI 自學習中...", ja: "AI自己学習中...", ko: "AI 자기학습 중...", mt: "AI Self-Learning...") }
    var viewFullLogLabel: String { t("查看完整记录", en: "View Full Log", zhHant: "檢視完整記錄", ja: "完全なログを表示", ko: "전체 기록 보기", mt: "View Full Log") }
    var cleanableRisk: String { t("可清理", en: "Cleanable", zhHant: "可清理", ja: "クリーンアップ可能", ko: "정리 가능", mt: "Cleanable") }
    var cautionRisk: String { t("谨慎清理", en: "Clean with Caution", zhHant: "謹慎清理", ja: "注意してクリーンアップ", ko: "주의하여 정리", mt: "Clean with Caution") }
    var keepRisk: String { t("保留", en: "Keep", zhHant: "保留", ja: "保持", ko: "유지", mt: "Keep") }
    var unknownRisk: String { t("未知", en: "Unknown", zhHant: "未知", ja: "不明", ko: "알 수 없음", mt: "Unknown") }
    var localSource: String { t("本地", en: "Local", zhHant: "本地", ja: "ローカル", ko: "로컬", mt: "Local") }
    var dirType: String { t("目录", en: "Directory", zhHant: "目錄", ja: "ディレクトリ", ko: "디렉토리", mt: "Directory") }
    var fileType: String { t("文件", en: "File", zhHant: "檔案", ja: "ファイル", ko: "파일", mt: "File") }
    var catPackageManager: String { t("包管理", en: "Package Manager", zhHant: "包管理", ja: "パッケージ管理", ko: "패키지 관리", mt: "Package Manager") }
    var catDev: String { t("开发", en: "Development", zhHant: "開發", ja: "開発", ko: "개발", mt: "Development") }
    var catApp: String { t("应用", en: "Apps", zhHant: "應用", ja: "アプリ", ko: "앱", mt: "Apps") }
    var catOther: String { t("其它", en: "Other", zhHant: "其它", ja: "その他", ko: "기타", mt: "Other") }
    var catBrowser: String { t("浏览器", en: "Browser", zhHant: "瀏覽器", ja: "ブラウザ", ko: "브라우저", mt: "Browser") }
    var catOffice: String { t("办公", en: "Office", zhHant: "辦公", ja: "オフィス", ko: "오피스", mt: "Office") }
    var catAIAgent: String { t("AI Agent", en: "AI Agent", zhHant: "AI Agent", ja: "AI Agent", ko: "AI Agent", mt: "AI Agent") }
    var catSystem: String { t("系统", en: "System", zhHant: "系統", ja: "システム", ko: "시스템", mt: "System") }
    var catSocial: String { t("社交", en: "Social", zhHant: "社交", ja: "ソーシャル", ko: "소셜", mt: "Social") }
    var catCLI: String { t("CLI", en: "CLI", zhHant: "CLI", ja: "CLI", ko: "CLI", mt: "CLI") }
    var uninstalling: String { t("正在卸载...", en: "Uninstalling...", zhHant: "正在解除安裝...", ja: "アンインストール中...", ko: "제거 중...", mt: "Uninstalling...") }
    var installing: String { t("正在安装...", en: "Installing...", zhHant: "正在安裝...", ja: "インストール中...", ko: "설치 중...", mt: "Installing...") }
    var completed: String { t("已完成", en: "Completed", zhHant: "已完成", ja: "完了", ko: "완료", mt: "Completed") }
    var failed: String { t("失败", en: "Failed", zhHant: "失敗", ja: "失敗", ko: "실패", mt: "Failed") }
    var unknownArch: String { t("未知", en: "Unknown", zhHant: "未知", ja: "不明", ko: "알 수 없음", mt: "Unknown") }
    var rosettaTrans: String { t("Rosetta 转译", en: "Rosetta Translation", zhHant: "Rosetta 轉譯", ja: "Rosetta翻訳", ko: "Rosetta 변환", mt: "Rosetta Translation") }
    var universalBinary: String { t("通用", en: "Universal", zhHant: "通用", ja: "ユニバーサル", ko: "유니버설", mt: "Universal") }
    var translated: String { t("转译", en: "Translated", zhHant: "轉譯", ja: "翻訳", ko: "변환", mt: "Translated") }
    var highConf: String { t("高", en: "High", zhHant: "高", ja: "高", ko: "높음", mt: "High") }
    var medConf: String { t("中", en: "Medium", zhHant: "中", ja: "中", ko: "중간", mt: "Medium") }
    var lowConf: String { t("低", en: "Low", zhHant: "低", ja: "低", ko: "낮음", mt: "Low") }
    var needAdaptLabel: String { t("需适配", en: "Needs Adaptation", zhHant: "需適配", ja: "要適応", ko: "적응 필요", mt: "Needs Adaptation") }
    var universalBinLabel: String { t("通用二进制", en: "Universal Binary", zhHant: "通用二進位制", ja: "ユニバーサルバイナリ", ko: "유니버설 바이너리", mt: "Universal Binary") }
    var armNative: String { t("ARM 原生", en: "ARM Native", zhHant: "ARM 原生", ja: "ARMネイティブ", ko: "ARM 네이티브", mt: "ARM Native") }
    var releasableSpace: String { t("可释放空间", en: "Releasable Space", zhHant: "可釋放空間", ja: "解放可能容量", ko: "해제 가능 공간", mt: "Releasable Space") }
    var showIntelOnly: String { t("仅显示需适配", en: "Show Intel Only", zhHant: "僅顯示需適配", ja: "Intel版のみ表示", ko: "Intel 버전만 표시", mt: "Show Intel Only") }
    var uninstallIntelAndInstallARM: String { t("卸载 Intel 版本并安装 ARM 版本", en: "Uninstall Intel version and install ARM version", zhHant: "解除安裝 Intel 版本並安裝 ARM 版本", ja: "Intel版をアンインストールしARM版をインストール", ko: "Intel 버전 제거 후 ARM 버전 설치", mt: "Uninstall Intel version and install ARM version") }
    var searchARMDownload: String { t("搜索 ARM 版本下载链接", en: "Search ARM version download link", zhHant: "搜尋 ARM 版本下載連結", ja: "ARM版ダウンロードリンクを検索", ko: "ARM 버전 다운로드 링크 검색", mt: "Search ARM version download link") }
    var searchPureARM: String { t("搜索纯 ARM 版本", en: "Search pure ARM version", zhHant: "搜尋純 ARM 版本", ja: "純ARM版を検索", ko: "순수 ARM 버전 검색", mt: "Search pure ARM version") }
    var openDownloadLink: String { t("打开下载链接", en: "Open download link", zhHant: "開啟下載連結", ja: "ダウンロードリンクを開く", ko: "다운로드 링크 열기", mt: "Open download link") }
    var uninstallLabel: String { t("卸载", en: "Uninstall", zhHant: "解除安裝", ja: "アンインストール", ko: "제거", mt: "Uninstall") }
    var detectingArchWithLipo: String { t("使用 lipo/file 命令检测每个应用的二进制架构", en: "Detecting binary architecture of each app using lipo/file commands", zhHant: "使用 lipo/file 命令檢測每個應用的二進位制架構", ja: "lipo/fileコマンドで各アプリのバイナリアーキテクチャを検出", ko: "lipo/file 명령으로 각 앱의 바이너리 아키텍처 감지", mt: "Detecting binary architecture of each app using lipo/file commands") }
    var appTypeApp: String { t("应用程序", en: "Application", zhHant: "應用程式", ja: "アプリケーション", ko: "애플리케이션", mt: "Application") }
    var appTypeCLI: String { t("命令行工具", en: "CLI Tool", zhHant: "命令列工具", ja: "CLIツール", ko: "CLI 도구", mt: "CLI Tool") }
    var appTypeHomebrew: String { t("Homebrew 包", en: "Homebrew Package", zhHant: "Homebrew 包", ja: "Homebrewパッケージ", ko: "Homebrew 패키지", mt: "Homebrew Package") }
    var appTypeFramework: String { t("框架/库", en: "Framework/Library", zhHant: "框架/庫", ja: "フレームワーク/ライブラリ", ko: "프레임워크/라이브러리", mt: "Framework/Library") }
    var minuteUnit: String { t("分钟", en: "min", zhHant: "分鐘", ja: "分", ko: "분", mt: "min") }
    var networkModeTitle: String { t("网络模式", en: "Network Mode", zhHant: "網路模式", ja: "ネットワークモード", ko: "네트워크 모드", mt: "Network Mode") }
    var networkModeDesc: String { t("选择更新检查和 AI 功能的网络模式", en: "Choose network mode for update checking and AI features", zhHant: "選擇更新檢查和 AI 功能的網路模式", ja: "アップデート確認とAI機能のネットワークモードを選択", ko: "업데이트 확인 및 AI 기능의 네트워크 모드 선택", mt: "Choose network mode for update checking and AI features") }
    var internetMode: String { t("互联网模式", en: "Internet Mode", zhHant: "網際網路模式", ja: "インターネットモード", ko: "인터넷 모드", mt: "Internet Mode") }
    var internetModeDesc: String { t("完整互联网访问，支持更新、AI 扫描和版本检查", en: "Full internet access for updates, AI scanning, and version checking", zhHant: "完整網際網路訪問，支援更新、AI 掃描和版本檢查", ja: "完全インターネットアクセス、アップデート・AIスキャン・バージョンチェック対応", ko: "전체 인터넷 접근, 업데이트·AI 스캔·버전 확인 지원", mt: "Full internet access for updates, AI scanning, and version checking") }
    var intranetMode: String { t("内网模式（离线）", en: "Intranet Mode (Offline)", zhHant: "內網模式（離線）", ja: "イントラネットモード（オフライン）", ko: "인트라넷 모드（오프라인）", mt: "Intranet Mode (Offline)") }
    var intranetModeDesc: String { t("无互联网访问，仅支持本地扫描，不检查更新", en: "No internet access. Local scanning only, no update checks", zhHant: "無網際網路訪問，僅支援本地掃描，不檢查更新", ja: "インターネットアクセスなし。ローカルスキャンのみ、アップデート確認なし", ko: "인터넷 접근 없음. 로컬 스캔만, 업데이트 확인 안 함", mt: "No internet access. Local scanning only, no update checks") }
    var updateChecking: String { t("更新检查", en: "Update Checking", zhHant: "更新檢查", ja: "アップデート確認", ko: "업데이트 확인", mt: "Update Checking") }
    var updateCheckingDesc: String { t("互联网模式下，可以检查已安装应用、AI Agent、CLI 工具和依赖的更新", en: "In internet mode, the app can check for updates of installed apps, AI agents, CLI tools, and dependencies.", zhHant: "網際網路模式下，可以檢查已安裝應用、AI Agent、CLI 工具和依賴的更新", ja: "インターネットモードでは、インストール済みアプリ・AI Agent・CLIツール・依存のアップデートを確認できます", ko: "인터넷 모드에서 설치된 앱, AI Agent, CLI 도구, 의존성의 업데이트를 확인할 수 있습니다", mt: "In internet mode, the app can check for updates of installed apps, AI agents, CLI tools, and dependencies.") }
    var movedToTrash: String { t("已移入回收站", en: "Moved to Trash", zhHant: "已移入回收站", ja: "ゴミ箱に移動しました", ko: "휴지통으로 이동됨", mt: "Moved to Trash") }
    var configureAPIKeyFirst: String { t("本地分析已启用", en: "Local analysis is enabled", zhHant: "本地分析已啟用", ja: "ローカル分析が有効です", ko: "로컬 분석이 활성화되었습니다", mt: "Local analysis is enabled") }
    var appReviewDemoStatus: String { t("正在生成 App Review 演示扫描结果...", en: "Generating App Review demo scan results...", zhHant: "正在生成 App Review 演示掃描結果...", ja: "App Review デモスキャン結果を生成中...", ko: "App Review 데모 스캔 결과 생성 중...", mt: "Generating App Review demo scan results...") }
    var collectingDirInfo: String { t("正在收集目录信息...", en: "Collecting directory info...", zhHant: "正在收集目錄資訊...", ja: "ディレクトリ情報を収集中...", ko: "디렉토리 정보 수집 중...", mt: "Collecting directory info...") }
    var callingAIAnalysis: String { t("正在调用大模型分析...", en: "Calling AI for analysis...", zhHant: "正在呼叫大模型分析...", ja: "AI分析を呼び出し中...", ko: "AI 분석 호출 중...", mt: "Calling AI for analysis...") }
    var aiScanComplete: String { t("AI 扫描完成，发现", en: "AI scan complete, found", zhHant: "AI 掃描完成，發現", ja: "AIスキャン完了、発見", ko: "AI 스캔 완료, 발견", mt: "AI scan complete, found") }
    var aiScanFailed: String { t("AI 扫描失败", en: "AI scan failed", zhHant: "AI 掃描失敗", ja: "AIスキャン失敗", ko: "AI 스캔 실패", mt: "AI scan failed") }
    var suggestLocalScan: String { t("建议使用本地扫描", en: "Suggest using local scan", zhHant: "建議使用本地掃描", ja: "ローカルスキャンの使用をお勧めします", ko: "로컬 스캔 사용 권장", mt: "Suggest using local scan") }
    var unknownError: String { t("未知错误", en: "Unknown error", zhHant: "未知錯誤", ja: "不明なエラー", ko: "알 수 없는 오류", mt: "Unknown error") }
    var userDir: String { t("用户目录", en: "User Directory", zhHant: "使用者目錄", ja: "ユーザーディレクトリ", ko: "사용자 디렉토리", mt: "User Directory") }
    var unknownDir: String { t("未知目录，删除前请确认其用途", en: "Unknown directory, confirm its purpose before deletion", zhHant: "未知目錄，刪除前請確認其用途", ja: "不明なディレクトリ、削除前に用途を確認してください", ko: "알 수 없는 디렉토리, 삭제 전 용도를 확인하세요", mt: "Unknown directory, confirm its purpose before deletion") }
    var menuBarMonitorClosed: String { t("菜单栏监控已关闭", en: "Menu bar monitor closed", zhHant: "選單欄監控已關閉", ja: "メニューバーモニターが閉じました", ko: "메뉴 막대 모니터가 종료됨", mt: "Menu bar monitor closed") }
    var searchLinkGenFailed: String { t("搜索链接生成失败", en: "Search link generation failed", zhHant: "搜尋連結生成失敗", ja: "検索リンクの生成に失敗", ko: "검색 링크 생성 실패", mt: "Search link generation failed") }
    var systemProcess: String { t("系统进程", en: "System Process", zhHant: "系統程序", ja: "システムプロセス", ko: "시스템 프로세스", mt: "System Process") }
    var processNotFound: String { t("未找到相关的运行中进程，请确认该程序正在运行", en: "No running process found, please confirm the program is running", zhHant: "未找到相關的執行中程序，請確認該程式正在執行", ja: "実行中のプロセスが見つかりません。プログラムが実行中か確認してください", ko: "실행 중인 프로세스를 찾을 수 없습니다. 프로그램이 실행 중인지 확인하세요", mt: "No running process found, please confirm the program is running") }
    var fileDeleted: String { t("文件已删除", en: "File deleted", zhHant: "檔案已刪除", ja: "ファイル削除済み", ko: "파일 삭제됨", mt: "File deleted") }
    var fileRead: String { t("文件已读取", en: "File read", zhHant: "檔案已讀取", ja: "ファイル読み取り済み", ko: "파일 읽음", mt: "File read") }
    var fileCreated: String { t("文件已创建", en: "File created", zhHant: "檔案已建立", ja: "ファイル作成済み", ko: "파일 생성됨", mt: "File created") }
    var contentChanged: String { t("内容已更改", en: "Content changed", zhHant: "內容已更改", ja: "コンテンツ変更済み", ko: "내용 변경됨", mt: "Content changed") }
    var fileModified: String { t("文件已修改", en: "File modified", zhHant: "檔案已修改", ja: "ファイル更新済み", ko: "파일 수정됨", mt: "File modified") }
    var fileTruncated: String { t("截断", en: "Truncated", zhHant: "截斷", ja: "切り詰め", ko: "잘림", mt: "Truncated") }
    var fileChangeCount: String { t("个文件变更", en: "files changed", zhHant: "個檔案變更", ja: "ファイル変更", ko: "파일 변경", mt: "files changed") }
    var allowedPaths: String { t("允许访问", en: "Allowed access", zhHant: "允許訪問", ja: "アクセス許可", ko: "접근 허용", mt: "Allowed access") }
    var pathsCount: String { t("个路径", en: "paths", zhHant: "個路徑", ja: "パス", ko: "경로", mt: "paths") }
    var currentSession: String { t("当前活跃会话", en: "Current active session", zhHant: "當前活躍會話", ja: "現在のアクティブセッション", ko: "현재 활성 세션", mt: "Current active session") }
    var historySession: String { t("历史会话", en: "History session", zhHant: "歷史會話", ja: "履歴セッション", ko: "과거 세션", mt: "History session") }
    var parsingOps: String { t("正在解析", en: "Parsing", zhHant: "正在解析", ja: "解析中", ko: "파싱 중", mt: "Parsing") }
    var opsRecord: String { t("的操作记录...", en: "operations...", zhHant: "的操作記錄...", ja: "の操作記録...", ko: "의 작업 기록...", mt: "operations...") }
    var colType: String { t("类型", en: "Type", zhHant: "型別", ja: "タイプ", ko: "유형", mt: "Type") }
    var colProcess: String { t("进程", en: "Process", zhHant: "程序", ja: "プロセス", ko: "프로세스", mt: "Process") }
    var colPID: String { t("PID", en: "PID", zhHant: "PID", ja: "PID", ko: "PID", mt: "PID") }
    var colBundleID: String { t("Bundle ID", en: "Bundle ID", zhHant: "Bundle ID", ja: "Bundle ID", ko: "Bundle ID", mt: "Bundle ID") }
    var colPath: String { t("路径", en: "Path", zhHant: "路徑", ja: "パス", ko: "경로", mt: "Path") }
    var colSize: String { t("大小", en: "Size", zhHant: "大小", ja: "サイズ", ko: "크기", mt: "Size") }
    var colName: String { t("名称", en: "Name", zhHant: "名稱", ja: "名前", ko: "이름", mt: "Name") }
    var colSource: String { t("来源", en: "Source", zhHant: "來源", ja: "ソース", ko: "소스", mt: "Source") }
    var configCol: String { t("配置", en: "Config", zhHant: "配置", ja: "設定", ko: "설정", mt: "Config") }
    var colApp: String { t("应用", en: "App", zhHant: "應用", ja: "アプリ", ko: "앱", mt: "App") }
    var colRisk: String { t("风险", en: "Risk", zhHant: "風險", ja: "リスク", ko: "위험", mt: "Risk") }
    var colDesc: String { t("说明", en: "Description", zhHant: "說明", ja: "説明", ko: "설명", mt: "Description") }
    var colAction: String { t("操作", en: "Action", zhHant: "操作", ja: "操作", ko: "작업", mt: "Action") }
    var detectingApp: String { t("检测", en: "Detecting", zhHant: "檢測", ja: "検出中", ko: "감지 중", mt: "Detecting") }
    var invalidDownloadLink: String { t("下载链接无效", en: "Invalid download link", zhHant: "下載連結無效", ja: "ダウンロードリンクが無効", ko: "다운로드 링크가 유효하지 않음", mt: "Invalid download link") }
    var saveDownloadFailed: String { t("保存下载文件失败", en: "Failed to save download file", zhHant: "儲存下載檔案失敗", ja: "ダウンロードファイルの保存に失敗", ko: "다운로드 파일 저장 실패", mt: "Failed to save download file") }
    var downloadFailed: String { t("下载失败", en: "Download failed", zhHant: "下載失敗", ja: "ダウンロード失敗", ko: "다운로드 실패", mt: "Download failed") }
    var installFileNotFound: String { t("安装文件不存在，请重新下载", en: "Install file not found, please re-download", zhHant: "安裝檔案不存在，請重新下載", ja: "インストールファイルが見つかりません。再ダウンロードしてください", ko: "설치 파일이 없습니다. 다시 다운로드하세요", mt: "Install file not found, please re-download") }
    var storageWarningTitle: String { t("⚠️ 存储空间不足", en: "⚠️ Low Storage", zhHant: "⚠️ 儲存空間不足", ja: "⚠️ ストレージ容量不足", ko: "⚠️ 저장 공간 부족", mt: "⚠️ Low Storage") }
    var storageWarningBody: String { t("磁盘剩余", en: "Disk remaining", zhHant: "磁碟剩餘", ja: "ディスク残り", ko: "디스크 남은", mt: "Disk remaining") }
    var suggestCleanNow: String { t("建议立即清理", en: "Clean up recommended", zhHant: "建議立即清理", ja: "クリーンアップをお勧めします", ko: "즉시 정리 권장", mt: "Clean up recommended") }
    var configureAIModel: String { t("请先配置 AI 模型（设置 → AI 设置）", en: "Please configure AI model (Settings → AI Settings)", zhHant: "請先配置 AI 模型（設定 → AI 設定）", ja: "AIモデルを先に設定してください（設定 → AI設定）", ko: "AI 모델을 먼저 설정하세요（설정 → AI 설정）", mt: "Please configure AI model (Settings → AI Settings)") }
    var collectingRawData: String { t("正在收集原始数据...", en: "Collecting raw data...", zhHant: "正在收集原始資料...", ja: "生データを収集中...", ko: "원본 데이터 수집 중...", mt: "Collecting raw data...") }
    var noMonitorData: String { t("暂无监控数据，请先启用 Agent 监控并等待文件操作产生", en: "No monitoring data, please enable Agent monitoring and wait for file operations", zhHant: "暫無監控資料，請先啟用 Agent 監控並等待檔案操作產生", ja: "モニタリングデータなし。Agentモニタリングを有効にしてファイル操作を待ってください", ko: "모니터링 데이터 없음. Agent 모니터링을 활성화하고 파일 작업을 기다려 주세요", mt: "No monitoring data, please enable Agent monitoring and wait for file operations") }
    var insufficientDataPrefix: String { t("监控数据不足（仅有", en: "Insufficient data (only", zhHant: "監控資料不足（僅有", ja: "モニタリングデータ不足（わずか", ko: "모니터링 데이터 부족（단", mt: "Insufficient data (only") }
    var continueMonitorRetry: String { t("条），继续监控后重试", en: "records), continue monitoring and retry", zhHant: "條），繼續監控後重試", ja: "件）、モニタリングを継続して再試行してください", ko: "건）, 모니터링을 계속한 후 재시도하세요", mt: "records), continue monitoring and retry") }
    var curationComplete: String { t("梳理完成：", en: "Curation complete: ", zhHant: "梳理完成：", ja: "整理完了：", ko: "정리 완료: ", mt: "Curation complete: ") }
    var unavailableInMacAppStoreBuild: String { t("Mac App Store 版本暂不可用", en: "Unavailable in Mac App Store build", zhHant: "Mac App Store 版本暫不可用", ja: "Mac App Store版では利用できません", ko: "Mac App Store 빌드에서는 사용할 수 없음", mt: "Unavailable in Mac App Store build") }
    var localAnalysisNoExternalAI: String { t("本地分析模式不会使用外部 AI 服务。", en: "Local analysis mode does not use external AI services.", zhHant: "本地分析模式不會使用外部 AI 服務。", ja: "ローカル分析モードでは外部AIサービスを使用しません。", ko: "로컬 분석 모드는 외부 AI 서비스를 사용하지 않습니다.", mt: "Local analysis mode does not use external AI services.") }
    func localMonitorReviewed(records: Int) -> String {
        t("本地监控已复核 \(records) 条记录，不会调用外部 AI 服务。",
          en: "Local monitor reviewed \(records) records without external AI services.",
          zhHant: "本地監控已覆核 \(records) 條記錄，不會呼叫外部 AI 服務。",
          ja: "ローカルモニターが \(records) 件の記録を確認しました。外部AIサービスは使用していません。",
          ko: "로컬 모니터가 \(records)개 기록을 검토했으며 외부 AI 서비스를 사용하지 않았습니다.",
          mt: "Local monitor reviewed \(records) records without external AI services.")
    }
    func localImpactSummary(appName: String, risk: String, type: String, isSafe: Bool) -> String {
        switch type {
        case "app":
            return t("本地：\(appName) 是已安装应用。AgentGuard 仅展示清单和缓存上下文；App Store 版本已禁用卸载操作。风险：\(risk)。",
                     en: "Local: \(appName) is an installed app. AgentGuard shows inventory and cache context only; uninstall actions are disabled in this App Store build. Risk: \(risk).",
                     zhHant: "本地：\(appName) 是已安裝應用。AgentGuard 僅展示清單和快取上下文；App Store 版本已停用解除安裝操作。風險：\(risk)。",
                     ja: "ローカル：\(appName) はインストール済みアプリです。AgentGuardは一覧とキャッシュ情報のみを表示し、このApp Store版ではアンインストール操作は無効です。リスク：\(risk)。",
                     ko: "로컬: \(appName)은 설치된 앱입니다. AgentGuard는 목록과 캐시 컨텍스트만 표시하며 이 App Store 빌드에서는 제거 작업이 비활성화되어 있습니다. 위험: \(risk).",
                     mt: "Local: \(appName) is an installed app. AgentGuard shows inventory and cache context only; uninstall actions are disabled in this App Store build. Risk: \(risk).")
        case "dependency":
            return t("本地：\(appName) 可能被项目依赖。请检查路径；除非确认没有项目依赖它，否则建议保留。风险：\(risk)。",
                     en: "Local: \(appName) may be required by projects. Review its path and keep it unless you are sure no project depends on it. Risk: \(risk).",
                     zhHant: "本地：\(appName) 可能被專案依賴。請檢查路徑；除非確認沒有專案依賴它，否則建議保留。風險：\(risk)。",
                     ja: "ローカル：\(appName) はプロジェクトに必要な可能性があります。パスを確認し、依存するプロジェクトがないと確信できる場合以外は保持してください。リスク：\(risk)。",
                     ko: "로컬: \(appName)은 프로젝트에 필요할 수 있습니다. 경로를 검토하고 의존하는 프로젝트가 없다고 확신할 때만 제거하세요. 위험: \(risk).",
                     mt: "Local: \(appName) may be required by projects. Review its path and keep it unless you are sure no project depends on it. Risk: \(risk).")
        default:
            if isSafe {
                return t("本地：\(appName) 看起来是缓存或临时数据。请先查看路径，确认后再移入废纸篓。",
                         en: "Local: \(appName) appears to be cache or temporary data. Move items to Trash only after reviewing the listed paths.",
                         zhHant: "本地：\(appName) 看起來是快取或暫存資料。請先查看路徑，確認後再移入垃圾桶。",
                         ja: "ローカル：\(appName) はキャッシュまたは一時データのようです。表示されたパスを確認してからゴミ箱に移動してください。",
                         ko: "로컬: \(appName)은 캐시 또는 임시 데이터로 보입니다. 표시된 경로를 검토한 뒤 휴지통으로 이동하세요.",
                         mt: "Local: \(appName) appears to be cache or temporary data. Move items to Trash only after reviewing the listed paths.")
            }
            return t("本地：请谨慎检查 \(appName) 后再清理。AgentGuard 会避免不可逆操作，并通过废纸篓保持可恢复。",
                     en: "Local: Review \(appName) carefully before cleanup. AgentGuard avoids irreversible actions and keeps cleanup recoverable through Trash.",
                     zhHant: "本地：請謹慎檢查 \(appName) 後再清理。AgentGuard 會避免不可逆操作，並透過垃圾桶保持可恢復。",
                     ja: "ローカル：クリーンアップ前に \(appName) を慎重に確認してください。AgentGuardは不可逆操作を避け、ゴミ箱経由で復元可能にします。",
                     ko: "로컬: 정리 전에 \(appName)을 신중히 검토하세요. AgentGuard는 되돌릴 수 없는 작업을 피하고 휴지통을 통해 복구 가능하게 유지합니다.",
                     mt: "Local: Review \(appName) carefully before cleanup. AgentGuard avoids irreversible actions and keeps cleanup recoverable through Trash.")
        }
    }
    var appUninstallDisabled: String { t("Mac App Store 版本已禁用应用卸载操作。", en: "App uninstall actions are disabled in the Mac App Store build.", zhHant: "Mac App Store 版本已停用應用解除安裝操作。", ja: "Mac App Store版ではアプリのアンインストール操作は無効です。", ko: "Mac App Store 빌드에서는 앱 제거 작업이 비활성화되어 있습니다.", mt: "App uninstall actions are disabled in the Mac App Store build.") }
    var fullUninstallDisabled: String { t("Mac App Store 版本已禁用完全卸载操作。", en: "Full uninstall actions are disabled in the Mac App Store build.", zhHant: "Mac App Store 版本已停用完全解除安裝操作。", ja: "Mac App Store版では完全アンインストール操作は無効です。", ko: "Mac App Store 빌드에서는 전체 제거 작업이 비활성화되어 있습니다.", mt: "Full uninstall actions are disabled in the Mac App Store build.") }
    var appResetDisabled: String { t("Mac App Store 版本已禁用应用重置操作。", en: "App reset actions are disabled in the Mac App Store build.", zhHant: "Mac App Store 版本已停用應用重置操作。", ja: "Mac App Store版ではアプリのリセット操作は無効です。", ko: "Mac App Store 빌드에서는 앱 재설정 작업이 비활성화되어 있습니다.", mt: "App reset actions are disabled in the Mac App Store build.") }
    var allInternalOps: String { t("条事件均在 agent 自身项目目录内，无对外部文件的操作", en: "events are all within the agent's own project directory, no external file operations", zhHant: "條事件均在 agent 自身專案目錄內，無對外部檔案的操作", ja: "件のイベントはすべてagent自身のプロジェクトディレクトリ内で、外部ファイルへの操作はありません", ko: "건의 이벤트가 모두 agent 자체 프로젝트 디렉토리 내에 있으며 외부 파일 작업이 없습니다", mt: "events are all within the agent's own project directory, no external file operations") }
    var allSystemOps: String { t("均为系统内部操作，未发现对外部文件的改动", en: "All are internal system operations, no external file changes detected", zhHant: "均為系統內部操作，未發現對外部檔案的改動", ja: "すべてシステム内部操作で、外部ファイルへの変更は検出されませんでした", ko: "모두 시스템 내부 작업이며 외부 파일 변경이 감지되지 않았습니다", mt: "All are internal system operations, no external file changes detected") }
    var identifiedAgentOps: String { t("识别到", en: "Identified", zhHant: "識別到", ja: "認識", ko: "인식", mt: "Identified") }
    var agentOpsRecords: String { t("条 Agent 操作", en: "Agent operations", zhHant: "條 Agent 操作", ja: "件のAgent操作", ko: "건의 Agent 작업", mt: "Agent operations") }
    var noProcessSnapshot: String { t("无进程快照——请确保 Agent 监控已启用，或重新启用后等待 30 秒再试", en: "No process snapshots—ensure Agent monitoring is enabled, or re-enable and wait 30 seconds", zhHant: "無程序快照——請確保 Agent 監控已啟用，或重新啟用後等待 30 秒再試", ja: "プロセススナップショットなし—Agentモニタリングが有効か確認、または再有効化して30秒待って再試行してください", ko: "프로세스 스냅샷 없음—Agent 모니터링이 활성화되어 있는지 확인하거나, 다시 활성화 후 30초 대기 후 재시도하세요", mt: "No process snapshots—ensure Agent monitoring is enabled, or re-enable and wait 30 seconds") }
    var aiConfigIncomplete: String { t("AI 配置不完整", en: "AI configuration incomplete", zhHant: "AI 配置不完整", ja: "AI設定が不完全", ko: "AI 설정이 불완전함", mt: "AI configuration incomplete") }
    var requestBuildFailed: String { t("请求构建失败", en: "Request build failed", zhHant: "請求構建失敗", ja: "リクエスト構築失敗", ko: "요청 빌드 실패", mt: "Request build failed") }
    var networkError: String { t("网络错误", en: "Network error", zhHant: "網路錯誤", ja: "ネットワークエラー", ko: "네트워크 오류", mt: "Network error") }
    var apiError: String { t("API 错误", en: "API error", zhHant: "API 錯誤", ja: "APIエラー", ko: "API 오류", mt: "API error") }
    var aiResponseFormatError: String { t("AI 响应格式错误", en: "AI response format error", zhHant: "AI 響應格式錯誤", ja: "AI応答形式エラー", ko: "AI 응답 형식 오류", mt: "AI response format error") }
    var networkRequestFailed: String { t("网络请求失败", en: "Network request failed", zhHant: "網路請求失敗", ja: "ネットワークリクエスト失敗", ko: "네트워크 요청 실패", mt: "Network request failed") }
    var aiNoJsonArray: String { t("AI 未返回 JSON 数组或对象", en: "AI did not return JSON array or object", zhHant: "AI 未返回 JSON 陣列或物件", ja: "AIがJSON配列またはオブジェクトを返しませんでした", ko: "AI가 JSON 배열 또는 객체를 반환하지 않음", mt: "AI did not return JSON array or object") }
    var updateInstallFailedMount: String { t("更新安装失败：无法挂载安装包", en: "Update install failed: cannot mount installer", zhHant: "更新安裝失敗：無法掛載安裝包", ja: "アップデートインストール失敗：インストーラーをマウントできません", ko: "업데이트 설치 실패: 설치 패키지를 마운트할 수 없음", mt: "Update install failed: cannot mount installer") }
    var updateInstallFailedApp: String { t("更新安装失败：安装包中未找到应用", en: "Update install failed: app not found in installer", zhHant: "更新安裝失敗：安裝包中未找到應用", ja: "アップデートインストール失敗：インストーラーにアプリが見つかりません", ko: "업데이트 설치 실패: 설치 패키지에서 앱을 찾을 수 없음", mt: "Update install failed: app not found in installer") }
    var updateInstallFailedCopy: String { t("更新安装失败：无法复制应用", en: "Update install failed: cannot copy app", zhHant: "更新安裝失敗：無法複製應用", ja: "アップデートインストール失敗：アプリをコピーできません", ko: "업데이트 설치 실패: 앱을 복사할 수 없음", mt: "Update install failed: cannot copy app") }
    var updateSuccess: String { t("已成功更新到最新版本", en: "Successfully updated to latest version", zhHant: "已成功更新到最新版本", ja: "最新バージョンへの更新に成功しました", ko: "최신 버전으로 업데이트 성공", mt: "Successfully updated to latest version") }
    var pleaseConfigureAPIKey: String { t("本地分析已启用", en: "Local analysis is enabled", zhHant: "本地分析已啟用", ja: "ローカル分析が有効です", ko: "로컬 분석이 활성화되었습니다", mt: "Local analysis is enabled") }
    var analyzingDots: String { t("🔄 分析中...", en: "🔄 Analyzing...", zhHant: "🔄 分析中...", ja: "🔄 分析中...", ko: "🔄 분석 중...", mt: "🔄 Analyzing...") }
    var invalidAPIUrl: String { t("❌ 无效的 API 地址", en: "❌ Invalid API URL", zhHant: "❌ 無效的 API 地址", ja: "❌ 無効なAPI URL", ko: "❌ 유효하지 않은 API URL", mt: "❌ Invalid API URL") }
    var invalidHttpResponse: String { t("❌ 无效的 HTTP 响应", en: "❌ Invalid HTTP response", zhHant: "❌ 無效的 HTTP 響應", ja: "❌ 無効なHTTPレスポンス", ko: "❌ 유효하지 않은 HTTP 응답", mt: "❌ Invalid HTTP response") }
    var aiModelFormatError: String { t("❌ 大模型返回格式错误", en: "❌ AI model response format error", zhHant: "❌ 大模型返回格式錯誤", ja: "❌ AIモデル応答形式エラー", ko: "❌ AI 모델 응답 형식 오류", mt: "❌ AI model response format error") }
    var analysisComplete: String { t("🤖 分析完成（详见原说明）", en: "🤖 Analysis complete (see original description)", zhHant: "🤖 分析完成（詳見原說明）", ja: "🤖 分析完了（元の説明を参照）", ko: "🤖 분석 완료（원래 설명 참조）", mt: "🤖 Analysis complete (see original description)") }
    var uninstallFailed: String { t("卸载失败", en: "Uninstall failed", zhHant: "解除安裝失敗", ja: "アンインストール失敗", ko: "제거 실패", mt: "Uninstall failed") }
    var systemPrefix: String { t("系统", en: "system", zhHant: "系統", ja: "システム", ko: "시스템", mt: "system") }
    var deleted: String { t("已删除", en: "Deleted", zhHant: "已刪除", ja: "削除済み", ko: "삭제됨", mt: "Deleted") }

    var navAgentGuard: String { t("Agent 守护", en: "Agent Guard", zhHant: "Agent 守護", ja: "Agentガード", ko: "Agent 가드", mt: "Agent Guard") }
    var subAgentGuard: String { t("AI Agent 安全监控与防护", en: "AI Agent Security Monitoring & Protection", zhHant: "AI Agent 安全監控與防護", ja: "AI Agentセキュリティモニタリング＆プロテクション", ko: "AI Agent 보안 모니터링 및 보호", mt: "AI Agent Security Monitoring & Protection") }
    var navAgentCenter: String { t("Agent 中心", en: "Agent Center", zhHant: "Agent 中心", ja: "Agentセンター", ko: "Agent 센터", mt: "Agent Center") }
    var subAgentCenter: String { t("Agent 集成、Hook 与会话管理", en: "Agent integrations, hooks, and sessions", zhHant: "Agent 整合、Hook 與會話管理", ja: "Agent統合、Hook、セッション管理", ko: "Agent 통합, Hook 및 세션 관리", mt: "Agent integrations, hooks, and sessions") }
    var agentCenterIntegrations: String { t("集成", en: "Integrations", zhHant: "整合", ja: "統合", ko: "통합", mt: "Integrations") }
    var agentCenterApprovals: String { t("审批", en: "Approvals", zhHant: "審批", ja: "承認", ko: "승인", mt: "Approvals") }
    var agentCenterRefresh: String { t("刷新", en: "Refresh", zhHant: "重新整理", ja: "更新", ko: "새로고침", mt: "Refresh") }
    var agentCenterInstallAll: String { t("安装全部 Hook", en: "Install All Hooks", zhHant: "安裝全部 Hook", ja: "すべてのHookをインストール", ko: "모든 Hook 설치", mt: "Install All Hooks") }
    var agentCenterSearch: String { t("搜索 Agent...", en: "Search agents...", zhHant: "搜尋 Agent...", ja: "Agentを検索...", ko: "Agent 검색...", mt: "Search agents...") }
    var agentCenterAll: String { t("全部", en: "All", zhHant: "全部", ja: "すべて", ko: "전체", mt: "All") }
    var agentCenterActive: String { t("已接入", en: "Active", zhHant: "已接入", ja: "接続済み", ko: "활성", mt: "Active") }
    var agentCenterInstalled: String { t("已安装", en: "Installed", zhHant: "已安裝", ja: "インストール済み", ko: "설치됨", mt: "Installed") }
    var agentCenterUnavailable: String { t("未发现", en: "Not Found", zhHant: "未發現", ja: "未検出", ko: "찾을 수 없음", mt: "Not Found") }
    var agentCenterInstallHook: String { t("安装 Hook", en: "Install Hook", zhHant: "安裝 Hook", ja: "Hookをインストール", ko: "Hook 설치", mt: "Install Hook") }
    var agentCenterRemoveHook: String { t("移除 Hook", en: "Remove Hook", zhHant: "移除 Hook", ja: "Hookを削除", ko: "Hook 제거", mt: "Remove Hook") }
    var agentCenterConnect: String { t("接入", en: "Connect", zhHant: "接入", ja: "接続", ko: "연결", mt: "Connect") }
    var agentCenterDisconnect: String { t("移除接入", en: "Disconnect", zhHant: "移除接入", ja: "接続解除", ko: "연결 해제", mt: "Disconnect") }
    var agentCenterConnecting: String { t("处理中", en: "Working", zhHant: "處理中", ja: "処理中", ko: "처리 중", mt: "Working") }
    var agentCenterHookHint: String { t("接入会写入该 Agent 的 Hook 配置，用于捕获权限请求、问题和计划审批。", en: "Connect writes this agent's hook config so permission requests, questions, and plan approvals can be captured.", zhHant: "接入會寫入該 Agent 的 Hook 配置，用於捕獲權限請求、問題和計劃審批。", ja: "接続すると、このAgentのHook設定を書き込み、権限リクエスト、質問、計画承認を取得します。", ko: "연결은 이 Agent의 Hook 설정을 기록해 권한 요청, 질문, 계획 승인을 캡처합니다.", mt: "Connect writes this agent's hook config so permission requests, questions, and plan approvals can be captured.") }
    var agentCenterHookStatus: String { t("Hook 状态", en: "Hook Status", zhHant: "Hook 狀態", ja: "Hook状態", ko: "Hook 상태", mt: "Hook Status") }
    var agentCenterHookUnsupported: String { t("当前 Agent 暂不支持 Hook 接入", en: "This agent does not support hook connection yet.", zhHant: "目前 Agent 暫不支援 Hook 接入", ja: "このAgentはまだHook接続に対応していません。", ko: "이 Agent는 아직 Hook 연결을 지원하지 않습니다.", mt: "This agent does not support hook connection yet.") }
    var agentCenterUnsupported: String { t("暂不支持", en: "Unsupported", zhHant: "暫不支援", ja: "未対応", ko: "미지원", mt: "Unsupported") }
    var agentCenterPending: String { t("待审批", en: "Pending", zhHant: "待審批", ja: "保留中", ko: "대기", mt: "Pending") }
    var agentCenterHistory: String { t("历史", en: "History", zhHant: "歷史", ja: "履歴", ko: "기록", mt: "History") }
    var agentCenterNoApprovals: String { t("暂无待审批事项", en: "No pending approvals", zhHant: "暫無待審批事項", ja: "保留中の承認はありません", ko: "대기 중인 승인이 없습니다", mt: "No pending approvals") }
    var agentCenterNoApprovalHistory: String { t("暂无审批历史", en: "No approval history", zhHant: "暫無審批歷史", ja: "承認履歴はありません", ko: "승인 기록이 없습니다", mt: "No approval history") }
    var agentCenterApprovalHistoryHint: String { t("这里会保留最近的 Agent 会话和已处理审批，方便回看。", en: "Recent agent sessions and handled approvals stay here for review.", zhHant: "這裡會保留最近的 Agent 會話和已處理審批，方便回看。", ja: "最近のAgentセッションと処理済み承認をここで確認できます。", ko: "최근 Agent 세션과 처리된 승인을 여기에서 다시 볼 수 있습니다.", mt: "Recent agent sessions and handled approvals stay here for review.") }
    var agentCenterPendingApprovalsHint: String { t("安装 Hook 后，权限请求、问题和计划审批会保留在 Agent Center 中处理。", en: "After hooks are installed, permission requests, questions, and plan approvals stay in Agent Center.", zhHant: "安裝 Hook 後，權限請求、問題和計劃審批會保留在 Agent Center 中處理。", ja: "Hookをインストールすると、権限リクエスト、質問、計画承認はAgent Centerに表示されます。", ko: "Hook 설치 후 권한 요청, 질문, 계획 승인은 Agent Center에 유지됩니다.", mt: "After hooks are installed, permission requests, questions, and plan approvals stay in Agent Center.") }
    var agentCenterPermission: String { t("权限请求", en: "Permission", zhHant: "權限請求", ja: "権限", ko: "권한", mt: "Permission") }
    var agentCenterQuestion: String { t("问题", en: "Question", zhHant: "問題", ja: "質問", ko: "질문", mt: "Question") }
    var agentCenterTextReply: String { t("文字回复", en: "Text Reply", zhHant: "文字回覆", ja: "テキスト返信", ko: "텍스트 답변", mt: "Text Reply") }
    var agentCenterPlan: String { t("计划审批", en: "Plan", zhHant: "計劃審批", ja: "計画", ko: "계획", mt: "Plan") }
    var agentCenterPhaseReady: String { t("就绪", en: "Ready", zhHant: "就緒", ja: "準備完了", ko: "준비됨", mt: "Ready") }
    var agentCenterPhaseIdle: String { t("空闲", en: "Idle", zhHant: "閒置", ja: "アイドル", ko: "대기 중", mt: "Idle") }
    var agentCenterPhaseRunning: String { t("运行中", en: "Running", zhHant: "執行中", ja: "実行中", ko: "실행 중", mt: "Running") }
    var agentCenterPhaseCompacting: String { t("压缩中", en: "Compacting", zhHant: "壓縮中", ja: "圧縮中", ko: "압축 중", mt: "Compacting") }
    var agentCenterPhaseDone: String { t("已完成", en: "Done", zhHant: "已完成", ja: "完了", ko: "완료", mt: "Done") }
    var agentCenterPhaseError: String { t("异常", en: "Error", zhHant: "異常", ja: "エラー", ko: "오류", mt: "Error") }
    var agentCenterPhaseInterrupted: String { t("已中断", en: "Interrupted", zhHant: "已中斷", ja: "中断済み", ko: "중단됨", mt: "Interrupted") }
    var agentCenterActiveSummary: String { t("已接入", en: "active", zhHant: "已接入", ja: "接続済み", ko: "활성", mt: "active") }
    var agentCenterInstalledSummary: String { t("已安装", en: "installed", zhHant: "已安裝", ja: "インストール済み", ko: "설치됨", mt: "installed") }
    var agentCenterAvailableSummary: String { t("可用", en: "available", zhHant: "可用", ja: "利用可能", ko: "사용 가능", mt: "available") }
    var agentApprovalNext: String { t("下一个", en: "Next", zhHant: "下一個", ja: "次", ko: "다음", mt: "Next") }
    var agentApprovalShowSessions: String { t("查看审批会话", en: "Show approval sessions", zhHant: "查看審批會話", ja: "承認セッションを表示", ko: "승인 세션 보기", mt: "Show approval sessions") }
    var agentPermissionRequest: String { t("权限请求", en: "Permission Request", zhHant: "權限請求", ja: "権限リクエスト", ko: "권한 요청", mt: "Permission Request") }
    var agentWantsToUseTool: String { t("想使用", en: "wants to use", zhHant: "想使用", ja: "が使用しようとしています", ko: "사용하려고 합니다", mt: "wants to use") }
    var agentChanges: String { t("变更", en: "Changes", zhHant: "變更", ja: "変更", ko: "변경", mt: "Changes") }
    var agentOptions: String { t("选项", en: "Options", zhHant: "選項", ja: "オプション", ko: "옵션", mt: "Options") }
    var agentCustomReply: String { t("文字回复", en: "Text Reply", zhHant: "文字回覆", ja: "テキスト返信", ko: "텍스트 답변", mt: "Text Reply") }
    var agentCustomReplyPlaceholder: String { t("输入补充说明或新的任务指令", en: "Type extra notes or a new task instruction", zhHant: "輸入補充說明或新的任務指令", ja: "補足説明または新しいタスク指示を入力", ko: "추가 설명 또는 새 작업 지시를 입력", mt: "Type extra notes or a new task instruction") }
    var agentSendReply: String { t("发送回复", en: "Send Reply", zhHant: "傳送回覆", ja: "返信を送信", ko: "답변 보내기", mt: "Send Reply") }
    var agentNoSessionSelected: String { t("未选择会话", en: "No session selected", zhHant: "未選擇會話", ja: "セッション未選択", ko: "세션이 선택되지 않음", mt: "No session selected") }
    var agentSessionDetail: String { t("会话详情", en: "Session Detail", zhHant: "會話詳情", ja: "セッション詳細", ko: "세션 상세", mt: "Session Detail") }
    var agentGuardReady: String { t("AgentGuard 就绪", en: "AgentGuard Ready", zhHant: "AgentGuard 就緒", ja: "AgentGuard 準備完了", ko: "AgentGuard 준비됨", mt: "AgentGuard Ready") }
    var agentDetailOverview: String { t("概览", en: "Overview", zhHant: "概覽", ja: "概要", ko: "개요", mt: "Overview") }
    var agentDetailTools: String { t("工具", en: "Tools", zhHant: "工具", ja: "ツール", ko: "도구", mt: "Tools") }
    var agentDetailSubagents: String { t("子 Agent", en: "Subagents", zhHant: "子 Agent", ja: "サブAgent", ko: "하위 Agent", mt: "Subagents") }
    var agentDetailEvents: String { t("事件", en: "Events", zhHant: "事件", ja: "イベント", ko: "이벤트", mt: "Events") }
    var agentProject: String { t("项目", en: "Project", zhHant: "專案", ja: "プロジェクト", ko: "프로젝트", mt: "Project") }
    var agentDuration: String { t("耗时", en: "Duration", zhHant: "耗時", ja: "所要時間", ko: "소요 시간", mt: "Duration") }
    var agentPhase: String { t("阶段", en: "Phase", zhHant: "階段", ja: "フェーズ", ko: "단계", mt: "Phase") }
    var agentTokenUsage: String { t("Token 用量", en: "Token Usage", zhHant: "Token 用量", ja: "Token使用量", ko: "Token 사용량", mt: "Token Usage") }
    var agentTokenInput: String { t("输入", en: "Input", zhHant: "輸入", ja: "入力", ko: "입력", mt: "Input") }
    var agentTokenOutput: String { t("输出", en: "Output", zhHant: "輸出", ja: "出力", ko: "출력", mt: "Output") }
    var agentTokenCacheRead: String { t("缓存读取", en: "Cache Read", zhHant: "快取讀取", ja: "キャッシュ読取", ko: "캐시 읽기", mt: "Cache Read") }
    var agentTokenCacheCreate: String { t("缓存写入", en: "Cache Create", zhHant: "快取寫入", ja: "キャッシュ作成", ko: "캐시 생성", mt: "Cache Create") }
    var agentRateLimits: String { t("限额", en: "Rate Limits", zhHant: "限額", ja: "レート制限", ko: "사용 한도", mt: "Rate Limits") }
    var agentContextWindow: String { t("上下文窗口", en: "Context Window", zhHant: "上下文視窗", ja: "コンテキストウィンドウ", ko: "컨텍스트 창", mt: "Context Window") }
    var agentTotalInput: String { t("总输入", en: "Total Input", zhHant: "總輸入", ja: "総入力", ko: "총 입력", mt: "Total Input") }
    var agentTotalOutput: String { t("总输出", en: "Total Output", zhHant: "總輸出", ja: "総出力", ko: "총 출력", mt: "Total Output") }
    var agentWindowSize: String { t("窗口大小", en: "Window Size", zhHant: "視窗大小", ja: "ウィンドウサイズ", ko: "창 크기", mt: "Window Size") }
    func agentContextUsed(_ percent: Int) -> String { t("已使用 \(percent)%", en: "\(percent)% used", zhHant: "已使用 \(percent)%", ja: "\(percent)% 使用済み", ko: "\(percent)% 사용됨", mt: "\(percent)% used") }
    var agentNoToolExecutions: String { t("暂无工具执行记录", en: "No tool executions recorded", zhHant: "暫無工具執行記錄", ja: "ツール実行記録はありません", ko: "도구 실행 기록 없음", mt: "No tool executions recorded") }
    var agentNoSubagents: String { t("暂无子 Agent", en: "No subagents spawned", zhHant: "暫無子 Agent", ja: "サブAgentはありません", ko: "하위 Agent 없음", mt: "No subagents spawned") }
    var agentRawEventsHint: String { t("原始 Hook 事件日志可在会话中心查看", en: "Raw hook event log available in Session Center", zhHant: "原始 Hook 事件日誌可在會話中心查看", ja: "Raw Hookイベントログはセッションセンターで確認できます", ko: "원시 Hook 이벤트 로그는 세션 센터에서 볼 수 있습니다", mt: "Raw hook event log available in Session Center") }
    var agentPhaseReady: String { t("就绪", en: "Ready", zhHant: "就緒", ja: "準備完了", ko: "준비됨", mt: "Ready") }
    var agentPhaseIdle: String { t("空闲", en: "Idle", zhHant: "閒置", ja: "アイドル", ko: "유휴", mt: "Idle") }
    var agentPhaseProcessing: String { t("运行中", en: "Running", zhHant: "執行中", ja: "実行中", ko: "실행 중", mt: "Running") }
    var agentPhaseCompacting: String { t("压缩中", en: "Compacting", zhHant: "壓縮中", ja: "圧縮中", ko: "압축 중", mt: "Compacting") }
    var agentPhaseDone: String { t("已完成", en: "Done", zhHant: "已完成", ja: "完了", ko: "완료", mt: "Done") }
    var agentPhaseError: String { t("错误", en: "Error", zhHant: "錯誤", ja: "エラー", ko: "오류", mt: "Error") }
    var agentPhaseInterrupted: String { t("已中断", en: "Interrupted", zhHant: "已中斷", ja: "中断済み", ko: "중단됨", mt: "Interrupted") }
    func agentSeconds(_ value: Int) -> String { t("\(value)秒", en: "\(value)s", zhHant: "\(value)秒", ja: "\(value)秒", ko: "\(value)초", mt: "\(value)s") }
    func agentMinutes(_ value: Int) -> String { t("\(value)分", en: "\(value)m", zhHant: "\(value)分", ja: "\(value)分", ko: "\(value)분", mt: "\(value)m") }
    func agentHours(_ value: Int) -> String { t("\(value)小时", en: "\(value)h", zhHant: "\(value)小時", ja: "\(value)時間", ko: "\(value)시간", mt: "\(value)h") }
    func agentDays(_ value: Int) -> String { t("\(value)天", en: "\(value)d", zhHant: "\(value)天", ja: "\(value)日", ko: "\(value)일", mt: "\(value)d") }
    func agentAgo(_ value: String) -> String { t("\(value)前", en: "\(value) ago", zhHant: "\(value)前", ja: "\(value)前", ko: "\(value) 전", mt: "\(value) ago") }
    var agentAlwaysAllowTool: String { t("始终允许此工具", en: "Always allow this tool", zhHant: "始終允許此工具", ja: "このツールを常に許可", ko: "이 도구 항상 허용", mt: "Always allow this tool") }
    var agentAllow: String { t("允许", en: "Allow", zhHant: "允許", ja: "許可", ko: "허용", mt: "Allow") }
    var agentDeny: String { t("拒绝", en: "Deny", zhHant: "拒絕", ja: "拒否", ko: "거부", mt: "Deny") }
    var agentPermissionYes: String { t("是", en: "Yes", zhHant: "是", ja: "はい", ko: "예", mt: "Yes") }
    var agentPermissionYesAlways: String { t("是（以后允许）", en: "Yes (always allow)", zhHant: "是（以後允許）", ja: "はい（今後も許可）", ko: "예(앞으로 허용)", mt: "Yes (always allow)") }
    var agentPermissionNo: String { t("否", en: "No", zhHant: "否", ja: "いいえ", ko: "아니요", mt: "No") }
    var agentPermissionNoWithReason: String { t("否（填理由或其它命令）", en: "No (add reason or instruction)", zhHant: "否（填理由或其它命令）", ja: "いいえ（理由または別指示）", ko: "아니요(이유 또는 다른 명령 입력)", mt: "No (add reason or instruction)") }
    var agentPermissionSubmitNoWithReason: String { t("提交否（理由或其它命令）", en: "Submit No", zhHant: "提交否（理由或其它命令）", ja: "いいえを送信", ko: "아니요 제출", mt: "Submit No") }
    var agentDenyReasonOrInstruction: String { t("拒绝理由或补充任务指令", en: "Deny reason or follow-up instruction", zhHant: "拒絕理由或補充任務指令", ja: "拒否理由または追加タスク指示", ko: "거부 이유 또는 추가 작업 지시", mt: "Deny reason or follow-up instruction") }
    var agentDenyReasonPlaceholder: String { t("可填写拒绝原因，也可以写新的任务指令", en: "Add a reason, or type a new task instruction", zhHant: "可填寫拒絕原因，也可以寫新的任務指令", ja: "理由、または新しいタスク指示を入力", ko: "이유를 추가하거나 새 작업 지시를 입력", mt: "Add a reason, or type a new task instruction") }
    var agentExternalApprovalTitle: String { t("外部审批请求", en: "External approval request", zhHant: "外部審批請求", ja: "外部承認リクエスト", ko: "외부 승인 요청", mt: "External approval request") }
    var agentExternalApprovalHint: String { t("请回到来源 Agent 完成批准或拒绝。AgentGuard 会在这里保留提醒和历史。", en: "Return to the source agent to approve or reject it. AgentGuard keeps the reminder and history here.", zhHant: "請回到來源 Agent 完成批准或拒絕。AgentGuard 會在這裡保留提醒和歷史。", ja: "元のAgentに戻って承認または拒否してください。AgentGuardはここに通知と履歴を残します。", ko: "원본 Agent로 돌아가 승인 또는 거부하세요. AgentGuard는 여기에서 알림과 기록을 유지합니다.", mt: "Return to the source agent to approve or reject it. AgentGuard keeps the reminder and history here.") }
    var agentOpenSourceApp: String { t("打开来源应用", en: "Open Source App", zhHant: "開啟來源應用", ja: "元アプリを開く", ko: "원본 앱 열기", mt: "Open Source App") }
    var agentMarkHandled: String { t("标记已处理", en: "Mark Handled", zhHant: "標記已處理", ja: "処理済みにする", ko: "처리됨 표시", mt: "Mark Handled") }
    var agentDesignPreview: String { t("设计稿预览", en: "Design Preview", zhHant: "設計稿預覽", ja: "デザインプレビュー", ko: "디자인 미리보기", mt: "Design Preview") }
    var agentOpenImage: String { t("打开图片", en: "Open Image", zhHant: "開啟圖片", ja: "画像を開く", ko: "이미지 열기", mt: "Open Image") }
    var agentRevealImage: String { t("在 Finder 中显示", en: "Reveal in Finder", zhHant: "在 Finder 中顯示", ja: "Finderで表示", ko: "Finder에서 보기", mt: "Reveal in Finder") }
    var agentImageMissing: String { t("图片文件不可访问", en: "Image file is not accessible", zhHant: "圖片檔案不可存取", ja: "画像ファイルにアクセスできません", ko: "이미지 파일에 접근할 수 없음", mt: "Image file is not accessible") }
    var agentReject: String { t("拒绝", en: "Reject", zhHant: "拒絕", ja: "却下", ko: "거부", mt: "Reject") }
    var agentApprove: String { t("批准", en: "Approve", zhHant: "批准", ja: "承認", ko: "승인", mt: "Approve") }
    var agentModifyApprove: String { t("修改并批准", en: "Modify & Approve", zhHant: "修改並批准", ja: "修正して承認", ko: "수정 후 승인", mt: "Modify & Approve") }
    var agentDecideLater: String { t("稍后处理", en: "Decide Later", zhHant: "稍後處理", ja: "後で判断", ko: "나중에 결정", mt: "Decide Later") }
    var agentFeedbackPlaceholder: String { t("反馈信息（可选）", en: "Feedback message (optional)", zhHant: "回饋資訊（可選）", ja: "フィードバック（任意）", ko: "피드백 메시지(선택)", mt: "Feedback message (optional)") }
    var agentRequestedPermissions: String { t("请求的权限", en: "Requested Permissions", zhHant: "請求的權限", ja: "要求された権限", ko: "요청된 권한", mt: "Requested Permissions") }
    var agentCancel: String { t("取消", en: "Cancel", zhHant: "取消", ja: "キャンセル", ko: "취소", mt: "Cancel") }
    var agentSubmit: String { t("提交", en: "Submit", zhHant: "提交", ja: "送信", ko: "제출", mt: "Submit") }
    var add: String { t("添加", en: "Add", zhHant: "新增", ja: "追加", ko: "추가", mt: "Add") }
    var guardDashboard: String { t("守护概览", en: "Guard Dashboard", zhHant: "守護概覽", ja: "ガード概要", ko: "가드 개요", mt: "Guard Dashboard") }
    var alertCenter: String { t("告警中心", en: "Alert Center", zhHant: "告警中心", ja: "アラートセンター", ko: "알림 센터", mt: "Alert Center") }
    var alertRules: String { t("告警规则", en: "Alert Rules", zhHant: "告警規則", ja: "アラートルール", ko: "알림 규칙", mt: "Alert Rules") }
    var protectedDirs: String { t("保护目录", en: "Protected Dirs", zhHant: "保護目錄", ja: "保護ディレクトリ", ko: "보호 디렉토리", mt: "Protected Dirs") }
    var trendChart: String { t("趋势图", en: "Trends", zhHant: "趨勢圖", ja: "トレンド", ko: "트렌드", mt: "Trends") }
    var exportData: String { t("导出数据", en: "Export Data", zhHant: "匯出資料", ja: "データエクスポート", ko: "데이터 내보내기", mt: "Export Data") }
    var auditReport: String { t("审计报告", en: "Audit Report", zhHant: "審計報告", ja: "監査レポート", ko: "감사 보고서", mt: "Audit Report") }
    var processLifecycle: String { t("进程生命周期", en: "Process Lifecycle", zhHant: "程序生命週期", ja: "プロセスライフサイクル", ko: "프로세스 수명 주기", mt: "Process Lifecycle") }
    var processLaunch: String { t("启动", en: "Launch", zhHant: "啟動", ja: "起動", ko: "시작", mt: "Launch") }
    var processExit: String { t("退出", en: "Exit", zhHant: "退出", ja: "終了", ko: "종료", mt: "Exit") }
    var batchDeleteAlertTitle: String { t("批量删除告警", en: "Batch Delete Alert", zhHant: "批次刪除告警", ja: "一括削除アラート", ko: "대량 삭제 알림", mt: "Batch Delete Alert") }
    var batchDeleteAlertMsg: String { t("在短时间内检测到大量文件删除操作", en: "Mass file deletion detected in a short period", zhHant: "在短時間內檢測到大量檔案刪除操作", ja: "短期間に大量のファイル削除操作を検出", ko: "짧은 시간에 대량의 파일 삭제 작업 감지", mt: "Mass file deletion detected in a short period") }
    var batchModifyAlertTitle: String { t("批量修改告警", en: "Batch Modify Alert", zhHant: "批次修改告警", ja: "一括変更アラート", ko: "대량 수정 알림", mt: "Batch Modify Alert") }
    var batchModifyAlertMsg: String { t("在短时间内检测到大量文件修改操作", en: "Mass file modification detected in a short period", zhHant: "在短時間內檢測到大量檔案修改操作", ja: "短期間に大量のファイル変更操作を検出", ko: "짧은 시간에 대량의 파일 수정 작업 감지", mt: "Mass file modification detected in a short period") }
    var sensitiveFileAlertTitle: String { t("敏感文件访问", en: "Sensitive File Access", zhHant: "敏感檔案訪問", ja: "機密ファイルアクセス", ko: "민감 파일 접근", mt: "Sensitive File Access") }
    var sensitiveFileAlertMsg: String { t("Agent 访问了敏感文件", en: "Agent accessed a sensitive file", zhHant: "Agent 訪問了敏感檔案", ja: "Agentが機密ファイルにアクセスしました", ko: "Agent가 민감 파일에 접근했습니다", mt: "Agent accessed a sensitive file") }
    var sensitiveContentAlertTitle: String { t("敏感内容检测", en: "Sensitive Content Detected", zhHant: "敏感內容檢測", ja: "機密コンテンツ検出", ko: "민감 콘텐츠 감지", mt: "Sensitive Content Detected") }
    var sensitiveContentAlertMsg: String { t("Agent 修改了包含敏感信息的文件", en: "Agent modified a file containing sensitive information", zhHant: "Agent 修改了包含敏感資訊的檔案", ja: "Agentが機密情報を含むファイルを変更しました", ko: "Agent가 민감 정보가 포함된 파일을 수정했습니다", mt: "Agent modified a file containing sensitive information") }
    var protectedDirAlertTitle: String { t("保护目录访问", en: "Protected Directory Access", zhHant: "保護目錄訪問", ja: "保護ディレクトリアクセス", ko: "보호 디렉토리 접근", mt: "Protected Directory Access") }
    var protectedDirAlertMsg: String { t("Agent 在保护目录中执行了操作", en: "Agent performed an operation in a protected directory", zhHant: "Agent 在保護目錄中執行了操作", ja: "Agentが保護ディレクトリで操作を実行しました", ko: "Agent가 보호 디렉토리에서 작업을 실행했습니다", mt: "Agent performed an operation in a protected directory") }
    var processLaunchAlertTitle: String { t("Agent 进程启动", en: "Agent Process Launched", zhHant: "Agent 程序啟動", ja: "Agentプロセス起動", ko: "Agent 프로세스 시작", mt: "Agent Process Launched") }
    var processLaunchAlertMsg: String { t("检测到新的 Agent 进程", en: "New agent process detected", zhHant: "檢測到新的 Agent 程序", ja: "新しいAgentプロセスを検出", ko: "새로운 Agent 프로세스 감지", mt: "New agent process detected") }
    var batchDeleteThreshold: String { t("批量删除阈值", en: "Batch Delete Threshold", zhHant: "批次刪除閾值", ja: "一括削除しきい値", ko: "대량 삭제 임계값", mt: "Batch Delete Threshold") }
    var batchModifyThreshold: String { t("批量修改阈值", en: "Batch Modify Threshold", zhHant: "批次修改閾值", ja: "一括変更しきい値", ko: "대량 수정 임계값", mt: "Batch Modify Threshold") }
    var timeWindowSeconds: String { t("时间窗口(秒)", en: "Time Window (sec)", zhHant: "時間視窗(秒)", ja: "時間ウィンドウ（秒）", ko: "시간 창（초）", mt: "Time Window (sec)") }
    var alertCooldown: String { t("告警冷却(秒)", en: "Alert Cooldown (sec)", zhHant: "告警冷卻(秒)", ja: "アラートクールダウン（秒）", ko: "알림 쿨다운（초）", mt: "Alert Cooldown (sec)") }
    var enableSensitiveFile: String { t("启用敏感文件检测", en: "Enable Sensitive File Detection", zhHant: "啟用敏感檔案檢測", ja: "機密ファイル検出を有効化", ko: "민감 파일 감지 활성화", mt: "Enable Sensitive File Detection") }
    var enableSensitiveContent: String { t("启用敏感内容检测", en: "Enable Sensitive Content Detection", zhHant: "啟用敏感內容檢測", ja: "機密コンテンツ検出を有効化", ko: "민감 콘텐츠 감지 활성화", mt: "Enable Sensitive Content Detection") }
    var enableProcessAlert: String { t("启用进程启停告警", en: "Enable Process Lifecycle Alert", zhHant: "啟用程序啟停告警", ja: "プロセスライフサイクルアラートを有効化", ko: "프로세스 수명 주기 알림 활성화", mt: "Enable Process Lifecycle Alert") }
    var enableProtectedDir: String { t("启用保护目录告警", en: "Enable Protected Dir Alert", zhHant: "啟用保護目錄告警", ja: "保護ディレクトリアラートを有効化", ko: "보호 디렉토리 알림 활성화", mt: "Enable Protected Dir Alert") }
    var enableNotification: String { t("启用系统通知", en: "Enable Notifications", zhHant: "啟用系統通知", ja: "通知を有効化", ko: "알림 활성화", mt: "Enable Notifications") }
    var doNotDisturb: String { t("免打扰模式", en: "Do Not Disturb", zhHant: "免打擾模式", ja: "非通知モード", ko: "방해 금지 모드", mt: "Do Not Disturb") }
    var enableSounds: String { t("启用声音", en: "Enable Sounds", zhHant: "啟用聲音", ja: "サウンドを有効化", ko: "소리 활성화", mt: "Enable Sounds") }
    var soundVolume: String { t("音量：", en: "Volume:", zhHant: "音量：", ja: "音量：", ko: "볼륨:", mt: "Volume:") }
    var muteDuringDND: String { t("免打扰时静音", en: "Mute during Do Not Disturb", zhHant: "免打擾時靜音", ja: "非通知モード中はミュート", ko: "방해 금지 중 음소거", mt: "Mute during Do Not Disturb") }
    var eventSounds: String { t("事件声音", en: "Event Sounds", zhHant: "事件聲音", ja: "イベントサウンド", ko: "이벤트 소리", mt: "Event Sounds") }
    var soundNone: String { t("无", en: "None", zhHant: "無", ja: "なし", ko: "없음", mt: "None") }
    var soundPop: String { t("轻弹", en: "Pop", zhHant: "輕彈", ja: "ポップ", ko: "팝", mt: "Pop") }
    var soundWhoosh: String { t("掠过", en: "Whoosh", zhHant: "掠過", ja: "フーシュ", ko: "휙", mt: "Whoosh") }
    var soundTick: String { t("滴答", en: "Tick", zhHant: "滴答", ja: "チック", ko: "틱", mt: "Tick") }
    var soundTock: String { t("嗒声", en: "Tock", zhHant: "嗒聲", ja: "タック", ko: "톡", mt: "Tock") }
    var soundPing: String { t("提示", en: "Ping", zhHant: "提示", ja: "ピン", ko: "핑", mt: "Ping") }
    var soundChime: String { t("铃音", en: "Chime", zhHant: "鈴音", ja: "チャイム", ko: "차임", mt: "Chime") }
    var soundSuccess: String { t("成功", en: "Success", zhHant: "成功", ja: "成功", ko: "성공", mt: "Success") }
    var soundError: String { t("错误", en: "Error", zhHant: "錯誤", ja: "エラー", ko: "오류", mt: "Error") }
    var soundPause: String { t("暂停", en: "Pause", zhHant: "暫停", ja: "一時停止", ko: "일시 정지", mt: "Pause") }
    var soundBell: String { t("铃声", en: "Bell", zhHant: "鈴聲", ja: "ベル", ko: "벨", mt: "Bell") }
    var soundSwoosh: String { t("划过", en: "Swoosh", zhHant: "劃過", ja: "スウッシュ", ko: "슈웅", mt: "Swoosh") }
    var eventSessionStart: String { t("会话开始", en: "Session Start", zhHant: "會話開始", ja: "セッション開始", ko: "세션 시작", mt: "Session Start") }
    var eventSessionEnd: String { t("会话结束", en: "Session End", zhHant: "會話結束", ja: "セッション終了", ko: "세션 종료", mt: "Session End") }
    var eventToolStart: String { t("工具开始", en: "Tool Start", zhHant: "工具開始", ja: "ツール開始", ko: "도구 시작", mt: "Tool Start") }
    var eventToolEnd: String { t("工具结束", en: "Tool End", zhHant: "工具結束", ja: "ツール終了", ko: "도구 종료", mt: "Tool End") }
    var eventPermissionRequest: String { t("权限请求", en: "Permission Request", zhHant: "權限請求", ja: "権限リクエスト", ko: "권한 요청", mt: "Permission Request") }
    var eventPlanApproval: String { t("计划审批", en: "Plan Approval", zhHant: "計劃審批", ja: "計画承認", ko: "계획 승인", mt: "Plan Approval") }
    var eventTaskComplete: String { t("任务完成", en: "Task Complete", zhHant: "任務完成", ja: "タスク完了", ko: "작업 완료", mt: "Task Complete") }
    var eventInterrupt: String { t("中断", en: "Interrupt", zhHant: "中斷", ja: "中断", ko: "중단", mt: "Interrupt") }
    var eventNotification: String { t("通知", en: "Notification", zhHant: "通知", ja: "通知", ko: "알림", mt: "Notification") }
    var eventSubagentStart: String { t("子 Agent 开始", en: "Subagent Start", zhHant: "子 Agent 開始", ja: "サブAgent開始", ko: "하위 Agent 시작", mt: "Subagent Start") }
    var eventSubagentEnd: String { t("子 Agent 结束", en: "Subagent End", zhHant: "子 Agent 結束", ja: "サブAgent終了", ko: "하위 Agent 종료", mt: "Subagent End") }
    var eventShellExecution: String { t("Shell 执行", en: "Shell Execution", zhHant: "Shell 執行", ja: "Shell実行", ko: "Shell 실행", mt: "Shell Execution") }
    var eventRateLimit: String { t("频率限制", en: "Rate Limit", zhHant: "頻率限制", ja: "レート制限", ko: "속도 제한", mt: "Rate Limit") }
    var enableWebhookNotifications: String { t("启用 Webhook 通知", en: "Enable Webhook Notifications", zhHant: "啟用 Webhook 通知", ja: "Webhook通知を有効化", ko: "Webhook 알림 활성화", mt: "Enable Webhook Notifications") }
    var webhookURL: String { t("Webhook 地址", en: "Webhook URL", zhHant: "Webhook 位址", ja: "Webhook URL", ko: "Webhook URL", mt: "Webhook URL") }
    var webhookSecretOptional: String { t("密钥（可选）", en: "Secret (optional)", zhHant: "密鑰（可選）", ja: "シークレット（任意）", ko: "시크릿(선택)", mt: "Secret (optional)") }
    var webhookSecretPlaceholder: String { t("HMAC 密钥", en: "HMAC secret key", zhHant: "HMAC 密鑰", ja: "HMACシークレットキー", ko: "HMAC 시크릿 키", mt: "HMAC secret key") }
    var webhookRetryCount: String { t("重试次数", en: "Retry Count", zhHant: "重試次數", ja: "再試行回数", ko: "재시도 횟수", mt: "Retry Count") }
    var webhookTimeoutSeconds: String { t("超时（秒）", en: "Timeout (seconds)", zhHant: "逾時（秒）", ja: "タイムアウト（秒）", ko: "시간 초과(초)", mt: "Timeout (seconds)") }
    var remoteHosts: String { t("远程主机", en: "Remote Hosts", zhHant: "遠端主機", ja: "リモートホスト", ko: "원격 호스트", mt: "Remote Hosts") }
    var noRemoteHosts: String { t("暂无远程主机", en: "No remote hosts configured", zhHant: "暫無遠端主機", ja: "リモートホスト未設定", ko: "구성된 원격 호스트 없음", mt: "No remote hosts configured") }
    var noRemoteHostsHint: String { t("添加 SSH 主机以监控远程 Agent 会话", en: "Add an SSH host to monitor remote agent sessions", zhHant: "新增 SSH 主機以監控遠端 Agent 會話", ja: "SSHホストを追加してリモートAgentセッションを監視", ko: "SSH 호스트를 추가해 원격 Agent 세션을 모니터링하세요", mt: "Add an SSH host to monitor remote agent sessions") }
    var security: String { t("安全", en: "Security", zhHant: "安全", ja: "セキュリティ", ko: "보안", mt: "Security") }
    var securityLevel: String { t("安全级别", en: "Security Level", zhHant: "安全級別", ja: "セキュリティレベル", ko: "보안 수준", mt: "Security Level") }
    var securityPermissive: String { t("宽松", en: "Permissive", zhHant: "寬鬆", ja: "許可優先", ko: "허용 우선", mt: "Permissive") }
    var securityStandard: String { t("标准", en: "Standard", zhHant: "標準", ja: "標準", ko: "표준", mt: "Standard") }
    var securityStrict: String { t("严格", en: "Strict", zhHant: "嚴格", ja: "厳格", ko: "엄격", mt: "Strict") }
    var securityPermissiveDesc: String { t("允许所有远程 Agent 活动，无需验证", en: "All remote agent activity is allowed without verification", zhHant: "允許所有遠端 Agent 活動，無需驗證", ja: "すべてのリモートAgent活動を検証なしで許可します", ko: "모든 원격 Agent 활동을 검증 없이 허용합니다", mt: "All remote agent activity is allowed without verification") }
    var securityStandardDesc: String { t("允许受信主机和已验证指纹，其它需要审批", en: "Trusted hosts and verified fingerprints are allowed; others require approval", zhHant: "允許受信主機和已驗證指紋，其它需要審批", ja: "信頼済みホストと検証済みフィンガープリントを許可し、その他は承認が必要です", ko: "신뢰된 호스트와 검증된 지문은 허용되고 나머지는 승인이 필요합니다", mt: "Trusted hosts and verified fingerprints are allowed; others require approval") }
    var securityStrictDesc: String { t("仅允许明确受信且指纹有效的主机", en: "Only explicitly trusted hosts with valid fingerprints are allowed", zhHant: "僅允許明確受信且指紋有效的主機", ja: "明示的に信頼され有効なフィンガープリントを持つホストのみ許可します", ko: "명시적으로 신뢰되고 유효한 지문이 있는 호스트만 허용합니다", mt: "Only explicitly trusted hosts with valid fingerprints are allowed") }
    var autoConnectKnownHosts: String { t("自动连接已知主机", en: "Auto-connect to known hosts", zhHant: "自動連接已知主機", ja: "既知のホストへ自動接続", ko: "알려진 호스트 자동 연결", mt: "Auto-connect to known hosts") }
    var online: String { t("在线", en: "Online", zhHant: "在線", ja: "オンライン", ko: "온라인", mt: "Online") }
    var offline: String { t("离线", en: "Offline", zhHant: "離線", ja: "オフライン", ko: "오프라인", mt: "Offline") }
    var addRemoteHost: String { t("添加远程主机", en: "Add Remote Host", zhHant: "新增遠端主機", ja: "リモートホストを追加", ko: "원격 호스트 추가", mt: "Add Remote Host") }
    var hostPlaceholder: String { t("主机（IP 或域名）", en: "Host (IP or hostname)", zhHant: "主機（IP 或網域）", ja: "ホスト（IPまたはホスト名）", ko: "호스트(IP 또는 호스트명)", mt: "Host (IP or hostname)") }
    var port: String { t("端口", en: "Port", zhHant: "連接埠", ja: "ポート", ko: "포트", mt: "Port") }
    var username: String { t("用户名", en: "Username", zhHant: "使用者名稱", ja: "ユーザー名", ko: "사용자 이름", mt: "Username") }
    var nickname: String { t("昵称", en: "Nickname", zhHant: "暱稱", ja: "ニックネーム", ko: "별명", mt: "Nickname") }
    var dndTimeRange: String { t("免打扰时段", en: "DND Period", zhHant: "免打擾時段", ja: "非通知時間帯", ko: "방해 금지 시간대", mt: "DND Period") }
    var addProtectedDir: String { t("添加保护目录", en: "Add Protected Directory", zhHant: "新增保護目錄", ja: "保護ディレクトリを追加", ko: "보호 디렉토리 추가", mt: "Add Protected Directory") }
    var removeDir: String { t("移除", en: "Remove", zhHant: "移除", ja: "削除", ko: "제거", mt: "Remove") }
    var noProtectedDirs: String { t("暂无保护目录", en: "No Protected Directories", zhHant: "暫無保護目錄", ja: "保護ディレクトリなし", ko: "보호 디렉토리 없음", mt: "No Protected Directories") }
    var noProtectedDirsHint: String { t("添加需要保护的目录，当 Agent 访问时将触发告警", en: "Add directories to protect. Alerts will fire when agents access them", zhHant: "新增需要保護的目錄，當 Agent 訪問時將觸發告警", ja: "保護するディレクトリを追加。Agentアクセス時にアラートが発生します", ko: "보호할 디렉토리를 추가하세요. Agent 접근 시 알림이 발생합니다", mt: "Add directories to protect. Alerts will fire when agents access them") }
    var unreadAlerts: String { t("未读告警", en: "Unread Alerts", zhHant: "未讀告警", ja: "未読アラート", ko: "읽지 않은 알림", mt: "Unread Alerts") }
    var criticalAlerts: String { t("严重告警", en: "Critical Alerts", zhHant: "嚴重告警", ja: "重大アラート", ko: "심각한 알림", mt: "Critical Alerts") }
    var totalAlerts: String { t("总告警", en: "Total Alerts", zhHant: "總告警", ja: "合計アラート", ko: "총 알림", mt: "Total Alerts") }
    var markAllRead: String { t("全部标为已读", en: "Mark All Read", zhHant: "全部標為已讀", ja: "すべて既読にする", ko: "모두 읽음으로 표시", mt: "Mark All Read") }
    var clearAllAlerts: String { t("清空告警", en: "Clear All", zhHant: "清空告警", ja: "アラートをクリア", ko: "알림 지우기", mt: "Clear All") }
    var noAlerts: String { t("暂无告警", en: "No Alerts", zhHant: "暫無告警", ja: "アラートなし", ko: "알림 없음", mt: "No Alerts") }
    var noAlertsHint: String { t("一切正常，未检测到异常操作", en: "All clear, no abnormal operations detected", zhHant: "一切正常，未檢測到異常操作", ja: "すべて正常、異常な操作は検出されませんでした", ko: "모두 정상, 비정상 작업이 감지되지 않았습니다", mt: "All clear, no abnormal operations detected") }
    var exportCSV: String { t("导出 CSV", en: "Export CSV", zhHant: "匯出 CSV", ja: "CSVエクスポート", ko: "CSV 내보내기", mt: "Export CSV") }
    var exportJSON: String { t("导出 JSON", en: "Export JSON", zhHant: "匯出 JSON", ja: "JSONエクスポート", ko: "JSON 내보내기", mt: "Export JSON") }
    var exportAlertsCSV: String { t("导出告警 CSV", en: "Export Alerts CSV", zhHant: "匯出告警 CSV", ja: "アラートCSVエクスポート", ko: "알림 CSV 내보내기", mt: "Export Alerts CSV") }
    var generateReport: String { t("生成报告", en: "Generate Report", zhHant: "生成報告", ja: "レポート生成", ko: "보고서 생성", mt: "Generate Report") }
    var reportPeriod: String { t("报告周期", en: "Report Period", zhHant: "報告週期", ja: "レポート期間", ko: "보고서 기간", mt: "Report Period") }
    var last24h: String { t("最近24小时", en: "Last 24 Hours", zhHant: "最近24小時", ja: "過去24時間", ko: "최근 24시간", mt: "Last 24 Hours") }
    var last7d: String { t("最近7天", en: "Last 7 Days", zhHant: "最近7天", ja: "過去7日間", ko: "최근 7일", mt: "Last 7 Days") }
    var last30d: String { t("最近30天", en: "Last 30 Days", zhHant: "最近30天", ja: "過去30日間", ko: "최근 30일", mt: "Last 30 Days") }
    var allTime: String { t("全部时间", en: "All Time", zhHant: "全部時間", ja: "全期間", ko: "전체 기간", mt: "All Time") }
    var opsCount: String { t("操作数", en: "Operations", zhHant: "運算元", ja: "操作数", ko: "작업 수", mt: "Operations") }
    var alertCount: String { t("告警数", en: "Alerts", zhHant: "告警數", ja: "アラート数", ko: "알림 수", mt: "Alerts") }
    var agentBreakdown: String { t("Agent 分布", en: "Agent Breakdown", zhHant: "Agent 分佈", ja: "Agent分布", ko: "Agent 분포", mt: "Agent Breakdown") }
    var opTypeBreakdown: String { t("操作类型分布", en: "Op Type Breakdown", zhHant: "操作型別分佈", ja: "操作タイプ分布", ko: "작업 유형 분포", mt: "Op Type Breakdown") }
    var topAffectedPaths: String { t("最受影响路径", en: "Top Affected Paths", zhHant: "最受影響路徑", ja: "最も影響を受けたパス", ko: "가장 영향받은 경로", mt: "Top Affected Paths") }
    var severityInfo: String { t("信息", en: "Info", zhHant: "資訊", ja: "情報", ko: "정보", mt: "Info") }
    var severityWarning: String { t("警告", en: "Warning", zhHant: "警告", ja: "警告", ko: "경고", mt: "Warning") }
    var severityCritical: String { t("严重", en: "Critical", zhHant: "嚴重", ja: "重大", ko: "심각", mt: "Critical") }
    var filterAll: String { t("全部", en: "All", zhHant: "全部", ja: "すべて", ko: "전체", mt: "All") }
    var filterInfo: String { t("信息", en: "Info", zhHant: "資訊", ja: "情報", ko: "정보", mt: "Info") }
    var filterWarning: String { t("警告", en: "Warning", zhHant: "警告", ja: "警告", ko: "경고", mt: "Warning") }
    var filterCritical: String { t("严重", en: "Critical", zhHant: "嚴重", ja: "重大", ko: "심각", mt: "Critical") }
    var hourlyTrend: String { t("操作趋势", en: "Operation Trend", zhHant: "操作趨勢", ja: "操作トレンド", ko: "작업 추이", mt: "Operation Trend") }
    var rangeAll: String { t("全部", en: "All", zhHant: "全部", ja: "すべて", ko: "전체", mt: "All") }
    var rangeToday: String { t("当日", en: "Today", zhHant: "當日", ja: "今日", ko: "오늘", mt: "Today") }
    var rangeRealtime: String { t("实时", en: "Realtime", zhHant: "即時", ja: "リアルタイム", ko: "실시간", mt: "Realtime") }
    var createOps: String { t("创建", en: "Create", zhHant: "建立", ja: "作成", ko: "생성", mt: "Create") }
    var modifyOps: String { t("修改", en: "Modify", zhHant: "修改", ja: "変更", ko: "수정", mt: "Modify") }
    var deleteOps: String { t("删除", en: "Delete", zhHant: "刪除", ja: "削除", ko: "삭제", mt: "Delete") }
    var readOps: String { t("读取", en: "Read", zhHant: "讀取", ja: "読み取り", ko: "읽기", mt: "Read") }
    var executeOps: String { t("执行", en: "Execute", zhHant: "執行", ja: "実行", ko: "실행", mt: "Execute") }
    var operationsUnit: String { t("次操作", en: "ops", zhHant: "次操作", ja: "回操作", ko: "회 작업", mt: "ops") }
    var selectDirectory: String { t("选择目录", en: "Select Directory", zhHant: "選擇目錄", ja: "ディレクトリを選択", ko: "디렉토리 선택", mt: "Select Directory") }
    var navToolbox: String { t("实验室", en: "Lab", zhHant: "實驗室", ja: "ラボ", ko: "실험실", mt: "Lab") }
    var subToolbox: String { t("实验性质工具，功能可能调整、下线或移动入口", en: "Experimental tools that may change, be removed, or move to another entry point", zhHant: "實驗性質工具，功能可能調整、下線或移動入口", ja: "変更、削除、または別の導線へ移動される可能性がある実験的ツール", ko: "변경, 제거 또는 다른 진입 경로로 이동될 수 있는 실험적 도구", mt: "Experimental tools that may change, be removed, or move to another entry point") }
    var tokenScopeTitle: String { t("Token 统计", en: "Token Analytics", zhHant: "Token 統計", ja: "Token 分析", ko: "Token 분석", mt: "Token Analytics") }
    var tokenScopeSubtitle: String { t("Token、成本、配额与项目归因分析", en: "Token, cost, quota, and project attribution analytics", zhHant: "Token、成本、配額與專案歸因分析", ja: "トークン、コスト、クォータ、プロジェクト帰属分析", ko: "토큰, 비용, 할당량, 프로젝트 귀속 분석", mt: "Token, cost, quota, and project attribution analytics") }
    var tokenScopeSyncNow: String { t("立即同步", en: "Sync Now", zhHant: "立即同步", ja: "今すぐ同期", ko: "지금 동기화", mt: "Sync Now") }
    var tokenScopeSelectDataFolder: String { t("授权数据目录", en: "Authorize Data Folder", zhHant: "授權資料目錄", ja: "データフォルダを許可", ko: "데이터 폴더 승인", mt: "Authorize Data Folder") }
    var tokenScopeLocalData: String { t("本机真实数据", en: "Local Real Data", zhHant: "本機真實資料", ja: "ローカル実データ", ko: "로컬 실제 데이터", mt: "Local Real Data") }
    var tokenScopeSampleData: String { t("实验室示例数据", en: "Lab Sample Data", zhHant: "實驗室範例資料", ja: "ラボサンプルデータ", ko: "실험실 샘플 데이터", mt: "Lab Sample Data") }
    var tokenScopeScanning: String { t("扫描中", en: "Scanning", zhHant: "掃描中", ja: "スキャン中", ko: "스캔 중", mt: "Scanning") }
    var tokenScopeHeroTitle: String { t("AI Coding 成本控制台", en: "AI Coding Cost Console", zhHant: "AI Coding 成本控制台", ja: "AI Coding コストコンソール", ko: "AI Coding 비용 콘솔", mt: "AI Coding Cost Console") }
    var tokenScopeIntro: String { t("把 Claude、Codex、Pi Agent、Trae、CodeBuddy、Gemini 等工具的 token、模型、项目和会话归因放在同一个原生视图里。通过“授权数据目录”读取用户明确授权的本机日志，不读取浏览器 Cookie，也不抓取网页。", en: "Review tokens, models, projects, and sessions from Claude, Codex, Pi Agent, Trae, CodeBuddy, Gemini, and other tools in one native view. Use Authorize Data Folder to read local logs you explicitly allow; AgentGuard does not read browser cookies or scrape web dashboards.", zhHant: "把 Claude、Codex、Pi Agent、Trae、CodeBuddy、Gemini 等工具的 token、模型、專案與會話歸因放在同一個原生視圖裡。透過「授權資料目錄」讀取使用者明確授權的本機日誌，不讀取瀏覽器 Cookie，也不抓取網頁。", ja: "Claude、Codex、Pi Agent、Trae、CodeBuddy、Gemini などのトークン、モデル、プロジェクト、セッション帰属をひとつのネイティブ画面で確認できます。「データフォルダを許可」で明示的に許可されたローカルログのみを読み取り、ブラウザ Cookie や Web ダッシュボードは読み取りません。", ko: "Claude, Codex, Pi Agent, Trae, CodeBuddy, Gemini 등의 토큰, 모델, 프로젝트, 세션 귀속을 하나의 네이티브 화면에서 확인합니다. 데이터 폴더 승인을 통해 명시적으로 허용한 로컬 로그만 읽으며 브라우저 쿠키나 웹 대시보드는 수집하지 않습니다.", mt: "Review tokens, models, projects, and sessions from Claude, Codex, Pi Agent, Trae, CodeBuddy, Gemini, and other tools in one native view. Use Authorize Data Folder to read local logs you explicitly allow; AgentGuard does not read browser cookies or scrape web dashboards.") }
    var tokenScopeNoData: String { t("未读取到可用的本机 AI usage 记录。请点击授权数据目录，选择 ~/.codex、$CODEX_HOME、~/.pi/agent、~/.claude/projects 或 Trae/CodeBuddy 数据目录后重新验证。", en: "No usable local AI usage records were found. Click Authorize Data Folder, then select ~/.codex, $CODEX_HOME, ~/.pi/agent, ~/.claude/projects, or a Trae/CodeBuddy data folder to verify with local files.", zhHant: "未讀取到可用的本機 AI usage 記錄。請點擊授權資料目錄，選擇 ~/.codex、$CODEX_HOME、~/.pi/agent、~/.claude/projects 或 Trae/CodeBuddy 資料目錄後重新驗證。", ja: "利用できるローカル AI usage レコードが見つかりません。「データフォルダを許可」をクリックし、~/.codex、$CODEX_HOME、~/.pi/agent、~/.claude/projects、または Trae/CodeBuddy のデータフォルダを選択して再確認してください。", ko: "사용 가능한 로컬 AI usage 기록을 찾지 못했습니다. 데이터 폴더 승인을 누른 뒤 ~/.codex, $CODEX_HOME, ~/.pi/agent, ~/.claude/projects 또는 Trae/CodeBuddy 데이터 폴더를 선택해 다시 확인하세요.", mt: "No usable local AI usage records were found. Click Authorize Data Folder, then select ~/.codex, $CODEX_HOME, ~/.pi/agent, ~/.claude/projects, or a Trae/CodeBuddy data folder to verify with local files.") }
    func tokenScopeLoadedSummary(recordCount: Int, sourceCount: Int, tokenText: String) -> String { t("已读取本机 \(recordCount) 条授权日志记录，来自 \(sourceCount) 个数据源。Token 合计 \(tokenText)，成本为本地估算值；数据不会上传。", en: "Loaded \(recordCount) authorized local log records from \(sourceCount) sources. Total tokens: \(tokenText). Cost is a local estimate; this data is not uploaded.", zhHant: "已讀取本機 \(recordCount) 條授權日誌記錄，來自 \(sourceCount) 個資料源。Token 合計 \(tokenText)，成本為本地估算值；資料不會上傳。", ja: "\(sourceCount) 個のソースから \(recordCount) 件の許可済みローカルログを読み込みました。合計トークン: \(tokenText)。コストはローカル推定で、このデータはアップロードされません。", ko: "\(sourceCount)개 소스에서 승인된 로컬 로그 \(recordCount)개를 읽었습니다. 총 토큰: \(tokenText). 비용은 로컬 추정값이며 이 데이터는 업로드되지 않습니다.", mt: "Loaded \(recordCount) authorized local log records from \(sourceCount) sources. Total tokens: \(tokenText). Cost is a local estimate; this data is not uploaded.") }
    var tokenScopeProjects: String { t("项目", en: "Projects", zhHant: "專案", ja: "プロジェクト", ko: "프로젝트", mt: "Projects") }
    var tokenScopeModels: String { t("模型", en: "Models", zhHant: "模型", ja: "モデル", ko: "모델", mt: "Models") }
    var tokenScopeTools: String { t("工具", en: "Tools", zhHant: "工具", ja: "ツール", ko: "도구", mt: "Tools") }
    var tokenScopeSessions: String { t("会话", en: "Sessions", zhHant: "會話", ja: "セッション", ko: "세션", mt: "Sessions") }
    var tokenScopeBudget: String { t("预算", en: "Budget", zhHant: "預算", ja: "予算", ko: "예산", mt: "Budget") }
    var tokenScopeOverview: String { t("概览", en: "Overview", zhHant: "概覽", ja: "概要", ko: "개요", mt: "Overview") }
    var tokenScopeUsageTrend: String { t("使用趋势", en: "Usage Trend", zhHant: "使用趨勢", ja: "使用傾向", ko: "사용 추이", mt: "Usage Trend") }
    var tokenScopeTokenBreakdown: String { t("Input、Output、Cache token 按日拆分", en: "Daily input, output, and cache token split", zhHant: "Input、Output、Cache token 按日拆分", ja: "日別の input、output、cache token 内訳", ko: "일별 input, output, cache token 분해", mt: "Daily input, output, and cache token split") }
    var tokenScopeTrendByToken: String { t("Token 构成", en: "Token Mix", zhHant: "Token 構成", ja: "トークン構成", ko: "토큰 구성", mt: "Token Mix") }
    var tokenScopeTrendByAgent: String { t("按 Agent", en: "By Agent", zhHant: "按 Agent", ja: "Agent 別", ko: "Agent별", mt: "By Agent") }
    var tokenScopeAgentTokenTrend: String { t("每个 Agent 一条 token 趋势线", en: "One token trend line per agent", zhHant: "每個 Agent 一條 token 趨勢線", ja: "Agent ごとの token 推移線", ko: "Agent별 token 추이선", mt: "One token trend line per agent") }
    var tokenScopeTopModels: String { t("Top 模型", en: "Top Models", zhHant: "Top 模型", ja: "上位モデル", ko: "상위 모델", mt: "Top Models") }
    var tokenScopeByCost: String { t("按成本排序", en: "Sorted by cost", zhHant: "按成本排序", ja: "コスト順", ko: "비용순", mt: "Sorted by cost") }
    var tokenScopeProjectBurn: String { t("项目消耗", en: "Project Burn", zhHant: "專案消耗", ja: "プロジェクト消費", ko: "프로젝트 소모", mt: "Project Burn") }
    var tokenScopeProjectAttribution: String { t("项目成本归因", en: "Project cost attribution", zhHant: "專案成本歸因", ja: "プロジェクトコスト帰属", ko: "프로젝트 비용 귀속", mt: "Project cost attribution") }
    var tokenScopeBudgetSignals: String { t("预算信号", en: "Budget Signals", zhHant: "預算訊號", ja: "予算シグナル", ko: "예산 신호", mt: "Budget Signals") }
    var tokenScopeBudgetSignalDesc: String { t("预算与异常波动", en: "Budget and spike signals", zhHant: "預算與異常波動", ja: "予算と急増シグナル", ko: "예산 및 급증 신호", mt: "Budget and spike signals") }
    var tokenScopeRecords: String { t("记录", en: "Records", zhHant: "記錄", ja: "記録", ko: "기록", mt: "Records") }
    var tokenScopeActiveRepos: String { t("活跃仓库", en: "active repos", zhHant: "活躍 repo", ja: "アクティブリポジトリ", ko: "활성 저장소", mt: "active repos") }
    var tokenScopeEstimatedSpend: String { t("估算花费", en: "estimated spend", zhHant: "估算花費", ja: "推定コスト", ko: "추정 비용", mt: "estimated spend") }
    var tokenScopeTotalTokens: String { t("总 Token", en: "Total Tokens", zhHant: "總 Token", ja: "合計トークン", ko: "총 토큰", mt: "Total Tokens") }
    var tokenScopeInputTokens: String { t("输入 Token", en: "Input Tokens", zhHant: "輸入 Token", ja: "入力トークン", ko: "입력 토큰", mt: "Input Tokens") }
    var tokenScopeOutputTokens: String { t("输出 Token", en: "Output Tokens", zhHant: "輸出 Token", ja: "出力トークン", ko: "출력 토큰", mt: "Output Tokens") }
    var tokenScopeCacheTokens: String { t("缓存 Token", en: "Cache Tokens", zhHant: "快取 Token", ja: "キャッシュトークン", ko: "캐시 토큰", mt: "Cache Tokens") }
    var tokenScopeTokenMix: String { t("Token 构成", en: "Token Mix", zhHant: "Token 構成", ja: "トークン構成", ko: "토큰 구성", mt: "Token Mix") }
    var tokenScopeSources: String { t("数据源", en: "Sources", zhHant: "資料源", ja: "データソース", ko: "데이터 소스", mt: "Sources") }
    var tokenScopeRealDataSources: String { t("本机日志与状态库读取状态", en: "Local log and state database read status", zhHant: "本機日誌與狀態庫讀取狀態", ja: "ローカルログと状態データベースの読み取り状態", ko: "로컬 로그 및 상태 DB 읽기 상태", mt: "Local log and state database read status") }
    var tokenScopeSessionDetail: String { t("按会话聚合的真实用量", en: "Real usage grouped by session", zhHant: "按會話彙總的真實用量", ja: "セッション別に集計した実使用量", ko: "세션별 실제 사용량 집계", mt: "Real usage grouped by session") }
    var tokenScopeNoRealData: String { t("尚未加载真实数据", en: "No Real Data Loaded", zhHant: "尚未載入真實資料", ja: "実データ未読み込み", ko: "실제 데이터가 아직 로드되지 않음", mt: "No Real Data Loaded") }
    var tokenScopeScanningDetail: String { t("正在后台读取本机日志，不会阻塞主界面。", en: "Reading local logs in the background without blocking the UI.", zhHant: "正在背景讀取本機日誌，不會阻塞主介面。", ja: "UI をブロックせずバックグラウンドでローカルログを読み取っています。", ko: "UI를 막지 않고 백그라운드에서 로컬 로그를 읽고 있습니다.", mt: "Reading local logs in the background without blocking the UI.") }
    var tokenScopeEmptyRecords: String { t("暂无可展示记录。请点击立即同步，或选择 Claude/Codex/Trae/CodeBuddy 的数据目录授权读取。", en: "No records to show. Click Sync Now or select a Claude, Codex, Trae, or CodeBuddy data folder.", zhHant: "暫無可展示記錄。請點擊立即同步，或選擇 Claude/Codex/Trae/CodeBuddy 的資料目錄授權讀取。", ja: "表示できる記録がありません。今すぐ同期するか、Claude/Codex/Trae/CodeBuddy のデータフォルダを選択してください。", ko: "표시할 기록이 없습니다. 지금 동기화를 누르거나 Claude/Codex/Trae/CodeBuddy 데이터 폴더를 선택하세요.", mt: "No records to show. Click Sync Now or select a Claude, Codex, Trae, or CodeBuddy data folder.") }
    var tokenScopeNeedsPermission: String { t("需要授权", en: "Needs Permission", zhHant: "需要授權", ja: "権限が必要", ko: "권한 필요", mt: "Needs Permission") }
    var tokenScopeNoRecords: String { t("无记录", en: "No Records", zhHant: "無記錄", ja: "記録なし", ko: "기록 없음", mt: "No Records") }
    var tokenScopeActive: String { t("活跃", en: "Active", zhHant: "活躍", ja: "アクティブ", ko: "활성", mt: "Active") }
    var tokenScopeFiles: String { t("文件", en: "Files", zhHant: "檔案", ja: "ファイル", ko: "파일", mt: "Files") }
    var tokenScopeDate: String { t("日期", en: "Date", zhHant: "日期", ja: "日付", ko: "날짜", mt: "Date") }
    var tokenScopeSevenDays: String { t("7 天", en: "7 Days", zhHant: "7 天", ja: "7日", ko: "7일", mt: "7 Days") }
    var tokenScopeThirtyDays: String { t("30 天", en: "30 Days", zhHant: "30 天", ja: "30日", ko: "30일", mt: "30 Days") }
    var commandRules: String { t("命令规则", en: "Command Rules", zhHant: "命令規則", ja: "コマンドルール", ko: "명령 규칙", mt: "Command Rules") }
    var commandRulesDesc: String { t("命令规则用于监控和管控 AI Agent 执行的命令。黑名单中的命令将被拦截并告警，白名单中的命令允许正常执行，未分类的命令将被记录。", en: "Command rules monitor and control commands executed by AI Agents. Blacklisted commands will be blocked and alerted, whitelisted commands are allowed, and unclassified commands are logged.", zhHant: "命令規則用於監控和管控 AI Agent 執行的命令。黑名單中的命令將被攔截並告警，白名單中的命令允許正常執行，未分類的命令將被記錄。", ja: "コマンドルールは、AI Agentが実行するコマンドを監視・制御します。ブラックリストのコマンドはブロック・警告され、ホワイトリストのコマンドは許可され、未分類のコマンドは記録されます。", ko: "명령 규칙은 AI Agent가 실행하는 명령을 모니터링하고 제어합니다. 블랙리스트 명령은 차단 및 경고되고, 화이트리스트 명령은 허용되며, 미분류 명령은 기록됩니다.", mt: "Command rules monitor and control commands executed by AI Agents. Blacklisted commands will be blocked and alerted, whitelisted commands are allowed, and unclassified commands are logged.") }
    var commandBlacklist: String { t("命令黑名单", en: "Command Blacklist", zhHant: "命令黑名單", ja: "コマンドブラックリスト", ko: "명령 블랙리스트", mt: "Command Blacklist") }
    var commandWhitelist: String { t("命令白名单", en: "Command Whitelist", zhHant: "命令白名單", ja: "コマンドホワイトリスト", ko: "명령 화이트리스트", mt: "Command Whitelist") }
    var enableCommandBlacklist: String { t("启用命令黑名单", en: "Enable Command Blacklist", zhHant: "啟用命令黑名單", ja: "コマンドブラックリストを有効化", ko: "명령 블랙리스트 활성화", mt: "Enable Command Blacklist") }
    var enableCommandWhitelist: String { t("启用命令白名单", en: "Enable Command Whitelist", zhHant: "啟用命令白名單", ja: "コマンドホワイトリストを有効化", ko: "명령 화이트리스트 활성화", mt: "Enable Command Whitelist") }
    var newCommandPattern: String { t("输入命令模式", en: "Enter command pattern", zhHant: "輸入命令模式", ja: "コマンドパターンを入力", ko: "명령 패턴 입력", mt: "Enter command pattern") }
    var noWhitelistRules: String { t("暂无白名单规则", en: "No whitelist rules", zhHant: "暫無白名單規則", ja: "ホワイトリストルールなし", ko: "화이트리스트 규칙 없음", mt: "No whitelist rules") }
    var commandBlacklistAlertTitle: String { t("黑名单命令检测", en: "Blacklisted Command Detected", zhHant: "黑名單命令檢測", ja: "ブラックリストコマンド検出", ko: "블랙리스트 명령 감지", mt: "Blacklisted Command Detected") }
    var commandBlacklistAlertMsg: String { t("Agent 执行了黑名单命令", en: "Agent executed a blacklisted command", zhHant: "Agent 執行了黑名單命令", ja: "Agentがブラックリストコマンドを実行しました", ko: "Agent가 블랙리스트 명령을 실행했습니다", mt: "Agent executed a blacklisted command") }
    var commandUnclassified: String { t("未分类命令", en: "Unclassified Commands", zhHant: "未分類命令", ja: "未分類コマンド", ko: "미분류 명령", mt: "Unclassified Commands") }
    var commandUnclassifiedAlertTitle: String { t("未分类命令检测", en: "Unclassified Command", zhHant: "未分類命令檢測", ja: "未分類コマンド検出", ko: "미분류 명령 감지", mt: "Unclassified Command") }
    var commandUnclassifiedAlertMsg: String { t("Agent 执行了未分类命令", en: "Agent executed an unclassified command", zhHant: "Agent 執行了未分類命令", ja: "Agentが未分類コマンドを実行しました", ko: "Agent가 미분류 명령을 실행했습니다", mt: "Agent executed an unclassified command") }
    var enableCommandGuard: String { t("启用命令守护", en: "Enable Command Guard", zhHant: "啟用命令守護", ja: "コマンドガードを有効化", ko: "명령 가드 활성화", mt: "Enable Command Guard") }
    var blacklistLabel: String { t("黑名单", en: "Blacklist", zhHant: "黑名單", ja: "ブラックリスト", ko: "블랙리스트", mt: "Blacklist") }
    var whitelistLabel: String { t("白名单", en: "Whitelist", zhHant: "白名單", ja: "ホワイトリスト", ko: "화이트리스트", mt: "Whitelist") }
    var unclassifiedLabel: String { t("未分类", en: "Unclassified", zhHant: "未分類", ja: "未分類", ko: "미분류", mt: "Unclassified") }
    var moveToBlacklist: String { t("加入黑名单", en: "Blacklist", zhHant: "加入黑名單", ja: "ブラックリストへ", ko: "블랙리스트", mt: "Blacklist") }
    var moveToWhitelist: String { t("加入白名单", en: "Whitelist", zhHant: "加入白名單", ja: "ホワイトリストへ", ko: "화이트리스트", mt: "Whitelist") }
    var moveToUnclassified: String { t("移至未分类", en: "Unclassify", zhHant: "移至未分類", ja: "未分類へ", ko: "미분류로", mt: "Unclassify") }
    var sourceDefault: String { t("默认", en: "Default", zhHant: "預設", ja: "デフォルト", ko: "기본", mt: "Default") }
    var sourceDiscovered: String { t("发现", en: "Discovered", zhHant: "發現", ja: "検出", ko: "발견", mt: "Discovered") }
    var sourceCustom: String { t("自定义", en: "Custom", zhHant: "自訂", ja: "カスタム", ko: "사용자 정의", mt: "Custom") }
    var noUnclassifiedRules: String { t("暂无未分类命令", en: "No unclassified commands yet", zhHant: "暫無未分類命令", ja: "未分類コマンドなし", ko: "미분류 명령 없음", mt: "No unclassified commands yet") }
    var addCustomCommand: String { t("添加自定义命令", en: "Add Custom Command", zhHant: "添加自訂命令", ja: "カスタムコマンド追加", ko: "사용자 명령 추가", mt: "Add Custom Command") }
    var openAppStoreUpdate: String { t("前往 App Store 更新", en: "Open App Store to Update", zhHant: "前往 App Store 更新", ja: "App Storeを開いてアップデート", ko: "App Store에서 업데이트", mt: "Open App Store to Update") }

    var cmdDeleteFiles: String { t("删除文件", en: "Delete files", zhHant: "刪除檔案", ja: "ファイルを削除", ko: "파일 삭제", mt: "Delete files") }
    var cmdRecursiveDelete: String { t("递归强制删除", en: "Recursive force delete", zhHant: "遞迴強制刪除", ja: "再帰的強制削除", ko: "재귀 강제 삭제", mt: "Recursive force delete") }
    var cmdDeleteFilesCon: String { t("文件可能被删除；AgentGuard 会提示你先复核", en: "Files may be removed; AgentGuard asks you to review first", zhHant: "檔案可能被刪除；AgentGuard 會提示你先複核", ja: "ファイルが削除される可能性があります。AgentGuardは先に確認を促します", ko: "파일이 제거될 수 있으며 AgentGuard가 먼저 검토를 요청합니다", mt: "Files may be removed; AgentGuard asks you to review first") }
    var cmdRecursiveDeleteCon: String { t("整个目录树将被无条件删除", en: "Entire directory trees will be deleted without confirmation", zhHant: "整個目錄樹將被無條件刪除", ja: "ディレクトリツリー全体が確認なしで削除されます", ko: "전체 디렉토리 트리가 확인 없이 삭제됩니다", mt: "Entire directory trees will be deleted without confirmation") }
    var cmdCreateDir: String { t("创建目录", en: "Create directory", zhHant: "建立目錄", ja: "ディレクトリ作成", ko: "디렉토리 생성", mt: "Create directory") }
    var cmdCreateDirCon: String { t("将创建新的目录", en: "New directory will be created", zhHant: "將建立新的目錄", ja: "新しいディレクトリが作成されます", ko: "새 디렉토리가 생성됩니다", mt: "New directory will be created") }
    var cmdCopyFiles: String { t("复制文件", en: "Copy files", zhHant: "複製檔案", ja: "ファイルをコピー", ko: "파일 복사", mt: "Copy files") }
    var cmdCopyFilesCon: String { t("文件将被复制到目标位置", en: "Files will be duplicated to target location", zhHant: "檔案將被複製到目標位置", ja: "ファイルが対象位置にコピーされます", ko: "파일이 대상 위치에 복사됩니다", mt: "Files will be duplicated to target location") }
    var cmdMoveFiles: String { t("移动/重命名文件", en: "Move/rename files", zhHant: "移動/重新命名檔案", ja: "ファイルを移動/リネーム", ko: "파일 이동/이름 변경", mt: "Move/rename files") }
    var cmdMoveFilesCon: String { t("文件将被移动或重命名", en: "Files will be moved or renamed", zhHant: "檔案將被移動或重新命名", ja: "ファイルが移動またはリネームされます", ko: "파일이 이동되거나 이름이 변경됩니다", mt: "Files will be moved or renamed") }
    var cmdChmod: String { t("修改文件权限", en: "Change file permissions", zhHant: "修改檔案權限", ja: "ファイル権限を変更", ko: "파일 권한 변경", mt: "Change file permissions") }
    var cmdChmodCon: String { t("文件访问权限将被修改", en: "File access permissions will be modified", zhHant: "檔案存取權限將被修改", ja: "ファイルのアクセス権限が変更されます", ko: "파일 접근 권한이 수정됩니다", mt: "File access permissions will be modified") }
    var cmdChown: String { t("修改文件所有者", en: "Change file ownership", zhHant: "修改檔案擁有者", ja: "ファイル所有者を変更", ko: "파일 소유자 변경", mt: "Change file ownership") }
    var cmdChownCon: String { t("文件所有者/所属组将被更改", en: "File owner/group will be changed", zhHant: "檔案擁有者/群組將被更改", ja: "ファイルの所有者/グループが変更されます", ko: "파일 소유자/그룹이 변경됩니다", mt: "File owner/group will be changed") }
    var cmdCatFile: String { t("显示文件内容", en: "Display file contents", zhHant: "顯示檔案內容", ja: "ファイル内容を表示", ko: "파일 내용 표시", mt: "Display file contents") }
    var cmdCatFileCon: String { t("文件内容将被读取并显示", en: "File contents will be read and displayed", zhHant: "檔案內容將被讀取並顯示", ja: "ファイルの内容が読み取られて表示されます", ko: "파일 내용이 읽혀서 표시됩니다", mt: "File contents will be read and displayed") }
    var cmdSearchText: String { t("搜索文件中的文本", en: "Search text in files", zhHant: "搜尋檔案中的文字", ja: "ファイル内テキスト検索", ko: "파일 내 텍스트 검색", mt: "Search text in files") }
    var cmdSearchTextCon: String { t("将在文件中搜索匹配模式", en: "Will search for patterns in files", zhHant: "將在檔案中搜尋匹配模式", ja: "ファイル内のパターンを検索します", ko: "파일에서 패턴을 검색합니다", mt: "Will search for patterns in files") }
    var cmdSearchFiles: String { t("搜索文件", en: "Search for files", zhHant: "搜尋檔案", ja: "ファイルを検索", ko: "파일 검색", mt: "Search for files") }
    var cmdSearchFilesCon: String { t("将定位符合条件的文件", en: "Will locate files matching criteria", zhHant: "將定位符合條件的檔案", ja: "条件に一致するファイルを検索します", ko: "조건에 맞는 파일을 찾습니다", mt: "Will locate files matching criteria") }
    var cmdDownload: String { t("从URL下载", en: "Download from URL", zhHant: "從URL下載", ja: "URLからダウンロード", ko: "URL에서 다운로드", mt: "Download from URL") }
    var cmdDownloadCon: String { t("将从远程服务器获取数据", en: "Data will be fetched from a remote server", zhHant: "將從遠端伺服器獲取資料", ja: "リモートサーバーからデータを取得します", ko: "원격 서버에서 데이터를 가져옵니다", mt: "Data will be fetched from a remote server") }
    var cmdDownloadFile: String { t("下载文件", en: "Download file", zhHant: "下載檔案", ja: "ダウンロード", ko: "파일 다운로드", mt: "Download file") }
    var cmdDownloadFileCon: String { t("将从互联网下载文件", en: "File will be downloaded from the internet", zhHant: "將從網際網路下載檔案", ja: "インターネットからファイルをダウンロードします", ko: "인터넷에서 파일을 다운로드합니다", mt: "File will be downloaded from the internet") }
    var cmdGit: String { t("Git版本控制", en: "Git version control", zhHant: "Git版本控制", ja: "Git バージョン管理", ko: "Git 버전 관리", mt: "Git version control") }
    var cmdGitCon: String { t("将执行代码仓库操作", en: "Repository operations will be performed", zhHant: "將執行程式碼儲存庫操作", ja: "リポジトリ操作が実行されます", ko: "저장소 작업이 실행됩니다", mt: "Repository operations will be performed") }
    var cmdPkgMgr: String { t("包管理器", en: "Package manager", zhHant: "套件管理器", ja: "パッケージマネージャー", ko: "패키지 관리자", mt: "Package manager") }
    var cmdNodePkgCon: String { t("将安装或修改Node.js依赖包", en: "Node.js packages will be installed/modified", zhHant: "將安裝或修改Node.js依賴套件", ja: "Node.jsパッケージがインストール/変更されます", ko: "Node.js 패키지가 설치/수정됩니다", mt: "Node.js packages will be installed/modified") }
    var cmdPyPkgCon: String { t("将安装或修改Python包", en: "Python packages will be installed/modified", zhHant: "將安裝或修改Python套件", ja: "Pythonパッケージがインストール/変更されます", ko: "Python 패키지가 설치/수정됩니다", mt: "Python packages will be installed/modified") }
    var cmdBrew: String { t("Homebrew包管理器", en: "Homebrew package manager", zhHant: "Homebrew套件管理器", ja: "Homebrewパッケージマネージャー", ko: "Homebrew 패키지 관리자", mt: "Homebrew package manager") }
    var cmdBrewCon: String { t("将安装或修改macOS软件包", en: "macOS packages will be installed/modified", zhHant: "將安裝或修改macOS套件", ja: "macOSパッケージがインストール/変更されます", ko: "macOS 패키지가 설치/수정됩니다", mt: "macOS packages will be installed/modified") }
    var cmdDocker: String { t("Docker容器管理", en: "Docker container management", zhHant: "Docker容器管理", ja: "Dockerコンテナ管理", ko: "Docker 컨테이너 관리", mt: "Docker container management") }
    var cmdDockerCon: String { t("容器/镜像将被创建或修改", en: "Containers/images will be created or modified", zhHant: "容器/映像將被建立或修改", ja: "コンテナ/イメージが作成または変更されます", ko: "컨테이너/이미지가 생성 또는 수정됩니다", mt: "Containers/images will be created or modified") }
    var cmdSudo: String { t("以超级用户权限执行", en: "Execute with superuser privileges", zhHant: "以超級使用者權限執行", ja: "スーパーユーザー権限で実行", ko: "슈퍼유저 권한으로 실행", mt: "Execute with superuser privileges") }
    var cmdSudoCon: String { t("命令将以提升的系统权限运行", en: "Command runs with elevated system permissions", zhHant: "命令將以提升的系統權限執行", ja: "コマンドが昇格されたシステム権限で実行されます", ko: "명령이 상승된 시스템 권한으로 실행됩니다", mt: "Command runs with elevated system permissions") }
    var cmdKill: String { t("终止进程", en: "Terminate process", zhHant: "終止程序", ja: "プロセスを終了", ko: "프로세스 종료", mt: "Terminate process") }
    var cmdKillCon: String { t("正在运行的进程将被停止", en: "Running processes will be stopped", zhHant: "正在執行的程序將被停止", ja: "実行中のプロセスが停止されます", ko: "실행 중인 프로세스가 중지됩니다", mt: "Running processes will be stopped") }
    var cmdLaunchctl: String { t("启动守护进程控制", en: "Launch daemon control", zhHant: "啟動守護程序控制", ja: "起動デーモン制御", ko: "런치 데몬 제어", mt: "Launch daemon control") }
    var cmdLaunchctlCon: String { t("系统服务将被加载或卸载", en: "System services will be loaded/unloaded", zhHant: "系統服務將被載入或卸載", ja: "システムサービスがロード/アンロードされます", ko: "시스템 서비스가 로드/언로드됩니다", mt: "System services will be loaded/unloaded") }
    var cmdDefaults: String { t("macOS默认设置", en: "macOS defaults system", zhHant: "macOS預設設定", ja: "macOSデフォルト設定", ko: "macOS 기본 설정", mt: "macOS defaults system") }
    var cmdDefaultsCon: String { t("系统/应用偏好设置将被修改", en: "System/application preferences will be modified", zhHant: "系統/應用偏好設定將被修改", ja: "システム/アプリケーション設定が変更されます", ko: "시스템/앱 환경설정이 수정됩니다", mt: "System/application preferences will be modified") }
    var cmdSymlink: String { t("创建符号链接", en: "Create symbolic link", zhHant: "建立符號連結", ja: "シンボリックリンク作成", ko: "심볼릭 링크 생성", mt: "Create symbolic link") }
    var cmdSymlinkCon: String { t("将创建指向另一个文件的链接", en: "A link to another file will be created", zhHant: "將建立指向另一個檔案的連結", ja: "別のファイルへのリンクが作成されます", ko: "다른 파일에 대한 링크가 생성됩니다", mt: "A link to another file will be created") }
    var cmdArchive: String { t("归档/解压文件", en: "Archive/extract files", zhHant: "封存/解壓檔案", ja: "ファイルのアーカイブ/展開", ko: "파일 보관/압축 해제", mt: "Archive/extract files") }
    var cmdArchiveCon: String { t("文件将被压缩或解压", en: "Files will be compressed or extracted", zhHant: "檔案將被壓縮或解壓", ja: "ファイルが圧縮または展開されます", ko: "파일이 압축되거나 압축이 해제됩니다", mt: "Files will be compressed or extracted") }
    var cmdZip: String { t("压缩/解压ZIP", en: "Compress/extract ZIP", zhHant: "壓縮/解壓ZIP", ja: "ZIPの圧縮/展開", ko: "ZIP 압축/해제", mt: "Compress/extract ZIP") }
    var cmdZipCon: String { t("文件将被压缩或解压", en: "Files will be archived or extracted", zhHant: "檔案將被壓縮或解壓", ja: "ファイルがアーカイブまたは展開されます", ko: "파일이 보관되거나 압축 해제됩니다", mt: "Files will be archived or extracted") }
    var cmdSed: String { t("流编辑器", en: "Stream editor", zhHant: "串流編輯器", ja: "ストリームエディタ", ko: "스트림 에디터", mt: "Stream editor") }
    var cmdSedCon: String { t("文件内容将被就地修改或流式处理", en: "File contents will be modified in-place or streamed", zhHant: "檔案內容將被就地修改或串流處理", ja: "ファイル内容がインプレースまたはストリームで変更されます", ko: "파일 내용이 제자리에서 수정되거나 스트리밍됩니다", mt: "File contents will be modified in-place or streamed") }
    var cmdAwk: String { t("文本处理", en: "Text processing", zhHant: "文字處理", ja: "テキスト処理", ko: "텍스트 처리", mt: "Text processing") }
    var cmdAwkCon: String { t("文本数据将被处理和转换", en: "Text data will be processed and transformed", zhHant: "文字資料將被處理和轉換", ja: "テキストデータが処理・変換されます", ko: "텍스트 데이터가 처리 및 변환됩니다", mt: "Text data will be processed and transformed") }
    var cmdXcode: String { t("构建Xcode项目", en: "Build Xcode project", zhHant: "構建Xcode專案", ja: "Xcodeプロジェクトをビルド", ko: "Xcode 프로젝트 빌드", mt: "Build Xcode project") }
    var cmdXcodeCon: String { t("项目将被编译和构建", en: "Project will be compiled and built", zhHant: "專案將被編譯和構建", ja: "プロジェクトがコンパイル・ビルドされます", ko: "프로젝트가 컴파일 및 빌드됩니다", mt: "Project will be compiled and built") }
    var cmdSwift: String { t("运行Swift", en: "Run Swift", zhHant: "執行Swift", ja: "Swiftを実行", ko: "Swift 실행", mt: "Run Swift") }
    var cmdSwiftCon: String { t("Swift代码将被编译或执行", en: "Swift code will be compiled or executed", zhHant: "Swift程式碼將被編譯或執行", ja: "Swiftコードがコンパイルまたは実行されます", ko: "Swift 코드가 컴파일되거나 실행됩니다", mt: "Swift code will be compiled or executed") }
    var cmdPython: String { t("运行Python", en: "Run Python", zhHant: "執行Python", ja: "Pythonを実行", ko: "Python 실행", mt: "Run Python") }
    var cmdPythonCon: String { t("Python脚本将被执行", en: "Python script will be executed", zhHant: "Python指令碼將被執行", ja: "Pythonスクリプトが実行されます", ko: "Python 스크립트가 실행됩니다", mt: "Python script will be executed") }
    var cmdNode: String { t("运行Node.js", en: "Run Node.js", zhHant: "執行Node.js", ja: "Node.jsを実行", ko: "Node.js 실행", mt: "Run Node.js") }
    var cmdNodeCon: String { t("JavaScript将被执行", en: "JavaScript will be executed", zhHant: "JavaScript將被執行", ja: "JavaScriptが実行されます", ko: "JavaScriptが実行されます", mt: "JavaScript will be executed") }
    var cmdShell: String { t("执行Shell脚本", en: "Execute shell script", zhHant: "執行Shell指令碼", ja: "シェルスクリプトを実行", ko: "셸 스크립트 실행", mt: "Execute shell script") }
    var cmdShellCon: String { t("Shell命令将被执行", en: "Shell commands will be run", zhHant: "Shell命令將被執行", ja: "シェルコマンドが実行されます", ko: "셸 명령이 실행됩니다", mt: "Shell commands will be run") }
    var cmdEcho: String { t("输出文本", en: "Print text", zhHant: "輸出文字", ja: "テキストを出力", ko: "텍스트 출력", mt: "Print text") }
    var cmdEchoCon: String { t("文本将被输出到控制台或文件", en: "Text will be output to console or file", zhHant: "文字將被輸出到控制台或檔案", ja: "テキストがコンソールまたはファイルに出力されます", ko: "텍스트가 콘솔 또는 파일에 출력됩니다", mt: "Text will be output to console or file") }
    var cmdTouch: String { t("创建空文件", en: "Create empty file", zhHant: "建立空檔案", ja: "空ファイルを作成", ko: "빈 파일 생성", mt: "Create empty file") }
    var cmdTouchCon: String { t("将创建新的空文件或更新时间戳", en: "New empty file will be created or timestamp updated", zhHant: "將建立新的空檔案或更新時間戳", ja: "新しい空ファイルが作成されるか、タイムスタンプが更新されます", ko: "새 빈 파일이 생성되거나 타임스탬프가 업데이트됩니다", mt: "New empty file will be created or timestamp updated") }
    var cmdHeadTail: String { t("查看文件头部/尾部", en: "View file head/tail", zhHant: "查看檔案頭部/尾部", ja: "ファイルの先頭/末尾を表示", ko: "파일 헤드/테일 보기", mt: "View file head/tail") }
    var cmdHeadTailCon: String { t("将显示文件的开头或结尾部分", en: "Beginning or end of file will be displayed", zhHant: "將顯示檔案的開頭或結尾部分", ja: "ファイルの先頭または末尾が表示されます", ko: "파일의 시작 또는 끝 부분이 표시됩니다", mt: "Beginning or end of file will be displayed") }
    var cmdWc: String { t("统计行数/词数", en: "Count lines/words", zhHant: "統計行數/詞數", ja: "行数/単語数をカウント", ko: "행/단어 수 계산", mt: "Count lines/words") }
    var cmdWcCon: String { t("将计算文件统计信息", en: "File statistics will be calculated", zhHant: "將計算檔案統計資訊", ja: "ファイルの統計情報が計算されます", ko: "파일 통계가 계산됩니다", mt: "File statistics will be calculated") }
    var cmdSort: String { t("排序行", en: "Sort lines", zhHant: "排序行", ja: "行をソート", ko: "행 정렬", mt: "Sort lines") }
    var cmdSortCon: String { t("行将按字母或数字排序", en: "Lines will be sorted alphabetically or numerically", zhHant: "行將按字母或數字排序", ja: "行がアルファベット順または数字順にソートされます", ko: "행이 알파벳 또는 숫자순으로 정렬됩니다", mt: "Lines will be sorted alphabetically or numerically") }
    var cmdUniq: String { t("去重", en: "Remove duplicates", zhHant: "去除重複", ja: "重複を削除", ko: "중복 제거", mt: "Remove duplicates") }
    var cmdUniqCon: String { t("相邻的重复行将被移除", en: "Duplicate adjacent lines will be removed", zhHant: "相鄰的重複行將被移除", ja: "隣接する重複行が削除されます", ko: "인접한 중복 행이 제거됩니다", mt: "Duplicate adjacent lines will be removed") }
    var cmdDiff: String { t("比较文件", en: "Compare files", zhHant: "比較檔案", ja: "ファイルを比較", ko: "파일 비교", mt: "Compare files") }
    var cmdDiffCon: String { t("将显示文件之间的差异", en: "Differences between files will be shown", zhHant: "將顯示檔案之間的差異", ja: "ファイル間の差異が表示されます", ko: "파일 간의 차이가 표시됩니다", mt: "Differences between files will be shown") }
    var cmdSafe: String { t("安全操作", en: "Safe operation", zhHant: "安全操作", ja: "安全な操作", ko: "안전한 작업", mt: "Safe operation") }
    var cmdReadOnly: String { t("只读操作", en: "Read-only operation", zhHant: "唯讀操作", ja: "読み取り専用操作", ko: "읽기 전용 작업", mt: "Read-only operation") }
    var cmdListDir: String { t("列出目录内容", en: "List directory contents", zhHant: "列出目錄內容", ja: "ディレクトリ内容を一覧", ko: "디렉토리 내용 나열", mt: "List directory contents") }
    var cmdLocate: String { t("定位命令路径", en: "Locate command path", zhHant: "定位命令路徑", ja: "コマンドパスを検索", ko: "명령 경로 찾기", mt: "Locate command path") }
    var cmdListProc: String { t("列出进程", en: "List processes", zhHant: "列出程序", ja: "プロセス一覧", ko: "프로세스 나열", mt: "List processes") }
    var cmdDiskFree: String { t("磁盘剩余空间", en: "Disk free space", zhHant: "磁碟剩餘空間", ja: "ディスク空き容量", ko: "디스크 여유 공간", mt: "Disk free space") }
    var cmdDiskUsage: String { t("磁盘使用量", en: "Disk usage", zhHant: "磁碟使用量", ja: "ディスク使用量", ko: "디스크 사용량", mt: "Disk usage") }
}
