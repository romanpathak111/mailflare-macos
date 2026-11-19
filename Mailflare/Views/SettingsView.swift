import SwiftUI
import MailflareCore
import UniformTypeIdentifiers

/// The Settings page in the main card, chosen from the sidebar's settings menu.
struct SettingsView: View {
	@Environment(MailStore.self) private var store
	var page: SettingsPage

	var body: some View {
		if page == .accounts {
			ScrollView {
				VStack(alignment: .leading, spacing: 44) {
					AccountsFoldersPage()
					VStack(alignment: .leading, spacing: 14) {
						Text("More settings").font(.system(size: 20, weight: .bold)).tracking(-0.4).foregroundStyle(Folio.ink)
						AccountSettings()
					}
				}
				.frame(maxWidth: 900, alignment: .leading)
				.padding(.horizontal, 72).padding(.top, 56).padding(.bottom, 40)
				.frame(maxWidth: .infinity, alignment: .leading)
			}
			.background(Folio.card)
		} else if page == .assistant {
			// The Assistant page is laid out as in the mockup: a large title over the full width.
			ScrollView {
				AssistantSettingsPage()
					.frame(maxWidth: 900, alignment: .leading)
					.padding(.horizontal, 72).padding(.top, 56).padding(.bottom, 40)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
			.background(Folio.card)
		} else {
			standardPage
		}
	}

	private var standardPage: some View {
		VStack(spacing: 0) {
			Text(page.title)
				.font(.system(size: 15, weight: .semibold))
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 24)
				.frame(height: PaneHeader.height)
			Rectangle().fill(AppTheme.cardStroke).frame(height: 1)
			ScrollView {
				VStack(alignment: .leading, spacing: 22) {
					switch page {
					case .general: GeneralSettings()
					case .notifications: NotificationSettingsPage()
					case .accounts: AccountSettings()
					case .assistant: AssistantSettingsPage()
					case .ai: AISettingsPage()
					case .mcp: MCPSettingsPage()
					case .license: LicenseSettings()
					case .support: SupportSettings()
					case .about: AboutSettings()
					}
				}
				.frame(maxWidth: 560, alignment: .leading)
				.padding(24)
				.frame(maxWidth: .infinity, alignment: .top)
			}
		}
		.background(AppTheme.background)
	}
}

// MARK: Building blocks

/// A titled card of rows. Rows are separated with `SettingsDivider`, and each brings its own
/// vertical padding, so a single row and a long list both sit evenly.
/// Set by an open dropdown so its group is drawn above the groups after it.
private struct OpenDropdownKey: PreferenceKey {
	static let defaultValue = false
	static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

struct SettingsGroup<Content: View>: View {
	var title: String
	var footer: String?
	@ViewBuilder var content: Content
	@State private var hasOpenDropdown = false

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(title).font(Typography.meta.weight(.medium)).foregroundStyle(.secondary)
			VStack(alignment: .leading, spacing: 0) { content }
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 14)
				.background(AppTheme.composerContextFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			if let footer {
				Text(footer).font(Typography.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
			}
		}
		.onPreferenceChange(OpenDropdownKey.self) { hasOpenDropdown = $0 }
		.zIndex(hasOpenDropdown ? 10 : 0)
	}
}

struct SettingsDivider: View {
	var body: some View { Rectangle().fill(AppTheme.cardStroke).frame(height: 1) }
}

/// One line of a group: content with the group's row padding.
struct SettingsRow<Content: View>: View {
	@ViewBuilder var content: Content

	var body: some View {
		HStack(spacing: 10) { content }
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.vertical, 12)
	}
}

/// The label on the left, the switch on the right.
private struct SettingsToggle: View {
	var title: String
	var detail: String?
	@Binding var isOn: Bool

	var body: some View {
		SettingsRow {
			VStack(alignment: .leading, spacing: 2) {
				Text(title).font(Typography.body)
				if let detail {
					Text(detail).font(Typography.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
				}
			}
			Spacer(minLength: 12)
			Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch)
		}
	}
}

/// A choice drawn as its current value and a chevron; opening it drops a card like the account
/// dropdown's, with a check on the chosen row.
struct SettingsPicker<Value: Hashable>: View {
	var title: String
	var options: [(label: String, value: Value)]
	@Binding var selection: Value
	/// For lists fetched on demand: shown instead of the options, as skeleton rows, while they load.
	var isLoading = false
	/// Called each time the dropdown opens, so a list can start loading then.
	var onOpen: (() -> Void)?
	var maxHeight: CGFloat = 280
	/// The label when `selection` is not among the options (yet).
	var fallbackLabel: String?
	@State private var isOpen = false
	@State private var isHovering = false
	@State private var query = ""

	/// The options whose label contains what was typed, all of them when nothing was.
	private var matches: [Int] {
		let q = query.trimmingCharacters(in: .whitespaces).lowercased()
		guard !q.isEmpty else { return Array(options.indices) }
		return options.indices.filter { options[$0].label.lowercased().contains(q) }
	}

	private var selectedIndex: Int? { options.firstIndex { $0.value == selection } }

	private var currentLabel: String { options.first { $0.value == selection }?.label ?? fallbackLabel ?? "" }

	var body: some View {
		SettingsRow {
			Text(title).font(Typography.body)
			Spacer(minLength: 12)
			Button {
				withAnimation(.snappy(duration: 0.2)) { isOpen.toggle() }
				if isOpen { onOpen?() }
			} label: {
				HStack(spacing: 6) {
					Text(currentLabel).font(Typography.body)
					HIcon(.chevronDown, size: 12).foregroundStyle(.secondary)
						.rotationEffect(.degrees(isOpen ? 180 : 0))
				}
				.padding(.horizontal, 8).padding(.vertical, 4)
				.background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(isHovering || isOpen ? AppTheme.rowHighlight : .clear))
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.onHover { isHovering = $0 }
			.overlay(alignment: .topTrailing) {
				if isOpen { dropdown.offset(y: 32) }
			}
			// A click anywhere else closes it.
			.clickAway(isActive: isOpen) { withAnimation(.snappy(duration: 0.2)) { isOpen = false } }
		}
		.zIndex(isOpen ? 10 : 0)
		.preference(key: OpenDropdownKey.self, value: isOpen)
		.onChange(of: isOpen) { _, _ in query = "" }
	}

	private var dropdown: some View {
		DropdownCard(width: 190) {
			if isLoading {
				DropdownScroll(maxHeight: maxHeight) {
					ForEach(0..<5, id: \.self) { _ in
						SkeletonBar(height: 12).padding(.horizontal, 10).padding(.vertical, 9)
					}
				}
			} else {
				// Worked out once here: asking per row would scan the whole list for every row.
				let shown = matches
				if options.count > 8 {
					DropdownSearchField(text: $query) {
						if let first = shown.first { selection = options[first].value; withAnimation(.snappy(duration: 0.2)) { isOpen = false } }
					}
				}
				DropdownScroll(maxHeight: maxHeight, target: query.isEmpty ? selectedIndex.map(String.init) : nil) {
					if shown.isEmpty { DropdownNoResults() }
					ForEach(shown, id: \.self) { index in
						DropdownRow(label: options[index].label, isSelected: options[index].value == selection) {
							selection = options[index].value
							withAnimation(.snappy(duration: 0.2)) { isOpen = false }
						}
						.id(String(index))
					}
				}
			}
		}
	}
}

/// A model choice. With one provider the dropdown lists its models; with several it lists the
/// providers first, and choosing one swaps the list for that provider's models.
private struct ModelPickerRow: View {
	var title: String
	var providers: [AIProviderConfig]
	var selection: AISettings.ModelChoice?
	/// When set, a first row that clears the choice (nil), labelled with this.
	var defaultLabel: String?
	var onSelect: (AISettings.ModelChoice?) -> Void

	@State private var isOpen = false
	@State private var isHovering = false
	@State private var drilled: String?
	@State private var query = ""

	private var multiple: Bool { providers.count > 1 }

	private var currentLabel: String {
		guard let selection else { return defaultLabel ?? "" }
		let name = providers.first { $0.id == selection.providerID }?.name
		return multiple ? "\(name.map { $0 + " · " } ?? "")\(selection.model)" : selection.model
	}

	var body: some View {
		SettingsRow {
			Text(title).font(Typography.body)
			Spacer(minLength: 12)
			Button {
				withAnimation(.snappy(duration: 0.2)) { isOpen.toggle() }
			} label: {
				HStack(spacing: 6) {
					Text(currentLabel).font(Typography.body).lineLimit(1).truncationMode(.middle)
						.frame(maxWidth: 300, alignment: .trailing).fixedSize(horizontal: true, vertical: false)
					HIcon(.chevronDown, size: 12).foregroundStyle(.secondary).rotationEffect(.degrees(isOpen ? 180 : 0))
				}
				.padding(.horizontal, 8).padding(.vertical, 4)
				.background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(isHovering || isOpen ? AppTheme.rowHighlight : .clear))
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.onHover { isHovering = $0 }
			.overlay(alignment: .topTrailing) {
				if isOpen { dropdown.offset(y: 32) }
			}
			.clickAway(isActive: isOpen) { close() }
		}
		.zIndex(isOpen ? 10 : 0)
		.preference(key: OpenDropdownKey.self, value: isOpen)
		.onChange(of: isOpen) { _, _ in drilled = nil; query = "" }
	}

	private func close() { withAnimation(.snappy(duration: 0.2)) { isOpen = false } }

	private func choose(_ choice: AISettings.ModelChoice?) {
		onSelect(choice)
		close()
	}

	private var dropdown: some View {
		DropdownCard(width: 240) {
			if let defaultLabel, drilled == nil {
				DropdownRow(label: defaultLabel, isSelected: selection == nil) { choose(nil) }
			}
			if multiple && drilled == nil {
				ForEach(providers) { provider in
					DropdownRow(label: provider.name, isSelected: selection?.providerID == provider.id, trailing: .chevronRight) {
						withAnimation(.snappy(duration: 0.2)) { query = ""; drilled = provider.id }
					}
				}
			} else if let provider = providers.first(where: { $0.id == drilled }) ?? (multiple ? nil : providers.first) {
				let q = query.trimmingCharacters(in: .whitespaces).lowercased()
				let models = q.isEmpty ? provider.choices : provider.choices.filter { $0.lowercased().contains(q) }
				if multiple {
					DropdownRow(label: provider.name, icon: .arrowLeft) { withAnimation(.snappy(duration: 0.2)) { drilled = nil } }
					DropdownDivider()
				}
				if provider.choices.count > 8 {
					DropdownSearchField(text: $query) {
						if let first = models.first { choose(.init(providerID: provider.id, model: first)) }
					}
				}
				let current = selection?.providerID == provider.id ? selection?.model : nil
				DropdownScroll(maxHeight: 220, target: q.isEmpty ? current : nil) {
					if models.isEmpty { DropdownNoResults() }
					ForEach(models, id: \.self) { model in
						DropdownRow(label: model, isSelected: model == current) { choose(.init(providerID: provider.id, model: model)) }
							.id(model)
					}
				}
			}
		}
	}
}

/// A button as wide as the page, outside any group.
struct WideButton: View {
	var title: String
	var icon: AppIcon?
	var prominent = false
	var action: () -> Void

	var body: some View {
		Button(action: action) {
			HStack(spacing: 6) {
				if let icon { HIcon(icon, size: 14) }
				Text(title)
			}
			.frame(maxWidth: .infinity)
			.padding(.vertical, 7)
		}
		.buttonStyle(PillButtonStyle(prominent: prominent))
	}
}

// MARK: Pages

private struct GeneralSettings: View {
	@AppStorage(ReadingSettings.autoCheckUpdatesKey) private var autoCheck = true
	@AppStorage(AppAppearance.key) private var appearance = AppAppearance.system.rawValue
	@AppStorage(MessageAppearance.adaptKey) private var adaptColors = true
	@AppStorage(ReadingSettings.markReadDelayKey) private var markReadDelay = 0
	@AppStorage(ReadingSettings.loadRemoteContentKey) private var loadRemote = true
	@AppStorage(ReadingSettings.showAvatarsKey) private var showAvatars = true
	@State private var launchAtLogin = LaunchAtLogin.isEnabled

	var body: some View {
		SettingsGroup(title: "Startup & Updates") {
			SettingsToggle(title: "Open SuperMail at login", isOn: Binding(
				get: { launchAtLogin },
				set: { launchAtLogin = $0; if !LaunchAtLogin.set($0) { launchAtLogin = LaunchAtLogin.isEnabled } }
			))
			SettingsDivider()
			SettingsToggle(
				title: "Check for updates automatically",
				detail: "New versions come from the SuperMail releases on GitHub.",
				isOn: $autoCheck)
		}
		SettingsGroup(title: "Appearance") {
			SettingsPicker(
				title: "Theme",
				options: AppAppearance.allCases.map { ($0.title, $0.rawValue) },
				selection: $appearance)
			SettingsDivider()
			SettingsToggle(
				title: "Adapt message colors in dark mode",
				detail: "Re-colors mail that has no dark styles of its own. The reader's color button overrides it per sender.",
				isOn: $adaptColors)
		}
		SettingsGroup(title: "Emails") {
			SettingsToggle(
				title: "Show avatars in the email list",
				detail: "A sender's Gravatar, or their initial on a colored circle.",
				isOn: $showAvatars)
			SettingsDivider()
			SettingsPicker(
				title: "Mark as read",
				options: [("Immediately", 0), ("After 3 seconds", 3), ("After 10 seconds", 10), ("Never", -1)],
				selection: $markReadDelay)
			SettingsDivider()
			SettingsToggle(
				title: "Load remote content",
				detail: "Images, styles and fonts a message loads from the internet. Always blocked in Spam.",
				isOn: $loadRemote)
		}
		SettingsGroup(title: "Storage") {
			Text("Sync checks the newest 50 messages per folder. Older messages are cached as you browse. The unread filter shows mail already on this Mac.")
				.font(Typography.meta).foregroundStyle(.secondary)
				.padding(.horizontal, 14).padding(.vertical, 10)
		}
		.onChange(of: appearance) { _, value in (AppAppearance(rawValue: value) ?? .system).apply() }
	}
}

private struct NotificationSettingsPage: View {
	@Environment(MailStore.self) private var store
	@AppStorage(NotificationSettings.enabledKey) private var enabled = true
	@AppStorage(NotificationSettings.previewsKey) private var previews = true
	@AppStorage(NotificationSettings.soundKey) private var sound = true
	@AppStorage(NotificationSettings.badgeKey) private var badge = true

	/// On means macOS allows Mailflare's notifications and the app has not muted them itself.
	private var allowSwitch: Binding<Bool> {
		Binding(
			get: { enabled && store.notifier.isAllowed },
			set: { on in
				enabled = on
				guard on else { return }
				switch store.notifier.authorization {
				case .notDetermined: Task { await store.notifier.requestAuthorization() }
				case .denied: MailNotifier.openSystemSettings()
				default: break
				}
			})
	}

	private var allowDetail: String {
		switch store.notifier.authorization {
		case .denied: "Turned off for SuperMail in System Settings. Turn it on there, then come back."
		case .notDetermined: "SuperMail will ask macOS for permission."
		default: "Alert on new mail in any account's inbox. Turning this off stops SuperMail's alerts; macOS's own setting stays as it is."
		}
	}

	var body: some View {
		SettingsGroup(title: "Notifications", footer: "SuperMail checks every account for new mail about once a minute while it is open. Each account can be muted on its page under Accounts.") {
			SettingsToggle(title: "Allow notifications", detail: allowDetail, isOn: allowSwitch)
			SettingsDivider()
			SettingsRow {
				Text("Banner style and sounds for SuperMail are also managed by macOS.")
					.font(Typography.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
				Spacer(minLength: 8)
				Button("Open System Settings") { MailNotifier.openSystemSettings() }
					.buttonStyle(.pill)
			}
			SettingsDivider()
			SettingsToggle(title: "Show previews", detail: "Include the sender and subject. Off, a notification only says there is new mail.", isOn: $previews)
				.disabled(!allowSwitch.wrappedValue)
			SettingsDivider()
			SettingsToggle(title: "Play a sound", isOn: $sound)
				.disabled(!allowSwitch.wrappedValue)
			SettingsDivider()
			SettingsToggle(title: "Show unread count on the Dock icon", isOn: $badge)
		}
		.onChange(of: badge) { _, _ in store.updateBadge() }
		.task { await store.notifier.refreshAuthorization() }
		// The user may have changed it in System Settings while Mailflare was in the background.
		.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
			Task { await store.notifier.refreshAuthorization() }
		}
	}
}

/// The Accounts page: a menu of three tabs, Organize, Accounts and Inbox Views.
private struct AccountSettings: View {
	private enum Tab: String, CaseIterable, Identifiable {
		case accounts = "Accounts", folders = "Folders", organize = "Organize", views = "Inbox Views", tabs = "Custom Tabs"
		var id: String { rawValue }
	}

	@State private var tab: Tab = .accounts

	var body: some View {
		VStack(alignment: .leading, spacing: 22) {
			HStack(spacing: 2) {
				ForEach(Tab.allCases) { item in
					Button { tab = item } label: {
						Text(item.rawValue).font(Typography.body)
							.foregroundStyle(tab == item ? Color.primary : Color.secondary)
							.padding(.horizontal, 12).padding(.vertical, 6)
							.background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tab == item ? AppTheme.railSelection : .clear))
							.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
				}
				Spacer(minLength: 0)
			}
			switch tab {
			case .organize: OrganizeTab()
			case .accounts: AccountsTab()
			case .folders: FoldersTab()
			case .views: InboxViewsTab()
			case .tabs: CustomTabsTab()
			}
		}
	}
}

/// Which views the sidebar lists, for the Unified section and for each account alike, and which
/// accounts Unified draws from.
private struct OrganizeTab: View {
	@Environment(MailStore.self) private var store

	var body: some View {
		VStack(alignment: .leading, spacing: 22) {
			SettingsGroup(title: "Views", footer: "On: listed below Today for everything in the account dropdown. Off: listed in the section of each inbox instead.") {
				ForEach(Array(UnifiedViewKind.allCases.enumerated()), id: \.element.id) { index, kind in
					if index > 0 { SettingsDivider() }
					SettingsRow {
						HIcon(kind.icon, size: 16).foregroundStyle(.secondary).frame(width: 22)
						Text(kind.title).font(Typography.body)
						Spacer(minLength: 12)
						Toggle("", isOn: Binding(get: { store.unifiedShows(kind) }, set: { store.setUnified(kind, shown: $0) }))
							.labelsHidden().toggleStyle(.switch)
					}
				}
			}
		}
	}
}

/// Tabs under Today in the sidebar: Today itself, which is fixed, and the ones made here.
private struct CustomTabsTab: View {
	@Environment(MailStore.self) private var store

	var body: some View {
		VStack(alignment: .leading, spacing: 22) {
			SettingsGroup(title: "Built in") {
				row(.today) { Text("Built in").font(Typography.meta).foregroundStyle(.tertiary) }
			}
			SettingsGroup(
				title: "Custom Tabs",
				footer: "Tabs are listed under Today and show the Inbox mail that matches their rules, with the unread count beside them. The newest 1,000 messages of each inbox are checked."
			) {
				if store.customTabs.isEmpty {
					SettingsRow { Text("No custom tabs yet").font(Typography.body).foregroundStyle(.secondary) }
				}
				ForEach(Array(store.customTabs.enumerated()), id: \.element.id) { index, tab in
					if index > 0 { SettingsDivider() }
					row(tab) {
						Button("Edit") { store.customTabEditor = tab }.buttonStyle(.pill)
						Button("Delete") { store.deleteCustomTab(tab.id) }.buttonStyle(.pill).foregroundStyle(.red)
					}
				}
			}
			WideButton(title: "New Custom Tab", icon: .add) { store.customTabEditor = CustomTab(rules: [CustomTab.Rule(kind: .from)]) }
		}
	}

	private func row<Trailing: View>(_ tab: CustomTab, @ViewBuilder trailing: () -> Trailing) -> some View {
		SettingsRow {
			HIcon(tab.appIcon, size: 16).foregroundStyle(.secondary).frame(width: 22)
			VStack(alignment: .leading, spacing: 1) {
				Text(tab.name).font(Typography.bodySemibold).lineLimit(1)
				Text(tab.summary.prefix(1).uppercased() + tab.summary.dropFirst()).font(Typography.meta).foregroundStyle(.secondary).lineLimit(2)
			}
			Spacer(minLength: 8)
			trailing()
		}
	}
}

/// Custom inboxes that combine chosen accounts and inboxes.
private struct InboxViewsTab: View {
	@Environment(MailStore.self) private var store

	var body: some View {
		VStack(alignment: .leading, spacing: 22) {
			SettingsGroup(title: "Unified Inbox") {
				ForEach(Array(store.accountList.enumerated()), id: \.element.id) { index, account in
					let isOn = store.unifiedIncludes(account.id)
					if index > 0 { SettingsDivider() }
					SettingsRow {
						ProfileAvatar(key: AvatarCache.key(account: account.id), name: store.accountName(account), size: 28)
						VStack(alignment: .leading, spacing: 1) {
							Text(store.accountName(account)).font(Typography.body).lineLimit(1)
							Text(account.email).font(Typography.meta).foregroundStyle(.secondary).lineLimit(1)
						}
						Spacer(minLength: 12)
						Toggle("", isOn: Binding(get: { isOn }, set: { store.setUnified(account.id, included: $0) }))
							.labelsHidden().toggleStyle(.switch)
							.disabled(isOn && store.unifiedIncludedCount <= 1)
					}
				}
			}
			if store.inboxViews.isEmpty {
				SettingsGroup(title: "Custom Inboxes View", footer: "An inbox view combines the accounts and inboxes you choose into one list.") {
					SettingsRow {
						Text("No inbox views yet").font(Typography.body).foregroundStyle(.secondary)
					}
				}
			} else {
				SettingsGroup(title: "Inbox Views") {
					ForEach(Array(store.inboxViews.enumerated()), id: \.element.id) { index, view in
						if index > 0 { SettingsDivider() }
						SettingsRow {
							VStack(alignment: .leading, spacing: 1) {
								Text(view.name).font(Typography.bodySemibold).lineLimit(1)
								let inboxes = view.members.count, accounts = view.accountIDs.count
								Text("\(inboxes) inbox\(inboxes == 1 ? "" : "es") · \(accounts) account\(accounts == 1 ? "" : "s")")
									.font(Typography.meta).foregroundStyle(.secondary)
							}
							Spacer(minLength: 8)
							Button("Edit") { store.inboxViewEditor = view }.buttonStyle(.pill)
							Button("Delete") { store.deleteInboxView(view.id) }.buttonStyle(.pill).foregroundStyle(.red)
						}
					}
				}
			}
			WideButton(title: "New Inbox View", icon: .add) { store.inboxViewEditor = InboxView() }
		}
	}
}

/// Every account's folders (labels on Gmail) in one place: pick each one's colour, rename, delete or add.
private struct FoldersTab: View {
	@Environment(MailStore.self) private var store

	var body: some View {
		VStack(alignment: .leading, spacing: 22) {
			Text("Folders belong to an account. Statuses work across all of them, so a conversation keeps its status in any folder.")
				.font(Typography.notice).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
			ForEach(store.accountList) { account in
				let gmail = store.isGmailAccount(account)
				let noun = gmail ? "Label" : "Folder"
				let folders = store.customFolders(of: account.id)
				let support = store.folderSupport(accountID: account.id)
				SettingsGroup(title: "\(store.accountName(account)) · \(account.email)") {
					if folders.isEmpty {
						SettingsRow {
							Text("No \(noun.lowercased())s yet").font(Typography.body).foregroundStyle(.secondary)
							Spacer(minLength: 0)
						}
					}
					ForEach(Array(folders.enumerated()), id: \.element.id) { index, box in
						if index > 0 { SettingsDivider() }
						SettingsRow {
							colorMenu(for: box)
							Text(box.name).font(Typography.body).lineLimit(1)
							Spacer(minLength: 8)
							if box.unreadEmails > 0 { CountBadge(count: Int(box.unreadEmails)) }
							if support?.canRename == true {
								Button("Rename") { store.folderRequest = .init(accountID: account.id, kind: .rename(box)) }.buttonStyle(.pill)
							}
							if support?.canDelete == true {
								Button("Delete") { store.folderRequest = .init(accountID: account.id, kind: .delete(box)) }
									.buttonStyle(.pill).foregroundStyle(.red)
							}
						}
					}
				}
				if store.canCreateFolders(accountID: account.id) {
					WideButton(title: "New \(noun)", icon: .add) {
						store.folderRequest = .init(accountID: account.id, kind: .create(parentID: store.inboxAddresses(of: account.id).first?.id))
					}
				}
			}
		}
	}

	/// The folder's icon in its colour; opening it offers the palette.
	private func colorMenu(for box: Mailbox) -> some View {
		Menu {
			ForEach(Array(FolderColors.swatches.enumerated()), id: \.element.id) { index, swatch in
				Button { store.folderColors.set(index, for: box.id) } label: {
					Text(store.folderColors.index(for: box.id) == index ? "✓  \(swatch.name)" : swatch.name)
				}
			}
		} label: {
			HIcon(.folder, size: 17).foregroundStyle(store.folderColors.color(for: box.id)).frame(width: 26, height: 26).contentShape(Rectangle())
		}
		.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
		.help("Folder colour")
	}
}

private struct AccountsTab: View {
	@Environment(MailStore.self) private var store
	/// The account whose page is open; nil shows the list. The page slides in from the right.
	@State private var openID: String?
	/// The account waiting on the sign-out confirmation.
	@State private var signingOut: Account?

	var body: some View {
		ZStack(alignment: .top) {
			if let account = store.accountList.first(where: { $0.id == openID }) {
				AccountDetail(account: account) { withAnimation(.snappy(duration: 0.25)) { openID = nil } }
					.transition(.move(edge: .trailing).combined(with: .opacity))
			} else {
				list.transition(.move(edge: .leading).combined(with: .opacity))
			}
		}
		.frame(maxWidth: .infinity, alignment: .top)
		.clipped()
		.confirmationDialog(
			signingOut.map { "Sign out of \($0.email)?" } ?? "Sign out?",
			isPresented: Binding(get: { signingOut != nil }, set: { if !$0 { signingOut = nil } }),
			titleVisibility: .visible,
			presenting: signingOut
		) { account in
			Button("Sign Out", role: .destructive) { store.signOut(account) }
		} message: { _ in
			Text("Its saved mail and any unsent changes are removed from this Mac. Mail on the server is not affected.")
		}
	}

	private var list: some View {
		VStack(alignment: .leading, spacing: 22) {
			SettingsGroup(title: "Accounts") {
				ForEach(Array(store.accountList.enumerated()), id: \.element.id) { index, account in
					if index > 0 { SettingsDivider() }
					SettingsRow {
						Button { withAnimation(.snappy(duration: 0.25)) { openID = account.id } } label: {
							HStack(spacing: 10) {
								ProfileAvatar(key: AvatarCache.key(account: account.id), name: store.accountName(account), size: 32)
								VStack(alignment: .leading, spacing: 1) {
									Text(store.accountName(account)).font(Typography.bodySemibold).lineLimit(1)
									HStack(spacing: 6) {
										Text(account.email).font(Typography.meta).foregroundStyle(.secondary).lineLimit(1)
										if KeychainCredentialStore().load(accountId: account.id) == nil {
											Text("Needs sign-in").font(Typography.meta.weight(.semibold)).foregroundStyle(ThreadStatus.waiting.ink)
												.padding(.horizontal, 7).padding(.vertical, 1).background(Capsule().fill(ThreadStatus.waiting.tint))
										} else {
											let unread = store.unreadCount(accountID: account.id, inbox: nil)
											if unread > 0 { Text("\(unread) unread").font(Typography.meta).foregroundStyle(.secondary) }
										}
									}
								}
								Spacer(minLength: 8)
							}
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
						if KeychainCredentialStore().load(accountId: account.id) == nil {
							Button("Sign in again") { store.showAddAccount = true }.buttonStyle(AccentPillStyle())
						}
						Button("Sign Out") { signingOut = account }
							.buttonStyle(.pill).foregroundStyle(.red)
						Button { withAnimation(.snappy(duration: 0.25)) { openID = account.id } } label: {
							HIcon(.chevronRight, size: 12).foregroundStyle(.secondary).contentShape(Rectangle())
						}
						.buttonStyle(.plain)
					}
				}
			}
			WideButton(title: "Add Account", icon: .add) { store.showAddAccount = true }
		}
	}
}

/// One account: its picture, name and signature.
private struct AccountDetail: View {
	@Environment(MailStore.self) private var store
	var account: Account
	var back: () -> Void

	@State private var name = ""
	@State private var signature = ""
	@State private var loaded = false
	@State private var saving = false
	@State private var note: String?

	private var profiles: AccountProfiles { store.profiles }
	private var key: String { AvatarCache.key(account: account.id) }
	private var remote: AccountProfiles.Remote? { profiles.remote[account.id] }
	private var savedName: String { store.accountName(account) }
	private var savedSignature: String { profiles.signature(account.id) }

	private var isDirty: Bool {
		name.trimmingCharacters(in: .whitespacesAndNewlines) != savedName
			|| signature.trimmingCharacters(in: .whitespacesAndNewlines) != savedSignature
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 22) {
			Button(action: back) {
				HStack(spacing: 6) {
					HIcon(.arrowLeft, size: 13)
					Text("Accounts").font(Typography.body)
				}
				.foregroundStyle(.secondary)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)

			HStack(spacing: 16) {
				ProfileAvatar(key: key, name: name.isEmpty ? savedName : name, size: 72)
				VStack(alignment: .leading, spacing: 8) {
					Text(account.email).font(Typography.meta).foregroundStyle(.secondary).lineLimit(1)
					HStack(spacing: 8) {
						Button("Choose Picture…", action: choosePicture).buttonStyle(.pill)
						if store.avatars.hasLocal(key) {
							Button("Remove") { store.avatars.removeLocal(key: key); store.loadAvatars(for: account) }.buttonStyle(.pill)
						}
					}
				}
				Spacer(minLength: 0)
			}

			SettingsGroup(title: "Profile") {
				SettingsRow {
					Text("Name").font(Typography.body)
					Spacer(minLength: 12)
					TextField("Your name", text: $name)
						.textFieldStyle(.plain).multilineTextAlignment(.trailing).font(Typography.body)
				}
				SettingsDivider()
				SettingsRow {
					Text("Email").font(Typography.body)
					Spacer(minLength: 12)
					Text(account.email).font(Typography.body).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
				}
			}

			SettingsGroup(title: "Notifications", footer: "Off: no system notification for new mail in this account. Its mail still arrives and counts toward the Dock badge.") {
				SettingsToggle(title: "Notify about new mail", isOn: Binding(
					get: { store.notifier.notifies(account.id) },
					set: { store.notifier.setNotifies($0, accountID: account.id) }))
			}

			SettingsGroup(title: "Signature", footer: signatureFooter) {
				TextEditor(text: $signature)
					.font(Typography.body)
					.scrollContentBackground(.hidden)
					.frame(minHeight: 96)
					.padding(.vertical, 8)
			}

			HStack(spacing: 8) {
				if saving { ProgressView().controlSize(.small) }
				Spacer()
				Button("Revert") { fill() }.buttonStyle(.pill).disabled(!isDirty || saving)
				Button("Save", action: save).buttonStyle(.pillProminent).disabled(!isDirty || saving)
			}
			if let note {
				Text(note).font(Typography.meta).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
			}

			WideButton(title: "Sign Out") { store.signOut(account) }
		}
		.task {
			fill()
			await profiles.refresh(account)
			// Take the server's values unless the user has started typing.
			if !isDirty { fill() }
			loaded = true
		}
	}

	private var signatureFooter: String {
		var text = profiles.hasSignature(account.id)
			? "Added to new messages, replies and forwards from this account."
			: "No signature is set, so “\(AccountProfiles.defaultSignature)” is added to new messages. Write your own to replace it."
		if remote?.editable == false { text += " Your server doesn't allow edits, so changes stay on this Mac." }
		return text
	}

	private func fill() {
		name = savedName
		signature = savedSignature
		note = nil
	}

	private func save() {
		saving = true; note = nil
		let name = name, signature = signature
		Task {
			note = await profiles.save(account, name: name, signature: signature)
			saving = false
			fill()
			if let kept = note { note = kept }
		}
	}

	private func choosePicture() {
		let panel = NSOpenPanel()
		panel.allowedContentTypes = [.image]
		panel.allowsMultipleSelection = false
		panel.message = "Choose a picture for \(savedName)"
		guard panel.runModal() == .OK, let url = panel.url else { return }
		if !store.avatars.setLocal(key: key, from: url) { note = "That file couldn't be read as a picture." }
	}
}

/// Connect Claude or Codex, and choose what the assistant does with statuses. Each service is one
/// provider of the AI Providers page: connecting adds it with its key, which stays in the Keychain.
private struct AssistantSettingsPage: View {
	@Environment(MailStore.self) private var store
	@AppStorage(AssistantSettings.suggestStatusKey) private var suggestStatus = true
	@AppStorage(AssistantSettings.draftRepliesKey) private var draftReplies = true
	@AppStorage(AssistantSettings.todayBriefKey) private var todayBrief = true
	@AppStorage(AssistantSettings.autoArchiveKey) private var autoArchive = false
	@AppStorage(AssistantSettings.suggestFoldersKey) private var suggestFolders = true
	@State private var modelCache: [String: [String]] = [:]
	@State private var editing: AIProviderConfig?
	@State private var editingIsNew = false
	@State private var keyText = ""

	private var ai: AISettings { store.ai }

	private struct Service: Identifiable {
		var preset: AIProviderPreset
		var name: String
		var maker: String
		var icon: AppIcon
		var id: String { preset.rawValue }
	}

	private let services = [
		Service(preset: .claudeCLI, name: "Claude", maker: "Claude Code on this Mac", icon: .sparkles),
		Service(preset: .codexCLI, name: "Codex", maker: "Codex CLI on this Mac", icon: .sourceCode),
		Service(preset: .appleIntelligence, name: "Apple Intelligence", maker: "Apple's model, on this Mac", icon: .aiContent),
	]

	var body: some View {
		VStack(alignment: .leading, spacing: 36) {
			VStack(alignment: .leading, spacing: 10) {
				Text("Assistant").font(.system(size: 36, weight: .bold)).tracking(-1.25).foregroundStyle(Folio.ink)
				Text("The assistant runs Claude Code or Codex on this Mac with the account you already pay for, so no API key is needed. It suggests a status for each thread, drafts replies and writes your Today brief, using your plan.")
					.font(.system(size: 16)).lineSpacing(4).foregroundStyle(Folio.body)
					.frame(maxWidth: 640, alignment: .leading).fixedSize(horizontal: false, vertical: true)
			}
			HStack(alignment: .top, spacing: 16) {
				ForEach(services) { card($0) }
			}
			whoDoesWhat
			VStack(alignment: .leading, spacing: 0) {
				Text("What the assistant does").font(.system(size: 20, weight: .bold)).tracking(-0.4).foregroundStyle(Folio.ink)
					.padding(.bottom, 12)
				behaviour("Suggest a status for new mail", "Proposes Needs reply, Waiting, Can archive or Long-term value. You confirm.", $suggestStatus)
				behaviour("Suggest folder rules", "Learns where you file mail and offers to file it for you. You approve each rule.", $suggestFolders)
				behaviour("Draft replies", "Prepares a short reply for threads marked Needs reply.", $draftReplies)
				behaviour("Write the Today brief", "Summarises what needs you and who is waiting on you each morning.", $todayBrief)
				behaviour("Archive without asking", "Moves Can archive threads to Archive on its own. Off by default.", $autoArchive)
				Rectangle().fill(Folio.line).frame(height: 1)
			}
			Text("\(store.displayBrandName) sends only the threads the assistant needs to your connected account. You can disconnect at any time.")
				.font(.system(size: 13)).lineSpacing(3).foregroundStyle(Folio.meta)
				.frame(maxWidth: 640, alignment: .leading).fixedSize(horizontal: false, vertical: true)
			if ai.providers.count > 0 {
				Button("More providers and models…") { store.settingsPage = .ai }
					.buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Folio.selectionInk)
			}
		}
	}

	/// Which assistant chats and drafts, and which one sorts mail in the background.
	@ViewBuilder
	private var whoDoesWhat: some View {
		if ai.readyProviders.count > 1 {
			VStack(alignment: .leading, spacing: 0) {
				Text("Who does what").font(.system(size: 20, weight: .bold)).tracking(-0.4).foregroundStyle(Folio.ink).padding(.bottom, 12)
				roleRow("Chat, replies and MCP", "The assistant panel and suggested replies.", current: ai.active) { p in
					ai.select(providerID: p.id, model: p.model)
				}
				roleRow("Sorting, suggestions and summaries", "Runs in the background as mail arrives. Apple Intelligence is instant, free and private.", current: ai.backgroundProvider) { p in
					ai.selectBackground(p.id)
				}
				Rectangle().fill(Folio.line).frame(height: 1)
			}
		}
	}

	private func roleRow(_ title: String, _ detail: String, current: AIProviderConfig?, choose: @escaping (AIProviderConfig) -> Void) -> some View {
		VStack(spacing: 0) {
			Rectangle().fill(Folio.line).frame(height: 1)
			HStack(spacing: 20) {
				VStack(alignment: .leading, spacing: 2) {
					Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Folio.ink)
					Text(detail).font(.system(size: 13)).foregroundStyle(Folio.meta).fixedSize(horizontal: false, vertical: true)
				}
				Spacer(minLength: 12)
				Menu {
					ForEach(ai.readyProviders) { p in
						Button((p.id == current?.id ? "✓  " : "") + (p.preset.isOnThisMac ? p.preset.title.replacingOccurrences(of: " (this Mac)", with: "") : p.name)) { choose(p) }
					}
				} label: {
					HStack(spacing: 8) {
						Text(current.map { $0.preset.isOnThisMac ? $0.preset.title.replacingOccurrences(of: " (this Mac)", with: "") : $0.name } ?? "None")
							.font(.system(size: 14, weight: .semibold)).foregroundStyle(Folio.body)
						HIcon(.chevronDown, size: 12).foregroundStyle(Folio.meta)
					}
					.padding(.horizontal, 14).frame(height: 36)
					.background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Folio.card))
					.overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Folio.line, lineWidth: 1))
				}
				.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
			}
			.frame(minHeight: 64)
		}
	}

	private func behaviour(_ title: String, _ detail: String, _ isOn: Binding<Bool>) -> some View {
		VStack(spacing: 0) {
			Rectangle().fill(Folio.line).frame(height: 1)
			HStack(spacing: 20) {
				VStack(alignment: .leading, spacing: 2) {
					Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Folio.ink)
					Text(detail).font(.system(size: 13)).foregroundStyle(Folio.meta).fixedSize(horizontal: false, vertical: true)
				}
				Spacer(minLength: 12)
				Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).tint(Folio.accent).controlSize(.large)
			}
			.frame(minHeight: 64)
		}
	}

	/// The provider of a service, when one has been added.
	private func provider(_ preset: AIProviderPreset) -> AIProviderConfig? {
		ai.providers.first { $0.preset == preset }
	}

	private func card(_ service: Service) -> some View {
		let config = provider(service.preset)
		let connected = config.map(ai.isReady) ?? false
		let inUse = config?.id == ai.active?.id && connected
		let apple = service.preset == .appleIntelligence
		let installed = apple ? AppleIntelligence.isAvailable : (service.preset.localCLI?.isInstalled ?? true)
		return VStack(alignment: .leading, spacing: 22) {
			HStack(spacing: 14) {
				HIcon(service.icon, size: 22)
					.foregroundStyle(connected ? Folio.onDark : Folio.ink)
					.frame(width: 48, height: 48)
					.background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(connected ? Folio.dark : Folio.chip))
				VStack(alignment: .leading, spacing: 2) {
					Text(service.name).font(.system(size: 18, weight: .bold)).tracking(-0.36).foregroundStyle(Folio.ink)
					Text(service.maker).font(.system(size: 13)).foregroundStyle(Folio.meta)
				}
				Spacer(minLength: 4)
				HStack(spacing: 7) {
					Circle().fill(connected ? Folio.connectedDot : ThreadStatus.canArchive.dot).frame(width: 7, height: 7)
					Text(connected ? (inUse ? "Connected · in use" : "Connected") : "Not connected").font(.system(size: 12.5, weight: .semibold))
				}
				.foregroundStyle(connected ? Folio.connectedInk : ThreadStatus.canArchive.ink)
				.padding(.horizontal, 12).frame(height: 28)
				.background(Capsule().fill(connected ? Folio.connectedFill : Folio.chip))
				.fixedSize()
			}
			VStack(alignment: .leading, spacing: 4) {
				if apple && connected {
					Text("Apple's on-device model. Free and private, and works offline.")
					Text("Best for sorting, tagging, filing and short replies.")
				} else if apple {
					Text(AppleIntelligence.unavailableReason ?? "Free and private, on this Mac.")
					Text("Best for sorting, tagging, filing and short replies.")
				} else if connected {
					Text("Runs the \(service.preset.localCLI?.command ?? "") command with your \(service.name) sign-in")
					Text("Model: \(config?.model ?? "default") · no API key")
				} else if installed {
					Text("Sign in with your paid account to use it as your assistant.")
					Text("You can connect both and choose one per task.")
				} else {
					Text("The \(service.preset.localCLI?.command ?? "") command isn't installed on this Mac.")
					Text("Install it and sign in, then reopen Settings.")
				}
			}
			.font(.system(size: 14)).lineSpacing(3).foregroundStyle(Folio.body)
			Spacer(minLength: 0)
			HStack(spacing: 10) {
				if let config, connected {
					if !apple {
						Button("Manage account") { edit(config, isNew: false) }
							.buttonStyle(FolioOutlineButtonStyle(ink: Folio.selectionInk, stroke: Folio.accentStroke))
					}
					if !inUse {
						Button("Use \(service.name)") { ai.select(providerID: config.id, model: config.model) }
							.buttonStyle(FolioOutlineButtonStyle())
					}
					Button("Disconnect") { ai.remove(config.id) }
						.buttonStyle(.plain).font(.system(size: 14, weight: .semibold)).foregroundStyle(Folio.body)
						.padding(.horizontal, 12)
				} else {
					Button("Connect \(service.name)") {
						let config = config ?? AIProviderConfig(preset: service.preset)
						ai.save(config, key: "")
						ai.select(providerID: config.id, model: config.model)
					}
					.buttonStyle(FolioFilledButtonStyle())
					.disabled(!installed)
				}
			}
		}
		.frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
		.padding(24)
		.background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(connected ? Folio.accentSoft : Folio.card))
		.overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(connected ? Folio.accentStroke : Folio.line, lineWidth: 1))
		.sheet(isPresented: Binding(get: { editing?.preset == service.preset }, set: { if !$0 { editing = nil } })) {
			ProviderEditor(config: Binding(get: { editing ?? AIProviderConfig(preset: service.preset) }, set: { editing = $0 }),
						   key: $keyText, isNew: editingIsNew, cache: $modelCache) {
				if let config = editing { ai.save(config, key: keyText) }
				editing = nil
			} cancel: { editing = nil }
		}
	}

	private func edit(_ config: AIProviderConfig, isNew: Bool) {
		keyText = ai.apiKey(for: config.id)
		editingIsNew = isNew
		editing = config
	}
}

private struct AISettingsPage: View {
	@Environment(MailStore.self) private var store
	/// Model lists fetched on this page, by service address and key. They are kept while the page is
	/// open and dropped when another settings page is shown.
	@State private var modelCache: [String: [String]] = [:]
	/// The provider being added or edited, with the key typed for it.
	@State private var editing: AIProviderConfig?
	@State private var editingIsNew = false
	@State private var keyText = ""

	private var ai: AISettings { store.ai }

	var body: some View {
		if ai.isConfigured { modelsGroup }
		if ai.providers.isEmpty {
			SettingsGroup(title: "AI Providers", footer: "Add a provider to turn on the assistant. The assistant sends the mail it reads to the provider you choose.") {
				SettingsRow {
					Text("No providers yet").font(Typography.body).foregroundStyle(.secondary)
					Spacer()
				}
			}
		} else if !ai.providers.isEmpty {
			SettingsGroup(title: "AI Providers", footer: "Keys are stored in your Keychain. Switch provider and model from the assistant panel.") {
				ForEach(Array(ai.providers.enumerated()), id: \.element.id) { index, provider in
					if index > 0 { SettingsDivider() }
					SettingsRow {
						VStack(alignment: .leading, spacing: 1) {
							HStack(spacing: 6) {
								Text(provider.name).font(Typography.bodySemibold).lineLimit(1)
								if provider.id == ai.active?.id { Text("In use").font(Typography.meta).foregroundStyle(.secondary) }
							}
							Text(ai.isReady(provider) ? provider.model : "Needs setup")
								.font(Typography.meta).foregroundStyle(ai.isReady(provider) ? Color.secondary : Color.orange).lineLimit(1)
						}
						Spacer(minLength: 8)
						Button("Edit") { edit(provider, isNew: false) }.buttonStyle(.pill)
						Button("Remove") { if editing?.id == provider.id { editing = nil }; ai.remove(provider.id) }.buttonStyle(.pill)
					}
				}
			}
		}
		WideButton(title: "Add Provider", icon: .add) { edit(AIProviderConfig(preset: .codexCLI), isNew: true) }
			.sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
				ProviderEditor(config: Binding(get: { editing ?? AIProviderConfig(preset: .openai) }, set: { editing = $0 }),
							   key: $keyText, isNew: editingIsNew, cache: $modelCache) {
					if let config = editing { ai.save(config, key: keyText) }
					editing = nil
				} cancel: { editing = nil }
			}
	}

	private var modelsGroup: some View {
		let activeChoice = ai.active.map { AISettings.ModelChoice(providerID: $0.id, model: $0.model) }
		return SettingsGroup(title: "Models", footer: "AI Writer follows the assistant's model unless you pick one for it. Each custom prompt is added to that feature's instructions.") {
			ModelPickerRow(
				title: "AI Chat", providers: ai.readyProviders, selection: activeChoice,
				onSelect: { if let c = $0 { ai.select(providerID: c.providerID, model: c.model) } })
			SettingsDivider()
			promptField("Custom prompt for AI Chat, such as “Be concise and sign off with Thanks, Sam”",
						text: Binding(get: { ai.instructions }, set: { ai.instructions = $0 }))
			SettingsDivider()
			ModelPickerRow(
				title: "AI Writer", providers: ai.readyProviders, selection: ai.writerChoice,
				defaultLabel: "Same as AI Chat", onSelect: { ai.selectWriter($0) })
			SettingsDivider()
			promptField("Custom prompt for AI Writer, such as “Friendly, short paragraphs, no jargon”",
						text: Binding(get: { ai.writerInstructions }, set: { ai.writerInstructions = $0 }))
		}
	}

	private func promptField(_ placeholder: String, text: Binding<String>) -> some View {
		TextField(placeholder, text: text, axis: .vertical)
			.textFieldStyle(.plain).font(Typography.body)
			.lineLimit(2...6)
			.padding(.vertical, 12)
			.frame(maxWidth: .infinity, alignment: .leading)
	}

	private func edit(_ config: AIProviderConfig, isNew: Bool) {
		keyText = ai.apiKey(for: config.id)
		editingIsNew = isNew
		editing = config
	}
}

/// The form for one provider: its service, address, key and model.
private struct ProviderEditor: View {
	@Environment(MailStore.self) private var store
	@Binding var config: AIProviderConfig
	@Binding var key: String
	var isNew: Bool
	@Binding var cache: [String: [String]]
	var save: () -> Void
	var cancel: () -> Void

	@State private var loading = false
	@State private var error: String?
	/// Listing failed, so the model is typed by hand.
	@State private var typeModel = false

	private var cacheKey: String { "\(config.baseURLString)|\(key.trimmingCharacters(in: .whitespaces))" }
	private var canList: Bool {
		if config.preset.localCLI != nil { return true }
		return config.baseURL != nil && (!config.preset.needsKey || !key.trimmingCharacters(in: .whitespaces).isEmpty)
	}

	private var canSave: Bool {
		if let cli = config.preset.localCLI { return cli.isInstalled && !config.model.trimmingCharacters(in: .whitespaces).isEmpty }
		return config.baseURL != nil && !config.model.trimmingCharacters(in: .whitespaces).isEmpty
			&& (!config.preset.needsKey || !key.trimmingCharacters(in: .whitespaces).isEmpty)
	}

	var body: some View {
		ModalScaffold(title: isNew ? "New Provider" : "Edit Provider", width: 460) {
			VStack(alignment: .leading, spacing: 12) {
				form
				if let error {
					Text(error).font(Typography.meta).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
				} else if !config.models.isEmpty {
					Text("\(config.models.count) models available.").font(Typography.meta).foregroundStyle(.secondary)
				}
			}
			// Room for the dropdowns to open downward inside the sheet.
			.frame(minHeight: 340, alignment: .top)
		} footer: {
			HStack(spacing: 8) {
				Button { Task { await loadModels() } } label: {
					if loading { ProgressView().controlSize(.small) } else { Text("Load Models") }
				}
				.buttonStyle(.pill)
				.disabled(loading || !canList)
				Spacer()
				Button("Cancel", action: cancel).buttonStyle(.pill).keyboardShortcut(.cancelAction)
				Button("Save", action: save).buttonStyle(.pillProminent).disabled(!canSave)
			}
		}
	}

	private var form: some View {
		SettingsGroup(title: "Provider") {
			SettingsPicker(
				title: "Service",
				options: AIProviderPreset.allCases.map { ($0.title, $0) },
				selection: Binding(get: { config.preset }, set: { changePreset($0) })
			)
			SettingsDivider()
			SettingsRow {
				Text("Name").font(Typography.body)
				Spacer(minLength: 12)
				TextField("Name", text: $config.name)
					.textFieldStyle(.plain).multilineTextAlignment(.trailing).font(Typography.body)
			}
			if config.preset == .custom {
				SettingsDivider()
				SettingsRow {
					Text("Base URL").font(Typography.body)
					Spacer(minLength: 12)
					TextField("https://api.example.com/v1", text: $config.customBaseURL)
						.textFieldStyle(.plain).multilineTextAlignment(.trailing).font(Typography.body)
				}
			}
			if config.preset == .cloudflare {
				SettingsDivider()
				SettingsRow {
					Text("Account ID").font(Typography.body)
					Spacer(minLength: 12)
					TextField("Cloudflare account ID", text: Binding(get: { config.cloudflareAccountID ?? "" }, set: { config.cloudflareAccountID = $0 }))
						.textFieldStyle(.plain).multilineTextAlignment(.trailing).font(Typography.body)
				}
			}
			if let cli = config.preset.localCLI {
				SettingsDivider()
				SettingsRow {
					Text(cli.isInstalled
						 ? "Runs the \(cli.command) command on this Mac with your own login. No API key."
						 : "The \(cli.command) command isn't installed on this Mac.")
						.font(Typography.meta).foregroundStyle(cli.isInstalled ? Color.secondary : Color.orange)
					Spacer()
				}
			}
			if config.preset.needsKey {
				SettingsDivider()
				SettingsRow {
					Text("API key").font(Typography.body)
					Spacer(minLength: 12)
					SecureField("Paste your key", text: $key)
						.textFieldStyle(.plain).multilineTextAlignment(.trailing).font(Typography.body)
				}
			}
			SettingsDivider()
			if typeModel || !canList {
				SettingsRow {
					Text("Model").font(Typography.body)
					Spacer(minLength: 12)
					TextField(config.preset.defaultModel.isEmpty ? "Model name" : config.preset.defaultModel, text: $config.model)
						.textFieldStyle(.plain).multilineTextAlignment(.trailing).font(Typography.body)
				}
			} else {
				// Opening it fetches the list the first time; later opens reuse what was fetched.
				SettingsPicker(
					title: "Model", options: config.choices.map { ($0, $0) }, selection: $config.model,
					isLoading: config.models.isEmpty, onOpen: { Task { await loadIfNeeded() } },
					maxHeight: 180, fallbackLabel: config.model
				)
			}
		}
	}

	private func changePreset(_ preset: AIProviderPreset) {
		let previous = config.preset
		config.preset = preset
		config.models = []
		typeModel = false
		error = nil
		if config.name == previous.title || config.name.isEmpty { config.name = preset.title }
		config.model = preset.defaultModel
	}

	/// Uses the list fetched earlier on this page, or fetches it.
	private func loadIfNeeded() async {
		guard config.models.isEmpty, !loading else { return }
		if let cached = cache[cacheKey] { config.models = cached; return }
		await loadModels()
	}

	private func loadModels() async {
		if let cli = config.preset.localCLI {
			config.models = cli.models
			typeModel = false
			if config.model.trimmingCharacters(in: .whitespaces).isEmpty { config.model = cli.defaultModel }
			return
		}
		guard let baseURL = config.baseURL else { return }
		loading = true; error = nil
		defer { loading = false }
		do {
			let models = try await AIClient.listModels(baseURL: baseURL, apiKey: key.trimmingCharacters(in: .whitespaces))
			if models.isEmpty { error = "The provider returned no models."; typeModel = true; return }
			cache[cacheKey] = models
			typeModel = false
			config.models = models
			if !models.contains(config.model) { config.model = models.first(where: { $0 == config.preset.defaultModel }) ?? models[0] }
		} catch {
			self.error = error.localizedDescription
			typeModel = true
		}
	}
}

private struct LicenseSettings: View {
	@Environment(MailStore.self) private var store
	@Environment(\.openURL) private var openURL
	@State private var keyText = ""

	private var license: LicenseManager { store.license }

	var body: some View {
		SettingsGroup(title: "Mailflare Pro", footer: footer) {
			SettingsRow {
				Text("Plan").font(Typography.body)
				Spacer()
				Text(license.isPro ? "Pro" : "Free").font(Typography.body).foregroundStyle(.secondary)
			}
			if license.serverLicensed {
				SettingsDivider()
				SettingsRow {
					Text("Activated by").font(Typography.body)
					Spacer(minLength: 16)
					Text(store.account.map { "\($0.serverUrl)" } ?? "Your server")
						.font(Typography.meta).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
				}
			}
			if let masked = license.maskedKey {
				SettingsDivider()
				SettingsRow {
					Text("License key").font(Typography.body)
					Spacer(minLength: 16)
					Text(masked).font(.system(.footnote, design: .monospaced)).foregroundStyle(.secondary)
				}
			}
		}
		if license.licenseKey != nil {
			if license.busy {
				ProgressView().controlSize(.small).frame(maxWidth: .infinity)
			} else {
				WideButton(title: "Deactivate This Mac") { Task { await license.deactivate() } }
			}
		} else {
			SettingsGroup(title: "Activate a license key") {
				SettingsRow {
					TextField("License key", text: $keyText)
						.textFieldStyle(.plain)
						.font(Typography.body)
						.onSubmit(activate)
					Button("Activate", action: activate)
						.buttonStyle(.pillProminent)
						.disabled(keyText.trimmingCharacters(in: .whitespaces).isEmpty || license.busy)
				}
			}
			if license.busy { ProgressView().controlSize(.small).frame(maxWidth: .infinity) }
			if !license.isPro {
				WideButton(title: "Buy Mailflare Pro", prominent: true) { openURL(LicenseManager.buyURL) }
			}
		}
		if let message = license.message {
			Text(message).font(Typography.meta).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
		}
	}

	private var footer: String {
		license.serverLicensed
			? "Your Mailflare server has an active license, so this app is activated while you are signed in to it."
			: "Signing in to a Mailflare account whose server has a Pro license activates the app automatically. Otherwise enter the key from your purchase email."
	}

	private func activate() {
		let key = keyText
		Task { await license.activate(key: key); if license.keyActive { keyText = "" } }
	}
}

private struct SupportSettings: View {
	private static let issuesURL = URL(string: "https://github.com/romanpathak111/mailflare-macos/issues")!

	var body: some View {
		SettingsGroup(title: "Need help?", footer: "Include your macOS version, the SuperMail version (see Version) and, for a bug, the steps that cause it. Please leave out passwords, API keys and private mail.") {
			VStack(alignment: .leading, spacing: 6) {
				Text("Found a bug, or want a feature?").font(Typography.bodySemibold)
				Text("Create an issue on GitHub and describe what happened or what you would like. Every report is read there.")
					.font(Typography.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
			}
			.padding(.vertical, 12)
			SettingsDivider()
			SettingsRow {
				Text("Issues").font(Typography.body)
				Spacer(minLength: 16)
				Text("github.com/romanpathak111/mailflare-macos/issues").font(Typography.meta).foregroundStyle(.secondary)
					.lineLimit(1).truncationMode(.middle).textSelection(.enabled)
			}
		}
		WideButton(title: "Create a GitHub Issue", icon: .support, prominent: true) { NSWorkspace.shared.open(Self.issuesURL) }
	}
}

private struct AboutSettings: View {
	@Environment(AppUpdater.self) private var updater

	var body: some View {
		SettingsGroup(title: "SuperMail", footer: "SuperMail is based on Mailflare by Hieu Nguyen (github.com/hieunc229/mailflare-macos) and, like it, is free software under the GNU Affero General Public License v3. Its source, with every change, is at github.com/romanpathak111/mailflare-macos.") {
			SettingsRow {
				Text("Version").font(Typography.body)
				Spacer()
				Text(AppUpdater.currentVersion).font(Typography.body).foregroundStyle(.secondary)
			}
			SettingsDivider()
			SettingsRow {
				Text("Mail data").font(Typography.body)
				Spacer(minLength: 16)
				Text(MailStore.dataDirectoryDescription).font(Typography.meta).foregroundStyle(.secondary)
					.lineLimit(1).truncationMode(.middle).textSelection(.enabled)
			}
		}
		if let release = updater.available {
			switch updater.phase {
			case .idle:
				WideButton(title: "Update to \(release.version) and Restart", prominent: true) { Task { await updater.install() } }
			case .downloading, .installing:
				HStack(spacing: 8) {
					ProgressView().controlSize(.small)
					Text(updater.phase == .downloading ? "Downloading \(release.version)…" : "Installing…").font(Typography.body)
				}
				.frame(maxWidth: .infinity).padding(.vertical, 7)
			case .failed(let message):
				Text(message).font(Typography.meta).foregroundStyle(.orange)
				WideButton(title: "Try Again") { Task { await updater.install() } }
			}
		} else {
			WideButton(title: "Check for Updates") { Task { await updater.check() } }
		}
	}
}
