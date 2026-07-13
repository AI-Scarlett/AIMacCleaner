import SwiftUI

@main
struct TraceFenceIOSApp: App {
    @StateObject private var connectionStore = ConnectionStore()
    @StateObject private var securityController = AppSecurityController()

    var body: some Scene {
        WindowGroup {
            AuthenticatedAppRoot()
                .environmentObject(connectionStore)
                .environmentObject(securityController)
        }
    }
}
