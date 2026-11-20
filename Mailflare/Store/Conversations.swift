import Foundation
import MailflareCore

/// Whole conversations: every message of a thread wherever it sits (Inbox, Sent, Archive, a
/// folder), and the trays that follow what happens in them. A reply sent from any device moves a
/// conversation from Needs you to Waiting; the other person's answer brings it back.
extension MailStore {
	/// The folders a conversation is gathered from.
	private func conversationSources(_ accountID: String) -> [Folder] {
		var folders: [Folder] = [.role(role: "inbox"), .role(role: "sent"), .role(role: "archive")]
		folders += customFolders(of: accountID).map { .mailbox(id: $0.id) }
		return folders
	}

	/// The messages of `anchor`'s conversation, oldest first, the anchor included.
	func conversation(of anchor: MessageSummary, accountID: String) -> [MessageSummary] {
		let raw = ViewMessageID.split(anchor.id).message
		guard !anchor.threadId.isEmpty else { return [anchor] }
		var found: [String: MessageSummary] = [:]
		for folder in conversationSources(accountID) {
			let limit: UInt32 = {
				if case .role = folder { return 400 }
				return 150
			}()
			guard let list = try? fetch(accountID, folder, limit: limit).list else { continue }
			for m in list where m.threadId == anchor.threadId { found[m.id] = m }
		}
		found[raw] = found[raw] ?? anchor
		return found.values.sorted { $0.receivedAt < $1.receivedAt }
	}

	/// Whether a message was written by one of the account's own addresses.
	func isMine(_ m: MessageSummary, accountID: String) -> Bool {
		let mine = Set(identities(forAccount: accountID).map { $0.email.lowercased() })
		return mine.contains(m.fromEmail.lowercased())
	}

	/// Moves Needs you and Waiting conversations along when a reply has gone out or come in since
	/// they were sorted, by the user's choices in Settings › Secretary.
	func reconcileConversations(force: Bool = false) {
		guard force || Date().timeIntervalSince(lastReconcile) > 45 else { return }
		lastReconcile = Date()
		guard SecretarySettings.autoWaiting || SecretarySettings.autoBack else { return }
		var changed = false
		for account in accountList where unifiedIncludes(account.id) {
			let open = statuses.records.values.filter {
				$0.accountID == account.id && ($0.status == .needsReply || $0.status == .waiting) && !($0.threadID ?? "").isEmpty
			}
			guard !open.isEmpty else { continue }
			let threads = Set(open.compactMap(\.threadID))
			var mineLatest: [String: MessageSummary] = [:]
			var theirsLatest: [String: MessageSummary] = [:]
			for folder in [Folder.role(role: "sent"), .role(role: "inbox"), .role(role: "archive")] {
				guard let list = try? fetch(account.id, folder, limit: 300).list else { continue }
				for m in list where threads.contains(m.threadId) {
					let sent: Bool = { if case .role(let r) = folder { return r == "sent" } ; return false }()
					if sent || isMine(m, accountID: account.id) {
						if (mineLatest[m.threadId]?.receivedAt ?? 0) < m.receivedAt { mineLatest[m.threadId] = m }
					} else if (theirsLatest[m.threadId]?.receivedAt ?? 0) < m.receivedAt {
						theirsLatest[m.threadId] = m
					}
				}
			}
			for record in open {
				guard let thread = record.threadID else { continue }
				let mine = mineLatest[thread]
				let theirs = theirsLatest[thread]
				let mineDate = mine.map { Date(timeIntervalSince1970: TimeInterval($0.receivedAt)) }
				let theirsDate = theirs.map { Date(timeIntervalSince1970: TimeInterval($0.receivedAt)) }
				switch record.status {
				case .needsReply where SecretarySettings.autoWaiting:
					// The user answered after the last message from the other side.
					guard let mineDate, mineDate > record.receivedAt, mineDate > (theirsDate ?? .distantPast) else { continue }
					let who = MailStore.who(name: record.fromName, email: record.fromEmail)
					statuses.set(.waiting, account: account.id, message: record.messageID, summary: nil,
								 reason: "You replied on \(Self.when(mineDate)), so this is waiting on \(who).")
					changed = true
				case .waiting where SecretarySettings.autoBack:
					// The other side answered after the user's last word.
					guard let theirs, let theirsDate, theirsDate > record.statusAt, theirsDate > (mineDate ?? .distantPast) else { continue }
					let who = MailStore.who(name: theirs.fromName, email: theirs.fromEmail)
					statuses.set(.needsReply, account: account.id, message: theirs.id, summary: theirs, kind: .reply,
								 reason: "\(who) answered on \(Self.when(theirsDate)), so it's back with you.")
					if theirs.id != record.messageID { statuses.remove(account: account.id, message: record.messageID) }
					changed = true
				default: continue
				}
			}
		}
		if changed, statusList != nil || statusFilter != .all { reload() }
	}

	nonisolated static func when(_ date: Date) -> String {
		let cal = Calendar.current
		let time = date.formatted(date: .omitted, time: .shortened)
		if cal.isDateInToday(date) { return "today at \(time)" }
		if cal.isDateInYesterday(date) { return "yesterday at \(time)" }
		return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + " at " + time
	}

	/// The short note at the top of a conversation: where it stands and what happens next.
	func standing(of record: ThreadRecord) -> String {
		let who = MailStore.who(name: record.fromName, email: record.fromEmail)
		switch record.status {
		case .needsReply:
			let kind = (record.kind ?? .reply)
			let what: String = {
				if let ask = record.ask, !ask.isEmpty { return "\(who): \(ask.prefix(1).lowercased() + ask.dropFirst())." }
				switch kind {
				case .reply: return "\(who) is waiting for your answer."
				case .decide: return "\(who) needs a decision from you."
				case .sign: return "Something here needs your signature."
				case .pay: return "Something here needs paying."
				case .read: return "Worth reading closely."
				}
			}()
			let due = record.due.map { " Due \(Self.when($0).components(separatedBy: " at ").first ?? "")." } ?? ""
			return [record.reason, what + due].compactMap { $0 }.joined(separator: " ")
		case .waiting:
			let chase = Calendar.current.date(byAdding: .day, value: SecretarySettings.chaseDays, to: record.statusAt) ?? record.statusAt
			let base = record.reason ?? "This is waiting on \(who)."
			let next = chase < .now
				? " It's been \(SecretarySettings.chaseDays)+ days with no answer: worth a nudge?"
				: " When they answer, it comes back to you. If nothing comes by \(chase.formatted(.dateTime.weekday(.wide))), \(SecretarySettings.name) will flag it."
			return base + next
		case .longTerm:
			return "Worth keeping. File it in a Library folder when you're ready."
		case .canArchive:
			return "Nothing here asks anything of you."
		}
	}

	/// Desk confirmations: archive one message by its account's own id.
	func archive(_ raw: String, accountID: String) {
		_ = try? core?.moveMessages(accountId: accountID, messageIds: [raw], target: .role(role: "archive"))
		statuses.remove(account: accountID, message: raw)
		afterDeskMove()
	}

	/// Desk confirmations: file one message into a Library folder.
	func file(_ raw: String, accountID: String, into folderID: String, name: String, quietly: Bool = false) {
		_ = try? core?.moveMessages(accountId: accountID, messageIds: [raw], target: .mailbox(id: folderID))
		statuses.remove(account: accountID, message: raw)
		if !quietly { showToast("Filed in \(name)", icon: .folder) }
		afterDeskMove()
	}

	private func afterDeskMove() {
		filingCache = [:]
		invalidateCaches()
		refreshMailboxes()
		reload()
	}
}
