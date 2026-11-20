import SwiftUI
import MailflareCore

/// Settings → Accounts and folders, as in the mockup: every mailbox with whether it is in All
/// accounts, buttons to add one, and the folders with the rules that file mail into them.
struct AccountsFoldersPage: View {
	@Environment(MailStore.self) private var store
	@State private var signingOut: Account?
	private var automation: Automation { Automation.shared }

	var body: some View {
		VStack(alignment: .leading, spacing: 40) {
			VStack(alignment: .leading, spacing: 10) {
				Text("Accounts and folders").font(.system(size: 36, weight: .bold)).tracking(-1.25).foregroundStyle(Folio.ink)
				Text("Add every mailbox once. Folders and statuses work across all of them, so a thread keeps its status wherever it came from.")
					.font(.system(size: 16)).lineSpacing(4).foregroundStyle(Folio.body)
					.frame(maxWidth: 640, alignment: .leading).fixedSize(horizontal: false, vertical: true)
			}
			accounts
			folders
		}
		.confirmationDialog("Sign out of \(signingOut.map(store.accountName) ?? "this account")?", isPresented: Binding(get: { signingOut != nil }, set: { if !$0 { signingOut = nil } }), titleVisibility: .visible) {
			Button("Sign Out", role: .destructive) { if let a = signingOut { store.signOut(a) }; signingOut = nil }
		} message: {
			Text("Its mail is removed from this Mac. Nothing changes on the server.")
		}
	}

	// MARK: Accounts

	private var accounts: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack(alignment: .firstTextBaseline) {
				Text("Accounts").font(.system(size: 20, weight: .bold)).tracking(-0.4).foregroundStyle(Folio.ink)
				Spacer()
				Text("In All accounts").font(.system(size: 12, weight: .semibold)).foregroundStyle(Folio.meta)
			}
			.padding(.bottom, 12)
			ForEach(store.accountList) { account in
				Rectangle().fill(Folio.line).frame(height: 1)
				accountRow(account)
			}
			Rectangle().fill(Folio.line).frame(height: 1)
			HStack(spacing: 10) {
				Text("Add account").font(.system(size: 13, weight: .semibold)).foregroundStyle(Folio.body).padding(.trailing, 6)
				ForEach(["Gmail", "iCloud", "Outlook", "Other (IMAP)"], id: \.self) { name in
					Button(name) { store.showAddAccount = true }
						.buttonStyle(FolioOutlineButtonStyle(ink: Folio.ink, height: 38))
				}
				Spacer(minLength: 0)
			}
			.padding(.top, 16)
		}
	}

	private func accountRow(_ account: Account) -> some View {
		let needsSignIn = KeychainCredentialStore().load(accountId: account.id) == nil
		let unread = store.unreadCount(accountID: account.id, inbox: nil)
		let included = store.unifiedIncludes(account.id)
		let name = store.accountName(account)
		return HStack(spacing: 16) {
			Text(name.first.map { String($0).uppercased() } ?? "?")
				.font(.system(size: 16, weight: .bold)).foregroundStyle(Folio.selectionInk)
				.frame(width: 40, height: 40)
				.background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Folio.selection))
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 8) {
					Text(name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Folio.ink).lineLimit(1)
					if account.id == store.account?.id {
						badge("In view", ink: Folio.selectionInk, fill: Folio.selection)
					}
					if needsSignIn { badge("Needs sign-in", ink: ThreadStatus.waiting.ink, fill: ThreadStatus.waiting.tint) }
				}
				Text(account.email + (unread > 0 ? " · \(unread) unread" : ""))
					.font(.system(size: 13)).foregroundStyle(Folio.meta).lineLimit(1)
			}
			Spacer(minLength: 8)
			if needsSignIn {
				Button("Sign in again") { store.showAddAccount = true }
					.buttonStyle(FolioOutlineButtonStyle(ink: ThreadStatus.waiting.ink, stroke: ThreadStatus.waiting.actionStroke, height: 34))
			}
			Toggle("", isOn: Binding(get: { included }, set: { store.setUnified(account.id, included: $0) }))
				.labelsHidden().toggleStyle(.switch).tint(Folio.accent).controlSize(.large)
				.disabled(included && store.unifiedIncludedCount <= 1)
				.help("Show this account's mail in All accounts")
			Menu {
				Button("Show This Account") { store.selectInbox(nil, accountID: account.id); store.settingsPage = nil }
				Divider()
				Button("Sign Out…", role: .destructive) { signingOut = account }
			} label: {
				HIcon(.more, size: 16).foregroundStyle(Folio.meta).frame(width: 28, height: 28)
			}
			.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
		}
		.frame(minHeight: 64)
	}

	private func badge(_ text: String, ink: Color, fill: Color) -> some View {
		Text(text).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(ink)
			.padding(.horizontal, 8).padding(.vertical, 2)
			.background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill))
	}

	// MARK: Folders

	private var folders: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack(alignment: .center) {
				Text("Folders").font(.system(size: 20, weight: .bold)).tracking(-0.4).foregroundStyle(Folio.ink)
				Spacer()
				if let account = store.account, store.canCreateFolders(accountID: account.id) {
					Button {
						store.folderRequest = .init(accountID: account.id, kind: .create(parentID: store.inboxAddresses.first?.id))
					} label: {
						HStack(spacing: 8) { HIcon(.add, size: 13); Text("New folder") }
					}
					.buttonStyle(FolioFilledButtonStyle(fill: Folio.dark, ink: Folio.onDark, height: 36))
				}
			}
			.padding(.bottom, 12)
			ForEach(store.accountList) { account in
				let boxes = store.customFolders(of: account.id)
				if store.accountList.count > 1 && !boxes.isEmpty {
					Text(store.accountName(account).uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.9)
						.foregroundStyle(Folio.meta).padding(.top, 14).padding(.bottom, 6)
				}
				ForEach(boxes) { box in
					Rectangle().fill(Folio.line).frame(height: 1)
					folderRow(box, account: account)
				}
			}
			Rectangle().fill(Folio.line).frame(height: 1)
		}
	}

	private func folderRow(_ box: Mailbox, account: Account) -> some View {
		let rules = automation.rules(forFolder: box.id, account: account.id)
		let nested = box.parentId != nil && store.customFolders(of: account.id).contains { $0.id == box.parentId }
		return HStack(spacing: 12) {
			HIcon(.folder, size: 17).foregroundStyle(store.folderColors.color(for: box.id) ?? Folio.body)
			Text(box.name).font(.system(size: 15, weight: nested ? .regular : .semibold)).foregroundStyle(Folio.ink).lineLimit(1)
			Spacer(minLength: 8)
			ForEach(rules) { rule in
				Text(rule.label).font(.system(size: 12)).foregroundStyle(Folio.body)
					.padding(.horizontal, 9).padding(.vertical, 3)
					.background(Capsule().fill(Folio.chip))
					.help("New mail \(rule.label.lowercased()) is filed here")
			}
			Text("\(box.totalEmails)").font(.system(size: 13)).foregroundStyle(Folio.meta).frame(minWidth: 32, alignment: .trailing)
			Menu {
				if let support = store.folderSupport(accountID: account.id) {
					if support.canRename { Button("Rename…") { store.folderRequest = .init(accountID: account.id, kind: .rename(box)) } }
					if support.canDelete { Button("Delete…", role: .destructive) { store.folderRequest = .init(accountID: account.id, kind: .delete(box)) } }
				}
				if !rules.isEmpty {
					Divider()
					ForEach(rules) { rule in Button("Stop Filing \(rule.label)") { Automation.shared.removeRule(rule) } }
				}
			} label: {
				HIcon(.more, size: 16).foregroundStyle(Folio.meta).frame(width: 28, height: 28)
			}
			.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
		}
		.padding(.leading, nested ? 30 : 0)
		.frame(minHeight: 50)
	}
}
