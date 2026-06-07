import SwiftData
import SwiftUI

@main
struct SublyApp: App {
    let environment: AppEnvironment

    init() {
        environment = AppEnvironment.live()
        try? environment.bootstrapper.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(environment: environment)
        }
        .modelContainer(environment.modelContainer)
    }
}
