import SwiftUI
import MailflareCore

struct SidebarView: View {
	@Environment(MailStore.self) private var store
	@Environment(AppUpdater.self) private var updater
	@State private var switcherOpen = false

	var body: some View {
		ZStack(alignment: .top) {
			content
			// The dropdown covers the header's place, its top edge level with the main body's.
			if switcherOpen {
				dropdown
					.padding(.top, Self.wordmarkHeight)
					.transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
			}
		}
		.background(Folio.sidebar)
	}

	private var content: some View {
		VStack(spacing: 0) {
			if store.settingsPage != nil {
				settingsMenu
			} else {
				mailMenu
			}
			footer
		}
	}

	/// Settings take the mailbox list's place: a way back to the inbox, then the pages.
	private var settingsMenu: some View {
		VStack(alignment: .leading, spacing: 2) {
			Button {
				store.settingsPage = nil
			} label: {
				HStack(spacing: 8) {
					HIcon(.arrowLeft, size: 15)
					Text("Back to Inbox").font(Typography.body)
					Spacer(minLength: 0)
				}
				.foregroundStyle(.primary)
				.padding(.horizontal, 12).padding(.vertical, 10)
				.contentShape(Rectangle())
			}
			.buttonStyle(.light)
			.keyboardShortcut(.escape, modifiers: [])
			.help("Back to Inbox (Esc)")
			.padding(.bottom, 6)
			ForEach(SettingsSection.allCases) { group in
				Text(group.title).font(Typography.meta.weight(.medium)).foregroundStyle(.secondary)
					.padding(.horizontal, 10).padding(.top, group == .general ? 6 : 14).padding(.bottom, 4)
				ForEach(group.pages) { page in
					SidebarRow(icon: page.icon, title: page.title, badge: 0, tint: nil, isSelected: store.settingsPage == page) {
						store.settingsPage = page
					}
				}
			}
			Spacer(minLength: 0)
		}
		.padding(.horizontal, Self.gutter)
		.frame(maxHeight: .infinity, alignment: .top)
	}

	private var mailMenu: some View {
		VStack(spacing: 0) {
			wordmark
			header
				.opacity(switcherOpen ? 0 : 1)
				.allowsHitTesting(!switcherOpen)
				.padding(.bottom, 14)
			ScrollView {
				VStack(alignment: .leading, spacing: 2) {
					folioList
					topList
					statusSection
					if store.showsAllInboxes { accountsSection } else { singleSections; accountList }
				}
				.padding(.horizontal, Self.gutter)
				.padding(.bottom, 12)
			}
			// A click anywhere else closes the account dropdown.
			.overlay {
				if switcherOpen { Color.clear.contentShape(Rectangle()).onTapGesture { closeSwitcher() } }
			}
		}
	}

	// MARK: Wordmark

	static let wordmarkHeight: CGFloat = 58

	/// The app's name, as the mockup sets "folio", with New Message at the other end.
	private var wordmark: some View {
		HStack(spacing: 8) {
			Text(store.displayBrandName.lowercased())
				.font(.system(size: 24, weight: .bold)).tracking(-0.7).foregroundStyle(Folio.ink).lineLimit(1)
			Spacer(minLength: 0)
			Button { store.newMessage() } label: {
				HIcon(.compose, size: 16)
					.foregroundStyle(store.minimizedDraft == nil ? Folio.body : Folio.selectionInk)
					.frame(width: 32, height: 32)
					.background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(store.minimizedDraft == nil ? Color.clear : Folio.selection))
					.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.help(store.minimizedDraft == nil ? "New Message (⌘N)" : "Continue your draft (⌘N)")
			.accessibilityLabel("New Message")
		}
		.padding(.leading, Self.gutter + 8).padding(.trailing, Self.gutter + 2)
		.frame(height: Self.wordmarkHeight)
	}

	// MARK: Switcher header

	private var multipleInboxes: Bool { store.inboxAddresses.count > 1 }
	/// The same gutter on the left and the right of the sidebar.
	static let gutter: CGFloat = 10

	/// The account/inbox in view: pictures, name and address, with a chevron that opens the switcher.
	private var headerButton: some View {
		let activeView = store.activeView
		let inbox = activeView != nil ? nil : (store.currentInbox ?? (multipleInboxes ? nil : store.inboxAddresses.first))
		let title = activeView?.name ?? inbox.map { store.label($0) }
			?? (store.account.map(store.switcherName) ?? "Mailflare")
		return Button {
			withAnimation(.snappy(duration: 0.22)) { switcherOpen.toggle() }
		} label: {
			HStack(spacing: 10) {
				if let activeView {
					accountStack(activeView.accountIDs, size: 22, step: 14)
				} else if let inbox, let account = store.account {
					ProfileAvatar(key: AvatarCache.key(account: account.id, mailbox: inbox.id), name: store.label(inbox), size: 22)
				} else if !multipleInboxes, let account = store.account {
					// A single-inbox account (Gmail and the like): the account itself.
					ProfileAvatar(key: AvatarCache.key(account: account.id), name: store.accountName(account), size: 22)
				} else {
					avatarStack(store.inboxAddresses, accountID: store.account?.id ?? "", size: 22, step: 14)
				}
				Text(store.isAllAccounts ? "All accounts" : title)
					.font(.system(size: 14, weight: .semibold)).foregroundStyle(Folio.ink).lineLimit(1)
					.help(activeView.map(viewSummary) ?? inbox?.inboxEmail ?? (multipleInboxes ? addressSummary : (store.account?.email ?? "")))
				Spacer(minLength: 0)
				UpDownChevron().foregroundStyle(Folio.meta)
			}
			.padding(.horizontal, 12)
			.frame(height: 46)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.help("Inboxes, accounts and sign-out")
	}

	/// The header is always a bordered card, its top edge level with the main body's; opening the
	/// dropdown grows this same card downward.
	private var header: some View {
		headerButton
			.background(Folio.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			.overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Folio.line, lineWidth: 1))
			.padding(.horizontal, Self.gutter)
	}

	/// The open dropdown: the header card extended with the accounts, inboxes and account actions.
	private var dropdown: some View {
		VStack(spacing: 0) {
			headerButton
			Rectangle().fill(AppTheme.cardStroke).frame(height: 1).padding(.horizontal, 10)
			switcher
		}
		.background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.outline, lineWidth: 1))
		.shadow(color: AppTheme.composerShadow, radius: 14, y: 6)
		.padding(.horizontal, Self.gutter)
	}

	/// The first address and how many more there are: "a@x.com +1 more".
	private var addressSummary: String {
		let emails = store.inboxAddresses.map(\.inboxEmail)
		guard let first = emails.first else { return "" }
		return emails.count > 1 ? "\(first) +\(emails.count - 1) more" : first
	}

	/// Up to three account pictures, overlapped.
	private func accountStack(_ ids: [String], size: CGFloat, step: CGFloat) -> some View {
		let shown = Array(ids.prefix(3))
		return ZStack(alignment: .leading) {
			ForEach(Array(shown.enumerated()), id: \.element) { index, id in
				let account = store.accountList.first { $0.id == id }
				ProfileAvatar(key: AvatarCache.key(account: id), name: account.map(store.accountName) ?? "?", size: size)
					.overlay(Circle().stroke(AppTheme.elevated, lineWidth: 2))
					.offset(x: CGFloat(index) * step)
					.zIndex(Double(shown.count - index))
			}
		}
		.frame(width: size + step * CGFloat(max(shown.count - 1, 0)), height: size + 6, alignment: .leading)
	}

	/// "2 inboxes · 2 accounts" under a view's name.
	private func viewSummary(_ view: InboxView) -> String {
		let inboxes = view.members.count, accounts = view.accountIDs.count
		return "\(inboxes) inbox\(inboxes == 1 ? "" : "es") · \(accounts) account\(accounts == 1 ? "" : "s")"
	}

	/// Up to three pictures, overlapped.
	private func avatarStack(_ inboxes: [Mailbox], accountID: String, size: CGFloat, step: CGFloat) -> some View {
		let shown = Array(inboxes.prefix(3))
		return ZStack(alignment: .leading) {
			ForEach(Array(shown.enumerated()), id: \.element.id) { index, inbox in
				ProfileAvatar(key: AvatarCache.key(account: accountID, mailbox: inbox.id), name: store.label(inbox), size: size)
					.overlay(Circle().stroke(AppTheme.elevated, lineWidth: 2))
					.offset(x: CGFloat(index) * step)
					.zIndex(Double(shown.count - index))
			}
		}
		.frame(width: size + step * CGFloat(max(shown.count - 1, 0)), height: size + 6, alignment: .leading)
	}

	/// Each saved account: all of its inboxes, then each inbox on its own. Scrolls only when it is
	/// taller than the room it gets (a `ScrollView` has no height of its own, so it is sized here).
	private var switcher: some View {
		let rows = store.accountList.reduce(0) { total, account in
			let inboxes = store.inboxAddresses(of: account.id).count
			return total + 1 + (inboxes > 1 ? inboxes : 0)
		} + store.inboxViews.count + (store.accountList.count > 1 ? 1 : 0)
		let content = VStack(alignment: .leading, spacing: 2) {
			if store.accountList.count > 1 {
				allAccountsRow
				Rectangle().fill(AppTheme.cardStroke).frame(height: 1).padding(.vertical, 6).padding(.horizontal, 6)
			}
			ForEach(Array(store.accountList.enumerated()), id: \.element.id) { index, account in
				if index > 0 { Rectangle().fill(AppTheme.cardStroke).frame(height: 1).padding(.vertical, 6).padding(.horizontal, 6) }
				accountRows(account)
			}
			if !store.inboxViews.isEmpty {
				Rectangle().fill(AppTheme.cardStroke).frame(height: 1).padding(.vertical, 6).padding(.horizontal, 6)
				ForEach(store.inboxViews) { view in viewRow(view) }
			}
		}
		.padding(.vertical, 6)
		let natural = CGFloat(rows) * 48 + CGFloat(max(store.accountList.count - 1, 0)) * 14 + 12 + (store.inboxViews.isEmpty ? 0 : 14)
		return VStack(spacing: 0) {
			Group {
				if natural > 280 {
					// No rule above the footer: scrolled rows fade into the card instead.
					ScrollView { content }.frame(height: 280)
						.overlay(alignment: .bottom) {
							LinearGradient(colors: [AppTheme.elevated.opacity(0), AppTheme.elevated], startPoint: .top, endPoint: .bottom)
								.frame(height: 28)
								.allowsHitTesting(false)
						}
				} else { content }
			}
			VStack(alignment: .leading, spacing: 2) {
				actionRow(.settings, "Manage Account") { closeSwitcher(); store.settingsPage = .accounts }
			}
			.padding(.vertical, 6)
		}
	}

	/// Every inbox of every account in one list.
	private var allAccountsRow: some View {
		SwitcherRow(
			isSelected: store.isAllAccounts,
			unread: store.unreadAllAccounts,
			action: { store.selectAllAccounts(); closeSwitcher() }
		) {
			accountStack(store.accountList.map(\.id), size: 24, step: 13)
		} text: {
			Text("Unified Inbox").font(.system(size: 14, weight: .semibold)).lineLimit(1)
			Text("\(store.accountList.count) accounts").font(Typography.meta).foregroundStyle(.secondary).lineLimit(1)
		}
	}

	private func viewRow(_ view: InboxView) -> some View {
	SwitcherRow(
		isSelected: store.activeViewID == view.id,
		unread: store.unreadCount(of: view),
		action: { store.selectView(view.id); closeSwitcher() }
	) {
		accountStack(view.accountIDs, size: 24, step: 13)
	} text: {
		Text(view.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
		Text(viewSummary(view)).font(Typography.meta).foregroundStyle(.secondary).lineLimit(1)
	}
}

private func actionRow(_ icon: AppIcon, _ title: String, action: @escaping () -> Void) -> some View {
		SwitcherRow(isSelected: false, unread: 0, action: action) {
			HIcon(icon, size: 16).foregroundStyle(.secondary).frame(width: 26)
		} text: {
			Text(title).font(Typography.body)
		}
	}

	@ViewBuilder
	private func accountRows(_ account: Account) -> some View {
		let inboxes = store.inboxAddresses(of: account.id)
		let isCurrent = account.id == store.account?.id
		let showInboxes = inboxes.count > 1
		SwitcherRow(
			isSelected: store.activeViewID == nil && isCurrent && (store.currentInbox == nil || !showInboxes),
			unread: store.unreadCount(accountID: account.id, inbox: nil),
			action: { store.selectInbox(nil, accountID: account.id); closeSwitcher() }
		) {
			if showInboxes {
				avatarStack(inboxes, accountID: account.id, size: 26, step: 14)
			} else {
				ProfileAvatar(key: AvatarCache.key(account: account.id), name: store.accountName(account), size: 32)
			}
		} text: {
			Text(store.switcherName(account)).font(.system(size: 14, weight: .semibold)).lineLimit(1)
			Text(showInboxes ? "\(account.email) (\(inboxes.count) inboxes)" : account.email)
				.font(Typography.meta).foregroundStyle(.secondary).lineLimit(1)
		}
		if showInboxes {
			ForEach(inboxes) { inbox in
				SwitcherRow(
					isSelected: store.activeViewID == nil && isCurrent && store.currentInbox?.id == inbox.id,
					unread: store.unreadCount(accountID: account.id, inbox: inbox),
					indent: true,
					action: { store.selectInbox(inbox, accountID: account.id); closeSwitcher() }
				) {
					ProfileAvatar(key: AvatarCache.key(account: account.id, mailbox: inbox.id), name: store.label(inbox), size: 28)
				} text: {
					Text(store.label(inbox)).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
					Text(inbox.inboxEmail).font(Typography.meta).foregroundStyle(.secondary).lineLimit(1)
				}
			}
		}
	}

	private func closeSwitcher() { withAnimation(.snappy(duration: 0.22)) { switcherOpen = false } }

	// MARK: Today, the Status board and the statuses

	/// Today and the Status board lead the sidebar.
	private var folioList: some View {
		VStack(alignment: .leading, spacing: 2) {
			SidebarRow(icon: .calendar, title: "Today", badge: 0, tint: nil,
					   isSelected: store.settingsPage == nil && store.screen == .home) { store.openScreen(.home) }
			SidebarRow(icon: .board, title: "Status board", badge: 0, tint: nil,
					   isSelected: store.settingsPage == nil && store.screen == .board) { store.openScreen(.board) }
		}
	}

	/// The four statuses with how many conversations each holds. Each lists its mail, so the
	/// labels give the tagged emails as a list while the board shows them side by side.
	private var statusSection: some View {
		VStack(alignment: .leading, spacing: 0) {
			heading("statuses", "Status")
			if !collapsed("statuses") {
				ForEach(ThreadStatus.allCases) { status in
					StatusSidebarRow(status: status, count: store.statuses.count(status),
									 isSelected: store.settingsPage == nil && store.screen == .mail && store.statusList == status) {
						store.openStatusList(status)
					}
				}
			}
		}
	}

	/// Every account, as the mockup lists them, with + to add one. Shown when one account is in view;
	/// with several, the accounts section above already lists them.
	private var accountList: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack(spacing: 0) {
				heading("account-list", "Accounts")
				addButton(title: "Accounts") { store.settingsPage = .accounts }
					.padding(.top, 12)
			}
			if !collapsed("account-list") {
				ForEach(store.accountList) { account in
					AccountSidebarRow(
						name: store.switcherName(account),
						unread: store.unreadCount(accountID: account.id, inbox: nil),
						isSelected: false
					) { store.selectInbox(nil, accountID: account.id) }
				}
			}
		}
	}

	// MARK: Items and sections

	private func collapsed(_ id: String) -> Bool { store.collapsedSections.contains(id) }

	/// A small collapsible heading shared by the sections.
	private func heading(_ id: String, _ title: String) -> some View {
		Button {
			withAnimation(.snappy(duration: 0.2)) { store.toggleSection(id) }
		} label: {
			HStack(spacing: 5) {
				SectionTitle(title)
				Spacer(minLength: 0)
			}
			.padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 4)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.help(collapsed(id) ? "Show \(title)" : "Hide \(title)")
	}

	/// Everything Organize has on, directly below Today, over the whole scope the dropdown chose. The
	/// custom tabs follow Today (or lead, when Today is turned off), each with its unread count.
	private var topList: some View {
		VStack(alignment: .leading, spacing: 2) {
			if !store.unifiedShows(.today) { customTabRows }
			ForEach(UnifiedViewKind.allCases.filter { store.unifiedShows($0) }) { kind in
				let title = kind == .inbox ? (store.showsAllInboxes ? "Inboxes" : "Inbox") : kind.title
				let badge = kind == .inbox || kind == .today ? store.unreadCount(for: kind.item) : 0
				SidebarRow(icon: kind.icon, title: title, badge: badge, tint: nil,
						   isSelected: store.settingsPage == nil && store.screen == .mail && store.focus == nil && store.sidebar == kind.item) {
					store.openTopItem(kind.item)
				}
				if kind == .today { customTabRows }
			}
		}
		.padding(.top, 4)
	}

	@ViewBuilder
	private var customTabRows: some View {
		ForEach(store.customTabs) { tab in
			let item = SidebarItem.customTab(tab.id)
			SidebarRow(icon: tab.appIcon, title: tab.name, badge: store.unreadCount(for: item), tint: nil,
					   isSelected: store.settingsPage == nil && store.screen == .mail && store.focus == nil && store.sidebar == item) {
				store.openTopItem(item)
			}
		}
	}

	/// The views Organize has off, as rows of one group or of the one inbox in view.
	@ViewBuilder
	private func offRows(group: MailStore.SidebarGroup?) -> some View {
		let accountID = group?.account.id ?? store.account?.id ?? ""
		let inbox = group != nil ? group?.inbox : store.scopeInbox
		let selectedFocus = group?.focus
		ForEach(UnifiedViewKind.allCases.filter { !store.unifiedShows($0) || ($0 == .inbox && group != nil) }) { kind in
			if kind != .archive || store.hasRole("archive", accountID: accountID, inbox: inbox) {
				SidebarRow(
					icon: kind.icon, title: kind == .inbox ? "Inbox" : kind.title,
					badge: kind == .inbox ? store.unreadCount(accountID: accountID, inbox: inbox) : 0, tint: nil,
					isSelected: store.settingsPage == nil && store.screen == .mail && store.focus == selectedFocus && store.sidebar == kind.item
				) {
					if let group { store.openGroupItem(kind.item, in: group) } else { store.openTopItem(kind.item) }
				}
			}
		}
	}

	/// A folder or label row: of a group (any account in view) or of the one inbox in view.
	private func folderRow(_ box: Mailbox, group: MailStore.SidebarGroup?) -> some View {
		let item: SidebarItem = group != nil && store.activeViewID != nil
			? .mailbox(ViewMessageID.make(account: group!.account.id, message: box.id)) : .mailbox(box.id)
		return SidebarRow(
			icon: .folder, title: box.name, badge: Int(box.unreadEmails), tint: store.folderColors.color(for: box.id), compact: true,
			isSelected: store.settingsPage == nil && store.screen == .mail && store.focus == group?.focus && store.sidebar == item
		) {
			if let group { store.openGroupItem(item, in: group) } else { store.openTopItem(item) }
		}
		// Shown before the server has made it.
		.opacity(MailStore.isPending(box) ? 0.5 : 1)
		.contextMenu {
			if !MailStore.isPending(box), let account = group?.account ?? store.account, let support = store.folderSupport(accountID: account.id) {
				if support.canRename {
					Button("Rename \(support.noun.capitalized)…") { store.folderRequest = .init(accountID: account.id, kind: .rename(box)) }
				}
				if support.canDelete {
					Button("Delete \(support.noun.capitalized)…", role: .destructive) { store.folderRequest = .init(accountID: account.id, kind: .delete(box)) }
				}
			}
		}
	}

	/// One inbox in view: its own section with the views Organize has off, then its folders or labels.
	@ViewBuilder
	private var singleSections: some View {
		let hasOff = UnifiedViewKind.allCases.contains { !store.unifiedShows($0) }
		let folders = store.scopeFolders
		if hasOff {
			// The views the sidebar doesn't list: closed under More until opened.
			let open = store.collapsedSections.contains("open:inbox-more")
			foldHeading("More", isOpen: open) { store.toggleSection("open:inbox-more") }
			if open { offRows(group: nil) }
		}
		let canCreate = store.account.map { store.canCreateFolders(accountID: $0.id) } ?? false
		if folders.isEmpty && canCreate {
			// Nothing to list yet: a button stands in for the section until one is made.
			let noun = store.isGmail ? "Label" : "Folder"
			SidebarRow(icon: .add, title: "Add \(noun)", badge: 0, tint: nil, isSelected: false) {
				guard let account = store.account else { return }
				store.folderRequest = .init(accountID: account.id, kind: .create(parentID: (store.scopeInbox ?? store.inboxAddresses.first)?.id))
			}
			.padding(.top, 10)
		} else if !folders.isEmpty {
			// Open unless the user closed it.
			let subID = "closed:inbox-folders"
			let open = store.collapsedSections.contains(subID)
			foldHeading("Folders", isOpen: !open, onAdd: canCreate ? {
				guard let account = store.account else { return }
				store.folderRequest = .init(accountID: account.id, kind: .create(parentID: (store.scopeInbox ?? store.inboxAddresses.first)?.id))
			} : nil) { store.toggleSection(subID) }
			if !open { ForEach(folders) { box in folderRow(box, group: nil) } }
		}
	}

	/// Several inboxes in view: one level of groups, each an account or an inbox of one.
	private var accountsSection: some View {
		VStack(alignment: .leading, spacing: 2) {
			// One account's own inboxes are just "Inboxes"; across accounts they are "Accounts".
			let own = store.activeViewID == nil
			heading(own ? "inboxes" : "accounts", own ? "Inboxes" : "Accounts")
			if !collapsed(own ? "inboxes" : "accounts") {
				ForEach(store.sidebarGroups) { group in groupView(group) }
			}
		}
	}

	private func groupView(_ group: MailStore.SidebarGroup) -> some View {
		let id = "grp:" + group.id
		return VStack(alignment: .leading, spacing: 2) {
			groupHeader(id, avatarKey: group.avatarKey, name: group.title, help: group.help,
						unread: store.unreadCount(accountID: group.account.id, inbox: group.inbox))
			if !collapsed(id) {
				// Rows line up under the avatar: chevron column (12) + gap (8) past the header's inset.
				VStack(alignment: .leading, spacing: 2) {
					offRows(group: group)
					let folders = store.customFolders(of: group.account.id, inbox: group.inbox)
					let canCreate = store.canCreateFolders(accountID: group.account.id)
					if folders.isEmpty && canCreate {
						SidebarRow(icon: .add, title: store.isGmailAccount(group.account) ? "Add Label" : "Add Folder", badge: 0, tint: nil, isSelected: false) {
							let parent = group.inbox ?? store.inboxAddresses(of: group.account.id).first
							store.folderRequest = .init(accountID: group.account.id, kind: .create(parentID: parent?.id))
						}
					} else if !folders.isEmpty {
						let subID = "open:" + id + "-folders"
						let open = store.collapsedSections.contains(subID)
						subHeading(store.isGmailAccount(group.account) ? "Labels" : "Folders", isOpen: open, onAdd: canCreate ? {
							let parent = group.inbox ?? store.inboxAddresses(of: group.account.id).first
							store.folderRequest = .init(accountID: group.account.id, kind: .create(parentID: parent?.id))
						} : nil) { store.toggleSection(subID) }
						if open { ForEach(folders) { box in folderRow(box, group: group) } }
					}
				}
				.padding(.leading, 20)
			}
		}
	}

	/// A section heading like `heading`, closed until opened (its state is kept under an `open:` key).
	/// `onAdd` puts a + at the right end.
	private func foldHeading(_ title: String, isOpen: Bool, onAdd: (() -> Void)? = nil, toggle: @escaping () -> Void) -> some View {
		HStack(spacing: 0) {
			Button {
				withAnimation(.snappy(duration: 0.2)) { toggle() }
			} label: {
				HStack(spacing: 5) {
					SectionTitle(title)
					Spacer(minLength: 0)
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.help(isOpen ? "Hide \(title)" : "Show \(title)")
			if let onAdd { addButton(title: title, action: onAdd) }
		}
		.padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 4)
	}

	/// A folded sub-section heading inside a group; the group keeps its state under an `open:` key,
	/// so it starts closed.
	private func subHeading(_ title: String, isOpen: Bool, onAdd: (() -> Void)? = nil, toggle: @escaping () -> Void) -> some View {
		HStack(spacing: 0) {
			Button {
				withAnimation(.snappy(duration: 0.2)) { toggle() }
			} label: {
				HStack(spacing: 8) {
					HIcon(.chevronRight, size: 10).rotationEffect(.degrees(isOpen ? 90 : 0)).frame(width: 16)
					Text(title).font(Typography.meta.weight(.medium))
					Spacer(minLength: 0)
				}
				.foregroundStyle(.secondary)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.help(isOpen ? "Hide \(title)" : "Show \(title)")
			if let onAdd { addButton(title: title, action: onAdd) }
		}
		.padding(.horizontal, 10).padding(.vertical, 6)
	}

	private func addButton(title: String, action: @escaping () -> Void) -> some View {
		let noun = title.hasSuffix("s") ? String(title.dropLast()) : title
		return Button(action: action) {
			HIcon(.add, size: 13).foregroundStyle(Folio.body).frame(width: 22, height: 22).contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.help("New \(noun)")
	}

	/// A collapsible heading for an account, or for one of its inboxes.
	private func groupHeader(_ id: String, avatarKey: String, name: String, help: String, unread: Int, size: CGFloat = 20) -> some View {
		Button {
			withAnimation(.snappy(duration: 0.2)) { store.toggleSection(id) }
		} label: {
			HStack(spacing: 8) {
				HIcon(.chevronRight, size: 10).rotationEffect(.degrees(collapsed(id) ? 0 : 90)).frame(width: 12)
				ProfileAvatar(key: avatarKey, name: name, size: size)
				Text(name).font(Typography.body.weight(.medium)).lineLimit(1)
				Spacer(minLength: 4)
				if collapsed(id) && unread > 0 { CountBadge(count: unread) }
			}
			.foregroundStyle(.primary.opacity(0.94))
			.padding(.horizontal, 10).padding(.vertical, 7)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.help(help)
	}

	// MARK: Footer

	/// The assistant's connection and Settings, with a connection note above them when offline.
	private var footer: some View {
		VStack(alignment: .leading, spacing: 8) {
			if let note = store.connectionNote {
				Text(note).font(.footnote).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
					.padding(.horizontal, Self.gutter)
			}
			if let release = updater.available {
				updateNotice(release)
			}
			// Inside Settings the menu above is the way around, so these are only for the mail view.
			if store.settingsPage == nil {
				assistantPill
				SidebarRow(icon: .settings, title: "Settings", badge: 0, tint: nil, isSelected: false) { store.settingsPage = .general }
					.help("Settings (⌘,)")
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.horizontal, Self.gutter).padding(.top, 8).padding(.bottom, 14)
	}

	/// Which assistant is in use, as the mockup's "Claude connected" card; it opens the Assistant settings.
	private var assistantPill: some View {
		let active = store.ai.active
		let name = active.map { $0.preset.localCLI?.title ?? $0.name } ?? "No assistant"
		return Button { store.settingsPage = .assistant } label: {
			HStack(spacing: 10) {
				Circle().fill(active != nil ? Folio.connectedDot : ThreadStatus.canArchive.dot).frame(width: 8, height: 8)
				Text(active != nil ? "\(name) connected" : "Connect an assistant")
					.font(.system(size: 14, weight: .semibold)).foregroundStyle(Folio.ink).lineLimit(1)
				Spacer(minLength: 0)
			}
			.padding(.horizontal, 14)
			.frame(height: 46)
			.background(Folio.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			.overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Folio.line, lineWidth: 1))
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.help("Assistant settings")
	}

	/// A newer release and the button that installs it, or how the install is going.
	private func updateNotice(_ release: AppUpdater.Release) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			switch updater.phase {
			case .idle:
				Text("Version \(release.version) is available").font(.footnote.weight(.medium))
				Button("Update and Restart") { Task { await updater.install() } }
					.buttonStyle(.pillProminent)
					.controlSize(.small)
			case .downloading, .installing:
				HStack(spacing: 6) {
					ProgressView().controlSize(.mini)
					Text(updater.phase == .downloading ? "Downloading \(release.version)…" : "Installing…").font(.footnote)
				}
			case .failed(let message):
				Text(message).font(.footnote).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
				Button("Try Again") { Task { await updater.install() } }
					.buttonStyle(.pill)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.noticeSurface(radius: 12)
		.padding(.bottom, 4)
	}
}

/// One sidebar line: glyph, name, unread count. Selected rows fill like PiCode's, hovered rows lift faintly.
private struct SidebarRow: View {
	var icon: AppIcon
	var title: String
	var badge: Int
	var tint: Color?
	/// Folder rows are shorter, like the status rows.
	var compact = false
	var isSelected: Bool
	var action: () -> Void

	@State private var isHovering = false

	var body: some View {
		Button(action: action) {
			HStack(spacing: compact ? 10 : 12) {
				HIcon(icon, size: compact ? 16 : 18).foregroundStyle(tint ?? (isSelected ? Folio.selectionInk : Folio.body))
				Text(title).font(.system(size: compact ? 13.5 : 14, weight: isSelected ? .semibold : .medium)).lineLimit(1)
					.foregroundStyle(isSelected ? Folio.selectionInk : Folio.body)
				Spacer(minLength: 4)
				if badge > 0 {
					Text("\(badge)").font(.system(size: 12, weight: isSelected ? .semibold : .regular))
						.foregroundStyle(isSelected ? Folio.selectionInk : Folio.meta)
				}
			}
			.padding(.horizontal, 12)
			.frame(height: compact ? 30 : 38)
			.background(
				RoundedRectangle(cornerRadius: 9, style: .continuous)
					.fill(isSelected ? Folio.selection : (isHovering ? AppTheme.rowHighlight : .clear))
			)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { isHovering = $0 }
	}
}


/// One status in the sidebar: its dot, its name and how many conversations have it.
private struct StatusSidebarRow: View {
	var status: ThreadStatus
	var count: Int
	var isSelected: Bool
	var action: () -> Void

	@State private var isHovering = false

	var body: some View {
		Button(action: action) {
			HStack(spacing: 10) {
				StatusDot(status: status, size: 9)
				Text(status.title).font(.system(size: 13.5, weight: isSelected ? .semibold : .regular)).lineLimit(1)
					.foregroundStyle(isSelected ? Folio.selectionInk : Folio.body)
				Spacer(minLength: 4)
				Text("\(count)").font(.system(size: 13, weight: isSelected ? .semibold : .regular))
					.foregroundStyle(isSelected ? Folio.selectionInk : Folio.meta)
			}
			.padding(.horizontal, 12)
			.frame(height: 30)
			.background(
				RoundedRectangle(cornerRadius: 9, style: .continuous)
					.fill(isSelected ? Folio.selection : (isHovering ? AppTheme.rowHighlight : .clear))
			)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { isHovering = $0 }
	}
}

/// The mockups' small-caps section title: STATUS, FOLDERS, ACCOUNTS.
private struct SectionTitle: View {
	var text: String
	init(_ text: String) { self.text = text }

	var body: some View {
		Text(text.uppercased())
			.font(.system(size: 11, weight: .semibold)).tracking(0.9)
			.foregroundStyle(Folio.meta).lineLimit(1)
	}
}

/// The switcher's ⌃⌄ mark.
private struct UpDownChevron: View {
	var body: some View {
		VStack(spacing: 1) {
			HIcon(.chevronDown, size: 10).rotationEffect(.degrees(180))
			HIcon(.chevronDown, size: 10)
		}
		.frame(width: 16)
	}
}

/// One account in the Accounts section: its initial on a soft square, its name and unread count.
private struct AccountSidebarRow: View {
	var name: String
	var unread: Int
	var isSelected: Bool
	var action: () -> Void
	@State private var isHovering = false

	private var initial: String { name.first.map { String($0).uppercased() } ?? "?" }

	var body: some View {
		Button(action: action) {
			HStack(spacing: 10) {
				Text(initial).font(.system(size: 11, weight: .bold)).foregroundStyle(Folio.selectionInk)
					.frame(width: 20, height: 20)
					.background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Folio.selection))
				Text(name).font(.system(size: 13.5)).foregroundStyle(Folio.body).lineLimit(1)
				Spacer(minLength: 4)
				if unread > 0 { Text("\(unread)").font(.system(size: 12)).foregroundStyle(Folio.meta) }
			}
			.padding(.horizontal, 12)
			.frame(height: 30)
			.background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(isHovering ? AppTheme.rowHighlight : .clear))
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { isHovering = $0 }
	}
}

/// One line of the account switcher: pictures, name and address, unread count, and a check when chosen.
private struct SwitcherRow<Leading: View, Text_: View>: View {
	var isSelected: Bool
	var unread: Int
	var indent = false
	var action: () -> Void
	@ViewBuilder var leading: Leading
	@ViewBuilder var text: Text_

	@State private var isHovering = false

	var body: some View {
		Button(action: action) {
			HStack(spacing: 10) {
				leading
				VStack(alignment: .leading, spacing: 1) { text }
				Spacer(minLength: 4)
				if unread > 0 { CountBadge(count: unread) }
			}
			.padding(.leading, indent ? 22 : 10).padding(.trailing, 10).padding(.vertical, 6)
			.background(RoundedRectangle(cornerRadius: 9, style: .continuous)
				.fill(isSelected ? AppTheme.railSelection : (isHovering ? AppTheme.rowHighlight : .clear)))
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.padding(.horizontal, 4)
		.onHover { isHovering = $0 }
	}
}

/// A round profile picture, or the initials on a hashed-color circle when there is none (the cache
/// tries the server's picture, then Gravatar, before this).
struct ProfileAvatar: View {
	@Environment(MailStore.self) private var store
	var key: String
	var name: String
	var size: CGFloat

	var body: some View {
		Group {
			if let image = store.avatars.images[key] {
				Image(nsImage: image).resizable().scaledToFill()
			} else {
				Text(initials)
					.font(.system(size: size * 0.42, weight: .semibold))
					.foregroundStyle(AvatarStyle.text)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.background(AvatarStyle.background(for: key))
			}
		}
		.frame(width: size, height: size)
		.clipShape(Circle())
	}

	private var initials: String {
		let letter = name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() }
		return letter ?? "?"
	}
}

/// An unread count in a fully rounded, softly filled pill.
struct CountBadge: View {
	var count: Int

	var body: some View {
		Text(count > 999 ? "999+" : "\(count)")
			.font(Typography.meta.weight(.medium))
			.foregroundStyle(.secondary)
			.padding(.horizontal, 7).padding(.vertical, 1)
			.frame(minWidth: 22)
			.background(Capsule().fill(AppTheme.rowHighlight))
	}
}
