import SwiftUI

@main
struct MailflareApp: App {
	@State private var store: MailStore
	@State private var updater = AppUpdater()

	init() {
		AppAppearance.applySaved()
		// Before the store opens the mail database, which may still be in the old sandbox container.
		ContainerMigration.run()
		_store = State(initialValue: MailStore())
	}

	var body: some Scene {
		// The mail window. It stays hidden until an account is signed in.
		WindowGroup(id: "main") {
			RootView()
				.environment(store)
				.environment(updater)
				.task { await store.restore() }
				.task { AskPanelController.shared.install(store: store) }
				.task { await store.license.revalidate() }
				.task { await updater.checkPeriodically() }
				.frame(minWidth: 540, minHeight: 560)
		}
		// The window draws its own titlebar band; the content runs to the top of the window.
		.windowStyle(.hiddenTitleBar)
		.windowToolbarStyle(.unifiedCompact)
		.defaultSize(width: 1180, height: 740)
		.commands {
			CommandGroup(replacing: .newItem) {
				Button("New Message") { store.newMessage() }
					.keyboardShortcut("n")
					.disabled(store.phase != .ready)
				Button("Add Account…") { store.showAddAccount = true }
					.disabled(store.phase != .ready)
			}
			CommandMenu("Go") {
				Button("Desk") { store.openScreen(.home) }
					.keyboardShortcut("1").disabled(store.phase != .ready)
				Button("Inbox") { store.openTopItem(.allInboxes) }
					.keyboardShortcut("2").disabled(store.phase != .ready)
				Button("Ask \(SecretarySettings.name)…") { AskPanelController.shared.show(store: store) }
					.keyboardShortcut(" ", modifiers: .option).disabled(store.phase != .ready)
			}
			CommandGroup(replacing: .appSettings) {
				Button("Settings…") { store.settingsPage = store.settingsPage ?? .general }
					.keyboardShortcut(",")
					.disabled(store.phase != .ready)
			}
			CommandGroup(after: .appInfo) {
				Button("Check for Updates…") { Task { await updater.check() } }
			}
		}
		// The envelope in the menu bar: ask from anywhere, even with the window closed.
		MenuBarExtra("SuperMail", systemImage: "envelope") {
			Button("Ask \(SecretarySettings.name)…") { AskPanelController.shared.show(store: store) }
			Button("Open the Desk") {
				store.openScreen(.home)
				NSApp.activate(ignoringOtherApps: true)
			}
		}
	}
}
