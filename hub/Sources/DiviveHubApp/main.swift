import HubAppUI
import SwiftUI

@main
struct DiviveHubApplication: App {
  @StateObject private var model = HubAppModel()

  var body: some Scene {
    WindowGroup(id: "hub-window") {
      HubAppView(model: model)
    }
    .defaultSize(width: 1_240, height: 760)
    .windowResizability(.contentMinSize)
    .windowToolbarStyle(.unified(showsTitle: false))

    MenuBarExtra {
      HubMenuBarContent(model: model)
    } label: {
      HubMenuBarLabel(model: model)
    }
    .menuBarExtraStyle(.window)
  }
}
