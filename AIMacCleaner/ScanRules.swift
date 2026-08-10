import Foundation

struct ScanRule {
    let id: String
    let name: String
    let category: String
    let app: String
    let risk: String
    let riskDesc: String
    let paths: [String]
}

let SCAN_RULES: [ScanRule] = [
    ScanRule(id: "cache_browser_chrome", name: "Chrome 浏览器缓存", category: "浏览器", app: "Google Chrome", risk: "safe", riskDesc: "仅删除缓存，不影响书签、密码、历史记录。删除后网页首次加载会稍慢。", paths: [
        "~/Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage",
        "~/Library/Application Support/Google/Chrome/Default/Code Cache",
        "~/Library/Application Support/Google/Chrome/Default/GPUCache",
        "~/Library/Caches/Google",
    ]),
    ScanRule(id: "cache_browser_chrome_data", name: "Chrome 用户数据缓存", category: "浏览器", app: "Google Chrome", risk: "caution", riskDesc: "包含 IndexedDB 和 Local Storage，部分网站登录状态可能丢失，需重新登录。", paths: [
        "~/Library/Application Support/Google/Chrome/Default/IndexedDB",
        "~/Library/Application Support/Google/Chrome/Default/Session Storage",
    ]),
    ScanRule(id: "cache_lark", name: "飞书缓存", category: "办公", app: "飞书/Lark", risk: "safe", riskDesc: "飞书下载的临时文件和缓存图片，删除后不影响聊天记录，会自动重新下载。", paths: [
        "~/Library/Caches/LarkShell",
    ]),
    ScanRule(id: "data_lark_deployments", name: "飞书更新包", category: "办公", app: "飞书/Lark", risk: "safe", riskDesc: "已安装的旧版本更新包，可安全删除。", paths: [
        "~/Library/Application Support/LarkShell/deployments",
    ]),
    ScanRule(id: "data_lark_aha", name: "飞书运行时数据", category: "办公", app: "飞书/Lark", risk: "caution", riskDesc: "飞书运行时缓存数据，删除后首次启动会较慢，部分离线文件需重新下载。", paths: [
        "~/Library/Application Support/LarkShell/aha",
        "~/Library/Application Support/LarkShell/iron",
    ]),
    ScanRule(id: "cache_claude_vm", name: "Claude Code 虚拟机沙箱", category: "AI Agent", app: "Claude Code", risk: "safe", riskDesc: "已完成的沙箱执行环境镜像，删除后不影响 Claude Code 正常使用，下次执行会重建。", paths: [
        "~/Library/Application Support/Claude-3p/vm_bundles",
    ]),
    ScanRule(id: "cache_claude", name: "Claude Code 缓存", category: "AI Agent", app: "Claude Code", risk: "safe", riskDesc: "Claude 运行缓存，删除后不影响使用。", paths: [
        "~/Library/Application Support/Claude-3p/Cache",
        "~/Library/Application Support/Claude-3p/GPUCache",
    ]),
    ScanRule(id: "cache_photo_analysis", name: "照片分析索引缓存", category: "系统", app: "macOS 照片", risk: "safe", riskDesc: "相册人脸识别、场景分类的索引缓存，删除后系统会自动重建（耗时较长），不影响照片本身。", paths: [
        "~/Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches",
    ]),
    ScanRule(id: "cache_updater_packages", name: "Agent 更新包缓存", category: "AI Agent", app: "多个 Agent", risk: "safe", riskDesc: "已安装的旧版本更新下载包，全部可安全删除，下次更新时会重新下载。", paths: [
        "~/Library/Caches/cn.trae.app.ShipIt",
        "~/Library/Caches/@guanjia-openclawelectron-updater",
        "~/Library/Caches/vms9466-updater",
        "~/Library/Caches/crebee-updater",
        "~/Library/Caches/cherrystudio-updater",
        "~/Library/Caches/@mmx-agentelectron-updater",
        "~/Library/Caches/galic-updater",
    ]),
    ScanRule(id: "log_trae", name: "Trae CN 日志", category: "AI Agent", app: "Trae CN", risk: "safe", riskDesc: "Trae 运行日志，仅用于调试，删除后不影响使用，会自动重建。", paths: [
        "~/Library/Application Support/Trae CN/logs",
    ]),
    ScanRule(id: "log_codebuddy", name: "CodeBuddy CN 日志", category: "AI Agent", app: "CodeBuddy CN", risk: "safe", riskDesc: "CodeBuddy 运行日志，仅用于调试，删除后不影响使用。", paths: [
        "~/Library/Application Support/CodeBuddy CN/logs",
    ]),
    ScanRule(id: "cache_trae", name: "Trae CN 缓存", category: "AI Agent", app: "Trae CN", risk: "safe", riskDesc: "Trae 缓存数据，删除后首次启动会稍慢。", paths: [
        "~/Library/Caches/Trae CN",
        "~/Library/Application Support/Trae CN/CachedData",
        "~/Library/Application Support/Trae CN/Cache",
    ]),
    ScanRule(id: "cache_codebuddy", name: "CodeBuddy CN 缓存", category: "AI Agent", app: "CodeBuddy CN", risk: "safe", riskDesc: "CodeBuddy 缓存数据，删除后首次启动会稍慢。", paths: [
        "~/Library/Application Support/CodeBuddy CN/CachedData",
    ]),
    ScanRule(id: "cache_electron", name: "Electron 框架缓存", category: "开发", app: "Electron", risk: "safe", riskDesc: "Electron 应用编译缓存，删除后 Electron 应用首次启动会稍慢，会自动重建。", paths: [
        "~/Library/Caches/electron",
        "~/Library/Caches/electron-builder",
    ]),
    ScanRule(id: "cache_pip", name: "Python pip 下载缓存", category: "开发", app: "Python/pip", risk: "safe", riskDesc: "pip 已下载的安装包缓存，删除后下次 pip install 会重新下载，不影响已安装的包。", paths: [
        "~/Library/Caches/pip",
        "~/.cache/pip",
    ]),
    ScanRule(id: "cache_homebrew", name: "Homebrew 下载缓存", category: "开发", app: "Homebrew", risk: "safe", riskDesc: "brew 已下载的安装包缓存，删除后下次 brew install 会重新下载，不影响已安装的包。", paths: [
        "~/Library/Caches/Homebrew",
    ]),
    ScanRule(id: "cache_npm", name: "npm 包缓存", category: "开发", app: "Node.js/npm", risk: "safe", riskDesc: "npm 已下载的包缓存，删除后下次 npm install 会重新下载。", paths: [
        "~/.npm/_cacache",
    ]),
    ScanRule(id: "cache_pnpm", name: "pnpm 包缓存", category: "开发", app: "Node.js/pnpm", risk: "safe", riskDesc: "pnpm 已下载的包缓存，删除后下次 pnpm install 会重新下载。", paths: [
        "~/Library/Caches/pnpm",
        "~/.pnpm-store",
    ]),
    ScanRule(id: "cache_quark", name: "夸克浏览器缓存", category: "浏览器", app: "夸克", risk: "safe", riskDesc: "夸克浏览器缓存数据，删除后不影响书签和设置。", paths: [
        "~/Library/Caches/Quark",
    ]),
    ScanRule(id: "system_logs", name: "系统日志", category: "系统", app: "macOS", risk: "safe", riskDesc: "系统运行日志，删除后不影响使用，会自动重建。", paths: [
        "~/Library/Logs",
    ]),
    ScanRule(id: "cache_geoservices", name: "地理位置服务缓存", category: "系统", app: "macOS", risk: "safe", riskDesc: "地图和定位服务缓存，删除后会自动重建。", paths: [
        "~/Library/Caches/GeoServices",
    ]),
    ScanRule(id: "cache_huawei", name: "华为相关缓存", category: "开发", app: "Huawei", risk: "safe", riskDesc: "华为开发工具缓存，删除后不影响使用。", paths: [
        "~/Library/Caches/Huawei",
    ]),
    ScanRule(id: "cache_hap_installer", name: "HAP 安装器缓存", category: "开发", app: "HarmonyOS", risk: "safe", riskDesc: "鸿蒙应用安装缓存，删除后不影响已安装的应用。", paths: [
        "~/Library/Caches/hap_installer",
    ]),
    ScanRule(id: "cache_doubao", name: "豆包可重建缓存", category: "AI Agent", app: "豆包", risk: "caution", riskDesc: "只清理缓存、代码缓存和 GPU 缓存；不会选择整个应用数据目录。退出豆包后再清理。", paths: [
        "~/Library/Application Support/Doubao/Cache",
        "~/Library/Application Support/Doubao/Code Cache",
        "~/Library/Application Support/Doubao/GPUCache",
        "~/Library/Application Support/Doubao/CachedData",
    ]),
    ScanRule(id: "cache_qianwen", name: "通义千问可重建缓存", category: "AI Agent", app: "通义千问", risk: "caution", riskDesc: "只清理缓存、代码缓存和 GPU 缓存；不会选择整个应用数据目录。退出应用后再清理。", paths: [
        "~/Library/Application Support/Qianwen/Cache",
        "~/Library/Application Support/Qianwen/Code Cache",
        "~/Library/Application Support/Qianwen/GPUCache",
        "~/Library/Application Support/Qianwen/CachedData",
    ]),
    ScanRule(id: "cache_crebee", name: "Crebee 可重建缓存", category: "AI Agent", app: "Crebee", risk: "caution", riskDesc: "只清理缓存、代码缓存和 GPU 缓存；不会选择整个应用数据目录。退出应用后再清理。", paths: [
        "~/Library/Application Support/crebee/Cache",
        "~/Library/Application Support/crebee/Code Cache",
        "~/Library/Application Support/crebee/GPUCache",
        "~/Library/Application Support/crebee/CachedData",
    ]),
    ScanRule(id: "cache_codebuddy_ext", name: "CodeBuddy 扩展可重建缓存", category: "AI Agent", app: "CodeBuddy", risk: "caution", riskDesc: "只清理扩展的明确缓存子目录；不会选择整个扩展数据目录。退出 CodeBuddy 后再清理。", paths: [
        "~/Library/Application Support/CodeBuddyExtension/Cache",
        "~/Library/Application Support/CodeBuddyExtension/Code Cache",
        "~/Library/Application Support/CodeBuddyExtension/GPUCache",
        "~/Library/Application Support/CodeBuddyExtension/CachedData",
    ]),
    ScanRule(id: "cache_codearts", name: "CodeArts Agent 可重建缓存", category: "AI Agent", app: "CodeArts Agent", risk: "caution", riskDesc: "只清理明确的缓存子目录；不会选择整个应用数据目录。退出应用后再清理。", paths: [
        "~/Library/Application Support/CodeArts Agent/Cache",
        "~/Library/Application Support/CodeArts Agent/Code Cache",
        "~/Library/Application Support/CodeArts Agent/GPUCache",
        "~/Library/Application Support/CodeArts Agent/CachedData",
    ]),
    ScanRule(id: "cache_master_desktop", name: "Master Desktop 可重建缓存", category: "AI Agent", app: "Master Desktop", risk: "caution", riskDesc: "只清理明确的缓存子目录；不会选择整个应用数据目录。退出应用后再清理。", paths: [
        "~/Library/Application Support/master-desktop/Cache",
        "~/Library/Application Support/master-desktop/Code Cache",
        "~/Library/Application Support/master-desktop/GPUCache",
        "~/Library/Application Support/master-desktop/CachedData",
    ]),
    ScanRule(id: "cache_qclaw", name: "QClaw 可重建缓存", category: "AI Agent", app: "QClaw", risk: "caution", riskDesc: "只清理明确的缓存子目录；不会选择整个应用数据目录。退出应用后再清理。", paths: [
        "~/Library/Application Support/QClaw/Cache",
        "~/Library/Application Support/QClaw/Code Cache",
        "~/Library/Application Support/QClaw/GPUCache",
        "~/Library/Application Support/QClaw/CachedData",
    ]),
    ScanRule(id: "cache_yarn", name: "Yarn 缓存", category: "开发", app: "Yarn", risk: "safe", riskDesc: "Yarn 包缓存，删除后下次安装包时会重新下载。", paths: [
        "~/Library/Caches/Yarn",
    ]),
    ScanRule(id: "cache_cargo", name: "Cargo 缓存", category: "开发", app: "Rust / Cargo", risk: "safe", riskDesc: "Cargo 包缓存和编译产物，删除后下次编译会重新下载。", paths: [
        "~/.cargo/registry",
    ]),
    ScanRule(id: "cache_gradle", name: "Gradle 缓存", category: "开发", app: "Gradle", risk: "safe", riskDesc: "Gradle 构建缓存和下载的依赖，删除后下次构建会重新下载。", paths: [
        "~/.gradle/caches",
        "~/.gradle/wrapper/dists",
    ]),
    ScanRule(id: "cache_maven", name: "Maven 缓存", category: "开发", app: "Maven", risk: "caution", riskDesc: "Maven 本地仓库，删除后需重新下载所有依赖。", paths: [
        "~/.m2/repository",
    ]),
    ScanRule(id: "cache_cocoapods", name: "CocoaPods 缓存", category: "开发", app: "CocoaPods", risk: "safe", riskDesc: "CocoaPods 仓库缓存，删除后下次 pod install 会重新下载。", paths: [
        "~/Library/Caches/CocoaPods",
        "~/.cocoapods/repos",
    ]),
    ScanRule(id: "cache_go_build", name: "Go 构建缓存", category: "开发", app: "Go", risk: "safe", riskDesc: "Go 编译缓存，删除后下次编译会稍慢。", paths: [
        "~/Library/Caches/go-build",
        "~/go/pkg/mod/cache",
    ]),
    ScanRule(id: "cache_docker", name: "Docker Desktop 日志与缓存", category: "开发", app: "Docker", risk: "caution", riskDesc: "只清理 Docker Desktop 的日志和可重建缓存；不会选择虚拟磁盘、镜像、容器或 volume 数据。退出 Docker Desktop 后再清理。", paths: [
        "~/Library/Caches/com.docker.docker",
        "~/Library/Containers/com.docker.docker/Data/log",
        "~/Library/Containers/com.docker.docker/Data/logs",
    ]),
    ScanRule(id: "cache_android", name: "Android SDK 缓存", category: "开发", app: "Android Studio", risk: "safe", riskDesc: "Android SDK 临时缓存，删除后不影响 SDK 本身。", paths: [
        "~/Library/Android/sdk/.temp",
    ]),
]
