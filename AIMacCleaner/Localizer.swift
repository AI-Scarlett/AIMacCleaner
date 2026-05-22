import SwiftUI
import Foundation

enum AppLanguage: String, CaseIterable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case maltese = "mt"

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
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
            objectWillChange.send()
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        language = AppLanguage(rawValue: saved) ?? .english
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
    var aiSettingsDesc: String { t("配置大模型 API，用于智能分析目录结构和识别可清理项", en: "Configure LLM API for intelligent directory analysis", zhHant: "配置大模型 API，用於智慧分析目錄結構和識別可清理項", ja: "大規模モデルAPIを設定し、ディレクトリ構造のインテリジェント分析とクリーンアップ項目の識別に使用", ko: "대규모 모델 API를 구성하여 디렉토리 구조 스마트 분석 및 정리 가능 항목 식별에 사용", mt: "Configure LLM API for intelligent directory analysis") }
    var apiBase: String { t("API Base", en: "API Base", zhHant: "API Base", ja: "API Base", ko: "API Base", mt: "API Base") }
    var apiKey: String { t("API Key", en: "API Key", zhHant: "API Key", ja: "API Key", ko: "API Key", mt: "API Key") }
    var modelName: String { t("模型名称", en: "Model Name", zhHant: "模型名稱", ja: "モデル名", ko: "모델 이름", mt: "Model Name") }
    var recommendedConfig: String { t("推荐配置（点击自动填入）", en: "Recommended presets (click to auto-fill)", zhHant: "推薦配置（點選自動填入）", ja: "推奨設定（クリックで自動入力）", ko: "추천 설정 (클릭 시 자동 입력)", mt: "Recommended presets (click to auto-fill)") }

    var featureToggles: String { t("功能开关", en: "Feature Toggles", zhHant: "功能開關", ja: "機能切替", ko: "기능 토글", mt: "Feature Toggles") }
    var menuBarMonitor: String { t("菜单栏监控", en: "Menu Bar Monitor", zhHant: "選單欄監控", ja: "メニューバーモニター", ko: "메뉴 막대 모니터", mt: "Menu Bar Monitor") }
    var menuBarMonitorDesc: String { t("在菜单栏显示系统资源监控", en: "Show system resource monitoring in menu bar", zhHant: "在選單欄顯示系統資源監控", ja: "メニューバーにシステムリソースモニタリングを表示", ko: "메뉴 막대에 시스템 리소스 모니터링 표시", mt: "Show system resource monitoring in menu bar") }
    var sensorMonitor: String { t("设备监控", en: "Device Monitor", zhHant: "裝置監控", ja: "デバイスモニター", ko: "장치 모니터", mt: "Device Monitor") }
    var sensorMonitorDesc: String { t("监控摄像头和麦克风调用", en: "Monitor camera and microphone usage", zhHant: "監控攝像頭和麥克風呼叫", ja: "カメラとマイクの使用をモニタリング", ko: "카메라 및 마이크 사용 모니터링", mt: "Monitor camera and microphone usage") }
    var operationMonitor: String { t("操作记录", en: "Operation Monitor", zhHant: "操作記錄", ja: "操作記録", ko: "작업 기록", mt: "Operation Monitor") }
    var operationMonitorDesc: String { t("监控 AI Agent 的文件操作", en: "Monitor AI Agent file operations", zhHant: "監控 AI Agent 的檔案操作", ja: "AI Agentのファイル操作をモニタリング", ko: "AI Agent 파일 작업 모니터링", mt: "Monitor AI Agent file operations") }

    var monitorSettings: String { t("监控设置", en: "Monitor Settings", zhHant: "監控設定", ja: "モニター設定", ko: "모니터 설정", mt: "Monitor Settings") }
    var storageAlertThreshold: String { t("存储警告阈值", en: "Storage Alert Threshold", zhHant: "儲存警告閾值", ja: "ストレージ警告しきい値", ko: "저장소 경고 임계값", mt: "Storage Alert Threshold") }
    var trashInsteadOfDelete: String { t("使用回收站", en: "Use Trash", zhHant: "使用回收站", ja: "ゴミ箱を使用", ko: "휴지통 사용", mt: "Use Trash") }
    var trashInsteadOfDeleteDesc: String { t("删除文件时移入回收站而非直接删除", en: "Move files to Trash instead of permanent delete", zhHant: "刪除檔案時移入回收站而非直接刪除", ja: "ファイルを完全削除ではなくゴミ箱に移動", ko: "영구 삭제 대신 휴지통으로 파일 이동", mt: "Move files to Trash instead of permanent delete") }

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
    var preventAutoEmptyTrash: String { t("禁止自动清空回收站", en: "Prevent Auto Empty Trash", zhHant: "禁止自動清空回收站", ja: "ゴミ箱の自動空にを禁止", ko: "휴지통 자동 비우기 금지", mt: "Prevent Auto Empty Trash") }
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
    var all: String { t("全部", en: "All", zhHant: "全部", ja: "すべて", ko: "전체", mt: "All") }
    var actionConfirm: String { t("确认操作", en: "Confirm Action", zhHant: "確認操作", ja: "操作の確認", ko: "작업 확인", mt: "Confirm Action") }
    var actionComplete: String { t("操作完成", en: "Action Complete", zhHant: "操作完成", ja: "操作完了", ko: "작업 완료", mt: "Action Complete") }
    var searchingApps: String { t("搜索应用...", en: "Search apps...", zhHant: "搜尋應用...", ja: "アプリを検索...", ko: "앱 검색...", mt: "Search apps...") }
    var searchingScanning: String { t("正在扫描...", en: "Scanning...", zhHant: "正在掃描...", ja: "スキャン中...", ko: "스캔 중...", mt: "Scanning...") }

    var agentMonitorTitle: String { t("Agent 监控", en: "Agent Monitor", zhHant: "Agent 監控", ja: "Agent モニター", ko: "Agent 모니터", mt: "Agent Monitor") }
    var systemMonitorTitle: String { t("系统监控", en: "System Monitor", zhHant: "系統監控", ja: "システムモニター", ko: "시스템 모니터", mt: "System Monitor") }
    var agentMonitorSubtitle: String { t("监控 AI Agent 的文件操作", en: "Monitor AI Agent file operations", zhHant: "監控 AI Agent 的檔案操作", ja: "AI Agentのファイル操作をモニタリング", ko: "AI Agent 파일 작업 모니터링", mt: "Monitor AI Agent file operations") }
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
    var settingsTabMonitor: String { t("监控", en: "Monitor", zhHant: "監控", ja: "モニター", ko: "모니터", mt: "Monitor") }
    var settingsTabLanguage: String { t("语言", en: "Language", zhHant: "語言", ja: "言語", ko: "언어", mt: "Language") }
    var settingsTabVersion: String { t("版本", en: "Version", zhHant: "版本", ja: "版本", ko: "Version", mt: "Version") }

    var navCleaner: String { t("Mac 清理", en: "Mac Cleaner", zhHant: "Mac 清理", ja: "Mac クリーナー", ko: "Mac 클리너", mt: "Mac Cleaner") }
    var navApp: String { t("APP 管理", en: "App Manager", zhHant: "APP 管理", ja: "アプリ管理", ko: "앱 관리", mt: "App Manager") }
    var navDependency: String { t("依赖管理", en: "Dependency", zhHant: "依賴管理", ja: "依存関係管理", ko: "의존성 관리", mt: "Dependency") }
    var navOther: String { t("其它工具", en: "Other Tools", zhHant: "其它工具", ja: "その他ツール", ko: "기타 도구", mt: "Other Tools") }
    var navOperations: String { t("Agent 监控", en: "Agent Monitor", zhHant: "Agent 監控", ja: "Agent モニター", ko: "Agent 모니터", mt: "Agent Monitor") }

    var subCleaner: String { t("扫描并清理存储空间", en: "Scan and clean storage", zhHant: "掃描並清理儲存空間", ja: "ストレージをスキャンしてクリーンアップ", ko: "저장 공간 스캔 및 정리", mt: "Scan and clean storage") }
    var subApp: String { t("管理已安装的应用", en: "Manage installed apps", zhHant: "管理已安裝的應用", ja: "インストール済みアプリを管理", ko: "설치된 앱 관리", mt: "Manage installed apps") }
    var subDependency: String { t("管理开发依赖", en: "Manage dev dependencies", zhHant: "管理開發依賴", ja: "開発依存関係を管理", ko: "개발 의존성 관리", mt: "Manage dev dependencies") }
    var subOther: String { t("管理命令行工具", en: "Manage CLI tools", zhHant: "管理命令列工具", ja: "CLIツールを管理", ko: "CLI 도구 관리", mt: "Manage CLI tools") }
    var subOperations: String { t("监控 AI Agent 的文件操作", en: "Monitor AI Agent file operations", zhHant: "監控 AI Agent 的檔案操作", ja: "AI Agentのファイル操作をモニタリング", ko: "AI Agent 파일 작업 모니터링", mt: "Monitor AI Agent file operations") }

    var searching: String { t("搜索...", en: "Search...", zhHant: "搜尋...", ja: "検索...", ko: "검색...", mt: "Search...") }
    var notFound: String { t("未发现", en: "Not found", zhHant: "未發現", ja: "見つかりません", ko: "찾을 수 없음", mt: "Not found") }
    var selected: String { t("已选", en: "Selected", zhHant: "已選", ja: "選択済み", ko: "선택됨", mt: "Selected") }
    var selectAllBtn: String { t("全选", en: "Select All", zhHant: "全選", ja: "すべて選択", ko: "전체 선택", mt: "Select All") }
    var cancelBtn: String { t("取消", en: "Cancel", zhHant: "取消", ja: "キャンセル", ko: "취소", mt: "Cancel") }
    var resetAction: String { t("重置", en: "Reset", zhHant: "重置", ja: "リセット", ko: "재설정", mt: "Reset") }
    var basicUninstall: String { t("基础卸载", en: "Basic Uninstall", zhHant: "基礎解除安裝", ja: "基本アンインストール", ko: "기본 제거", mt: "Basic Uninstall") }
    var fullUninstall: String { t("完全卸载", en: "Full Uninstall", zhHant: "完全解除安裝", ja: "完全アンインストール", ko: "완전 제거", mt: "Full Uninstall") }
    var resetDesc: String { t("清除缓存和历史数据，恢复为全新安装状态（APP本身保留）", en: "Clear cache and data, restore to fresh install state", zhHant: "清除快取和歷史資料，恢復為全新安裝狀態（APP本身保留）", ja: "キャッシュとデータをクリアし、新規インストール状態に復元", ko: "캐시와 데이터를 지우고 새 설치 상태로 복원", mt: "Clear cache and data, restore to fresh install state") }
    var basicUninstallDesc: String { t("仅卸载安装文件，保留缓存和历史数据（重新安装后可恢复）", en: "Uninstall only, keep cache and data", zhHant: "僅解除安裝安裝檔案，保留快取和歷史資料（重新安裝後可恢復）", ja: "アンインストールのみ、キャッシュとデータを保持", ko: "제거만 하고 캐시와 데이터 유지", mt: "Uninstall only, keep cache and data") }
    var fullUninstallDesc: String { t("卸载并清除所有缓存、历史数据和配置（彻底清除，不可恢复）", en: "Uninstall and clear all data (permanent)", zhHant: "解除安裝並清除所有快取、歷史資料和配置（徹底清除，不可恢復）", ja: "アンインストールと全データ消去（完全削除、復元不可）", ko: "제거 및 모든 데이터 삭제（영구 삭제, 복원 불가）", mt: "Uninstall and clear all data (permanent)") }
    var confirmAction: String { t("确认操作", en: "Confirm Action", zhHant: "確認操作", ja: "操作の確認", ko: "작업 확인", mt: "Confirm Action") }
    var actionDone: String { t("操作完成", en: "Action Done", zhHant: "操作完成", ja: "操作完了", ko: "작업 완료", mt: "Action Done") }
    var confirmBtn: String { t("确认", en: "Confirm", zhHant: "確認", ja: "確認", ko: "확인", mt: "Confirm") }
    var willAction: String { t("将", en: "Will", zhHant: "將", ja: "実行", ko: "실행", mt: "Will") }
    var total: String { t("共", en: "Total", zhHant: "共", ja: "合計", ko: "총", mt: "Total") }

    var nameCol: String { t("名称", en: "Name", zhHant: "名稱", ja: "名前", ko: "이름", mt: "Name") }
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
    var scanDesc2: String { t("检测哪些需要适配当前 Apple Silicon 芯片", en: "Detect which need adaptation for current Apple Silicon chip", zhHant: "檢測哪些需要適配當前 Apple Silicon 晶片", ja: "現在のApple Siliconチップに適応が必要なものを検出", ko: "현재 Apple Silicon 칩에 적응이 필요한 항목 감지", mt: "Detect which need adaptation for current Apple Silicon chip") }
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
    var localScanSubtitle: String { t("扫描系统缓存、日志等已知可清理目录", en: "Scan known cleanable dirs like system caches, logs", zhHant: "掃描系統快取、日誌等已知可清理目錄", ja: "システムキャッシュやログ等の既知のクリーンアップ可能ディレクトリをスキャン", ko: "시스템 캐시, 로그 등 알려진 정리 가능 디렉토리 스캔", mt: "Scan known cleanable dirs like system caches, logs") }
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
    var configureAPIKeyFirst: String { t("请先配置大模型 API Key", en: "Please configure LLM API Key first", zhHant: "請先配置大模型 API Key", ja: "大規模モデルAPI Keyを先に設定してください", ko: "대규모 모델 API Key를 먼저 설정하세요", mt: "Please configure LLM API Key first") }
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
    var colPath: String { t("路径", en: "Path", zhHant: "路徑", ja: "パス", ko: "경로", mt: "Path") }
    var colSize: String { t("大小", en: "Size", zhHant: "大小", ja: "サイズ", ko: "크기", mt: "Size") }
    var colName: String { t("名称", en: "Name", zhHant: "名稱", ja: "名前", ko: "이름", mt: "Name") }
    var colSource: String { t("来源", en: "Source", zhHant: "來源", ja: "ソース", ko: "소스", mt: "Source") }
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
    var pleaseConfigureAPIKey: String { t("⚠️ 请先配置大模型 API Key", en: "⚠️ Please configure LLM API Key first", zhHant: "⚠️ 請先配置大模型 API Key", ja: "⚠️ 大規模モデルAPI Keyを先に設定してください", ko: "⚠️ 대규모 모델 API Key를 먼저 설정하세요", mt: "⚠️ Please configure LLM API Key first") }
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
    var hourlyTrend: String { t("每小时趋势", en: "Hourly Trend", zhHant: "每小時趨勢", ja: "時間別トレンド", ko: "시간별 추이", mt: "Hourly Trend") }
    var createOps: String { t("创建", en: "Create", zhHant: "建立", ja: "作成", ko: "생성", mt: "Create") }
    var modifyOps: String { t("修改", en: "Modify", zhHant: "修改", ja: "変更", ko: "수정", mt: "Modify") }
    var deleteOps: String { t("删除", en: "Delete", zhHant: "刪除", ja: "削除", ko: "삭제", mt: "Delete") }
    var readOps: String { t("读取", en: "Read", zhHant: "讀取", ja: "読み取り", ko: "읽기", mt: "Read") }
    var operationsUnit: String { t("次操作", en: "ops", zhHant: "次操作", ja: "回操作", ko: "회 작업", mt: "ops") }
    var selectDirectory: String { t("选择目录", en: "Select Directory", zhHant: "選擇目錄", ja: "ディレクトリを選択", ko: "디렉토리 선택", mt: "Select Directory") }
    var navToolbox: String { t("工具箱", en: "Toolbox", zhHant: "工具箱", ja: "ツールボックス", ko: "도구 상자", mt: "Toolbox") }
    var subToolbox: String { t("系统清理与应用管理", en: "System Cleanup & App Management", zhHant: "系統清理與應用管理", ja: "システムクリーンアップ＆アプリ管理", ko: "시스템 정리 및 앱 관리", mt: "System Cleanup & App Management") }
    var commandRules: String { t("命令规则", en: "Cmd Rules", zhHant: "命令規則", ja: "コマンドルール", ko: "명령 규칙", mt: "Cmd Rules") }
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
}
