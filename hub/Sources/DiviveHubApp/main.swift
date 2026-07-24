import HubAppUI
import SwiftUI

@main
struct DiviveHubApplication: App {
  var body: some Scene {
    WindowGroup("Divive Hub") {
      HubAppView()
    }
    .defaultSize(width: 1_240, height: 760)
    .windowResizability(.contentMinSize)
  }
}
