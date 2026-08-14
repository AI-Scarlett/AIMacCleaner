import Foundation

struct XcodeCleanRule: Identifiable, Equatable, Sendable {
    let id: String
    let category: XcodeCleanCategory
    let pathPatterns: [String]

    init(id: String, category: XcodeCleanCategory, pathPatterns: [String]) {
        self.id = id
        self.category = category
        self.pathPatterns = pathPatterns
    }
}

struct XcodeCleanRuleCatalog: Equatable, Sendable {
    let rules: [XcodeCleanRule]

    static let allowedRootPrefixes: [String] = [
        "~/Library/Developer/Xcode/",
        "~/Library/Developer/CoreSimulator/Caches/",
        "~/Library/Caches/com.apple.dt.Xcode/"
    ]

    static let defaultCatalog = XcodeCleanRuleCatalog(rules: [
        XcodeCleanRule(
            id: "xcode-clean.derived-data",
            category: .derivedData,
            pathPatterns: ["~/Library/Developer/Xcode/DerivedData/*"]
        ),
        XcodeCleanRule(
            id: "xcode-clean.device-support",
            category: .deviceSupport,
            pathPatterns: [
                "~/Library/Developer/Xcode/iOS DeviceSupport/*",
                "~/Library/Developer/Xcode/tvOS DeviceSupport/*",
                "~/Library/Developer/Xcode/watchOS DeviceSupport/*",
                "~/Library/Developer/Xcode/visionOS DeviceSupport/*",
                "~/Library/Developer/Xcode/macOS DeviceSupport/*"
            ]
        ),
        XcodeCleanRule(
            id: "xcode-clean.archives",
            category: .archives,
            pathPatterns: ["~/Library/Developer/Xcode/Archives/*"]
        ),
        XcodeCleanRule(
            id: "xcode-clean.simulator-caches",
            category: .simulatorCaches,
            pathPatterns: ["~/Library/Developer/CoreSimulator/Caches/*"]
        ),
        XcodeCleanRule(
            id: "xcode-clean.previews",
            category: .previews,
            pathPatterns: ["~/Library/Developer/Xcode/UserData/Previews/*"]
        ),
        XcodeCleanRule(
            id: "xcode-clean.xcode-app-caches",
            category: .xcodeAppCaches,
            pathPatterns: ["~/Library/Caches/com.apple.dt.Xcode/*"]
        )
    ])

    func rules(for category: XcodeCleanCategory) -> [XcodeCleanRule] {
        rules.filter { $0.category == category }
    }
}
