import Foundation
import Observation
import MailflareCore

/// A folder rule the user approved: mail from a sender's domain (or one address) that lands in the
/// inbox is filed into a folder. Rules live on this Mac only.
struct FolderRule: Codable, Identifiable, Equatable {
	var id = UUID().uuidString
	var accountID: String
	var folderID: String
	var folderName: String
	/// A domain ("riverside.co") or a full address ("jo@riverside.co").
	var match: String
	var created = Date()

	var label: String { match.contains("@") ? "From \(match)" : "From @\(match)" }

	func matches(_ m: MessageSummary) -> Bool {
		let from = m.fromEmail.lowercased()
		return match.contains("@") ? from == match : from.hasSuffix("@" + match) || from.hasSuffix("." + match)
	}
}

/// A folder rule SuperMail thinks would help, from where mail from the same domain was filed before.
struct RuleSuggestion: Identifiable, Equatable {
	var accountID: String
	var folderID: String
	var folderName: String
	var domain: String
	/// How many messages from the domain are already in the folder.
	var filed: Int
	/// How many are waiting in the inbox now.
	var waiting: Int
	/// Set when the user picked a different folder from the one learned.
	var changed = false
	var id: String { "\(accountID)|\(domain)" }
}

/// A status SuperMail suggests for one inbox message; nothing changes until it is accepted.
struct StatusSuggestion: Identifiable {
	var accountID: String
	var summary: MessageSummary
	var suggestion: StatusAssistant.Suggestion
	var id: String { "\(accountID)|\(summary.id)" }
}

/// The assistant's suggestions and the approved folder rules. Suggestions are worked out in the
/// background after new mail, at most every few minutes, and wait for the user to accept them.
@MainActor
@Observable
final class Automation {
	static let shared = Automation()

	private(set) var rules: [FolderRule] = []
	private(set) var ruleSuggestions: [RuleSuggestion] = []
	private(set) var statusSuggestions: [StatusSuggestion] = []
	private(set) var isSuggestingStatuses = false

	@ObservationIgnored private var dismissedRules: Set<String> = []
	@ObservationIgnored private var dismissedStatuses: Set<String> = []
	@ObservationIgnored private var lastRuleScan: Date = .distantPast
	@ObservationIgnored private var lastStatusScan: Date = .distantPast

	/// Webmail domains are shared by unrelated people, so they are never suggested as a whole.
	nonisolated private static let sharedDomains: Set<String> = [
		"gmail.com", "googlemail.com", "outlook.com", "hotmail.com", "live.com", "msn.com", "yahoo.com", "yahoo.com.au",
		"icloud.com", "me.com", "mac.com", "bigpond.com", "bigpond.net.au", "optusnet.com.au", "proton.me", "protonmail.com", "aol.com",
	]

	nonisolated static func isSharedDomain(_ domain: String) -> Bool { sharedDomains.contains(domain.lowercased()) }

	private init() {
		let defaults = UserDefaults.standard
		rules = defaults.data(forKey: "folio.folderRules").flatMap { try? JSONDecoder().decode([FolderRule].self, from: $0) } ?? []
		dismissedRules = Set(defaults.stringArray(forKey: "folio.dismissedRules") ?? [])
		dismissedStatuses = Set(defaults.stringArray(forKey: "folio.dismissedStatusSuggestions") ?? [])
	}

	private func saveRules() { UserDefaults.standard.set(try? JSONEncoder().encode(rules), forKey: "folio.folderRules") }

	func rules(forFolder id: String, account: String) -> [FolderRule] {
		rules.filter { $0.folderID == id && $0.accountID == account }
	}

	/// The suggestion for one listed message, if any.
	func statusSuggestion(account: String, message: String) -> StatusAssistant.Suggestion? {
		statusSuggestions.first { $0.accountID == account && $0.summary.id == message }?.suggestion
	}

	// MARK: Running

	/// After new mail and when Today opens: file what the rules cover, then refresh the suggestions.
	func run(_ store: MailStore, force: Bool = false) {
		if SecretarySettings.autoFile { applyRules(store) }
		if AssistantSettings.suggestFolders, force || Date().timeIntervalSince(lastRuleScan) > 300 {
			lastRuleScan = Date()
			scanRules(store)
		}
		if AssistantSettings.suggestStatus, force || sortIsDue {
			lastStatusScan = Date()
			Task { await suggestStatuses(store) }
		}
	}

	/// Whether new mail should be sorted now, by the user's choice in Settings › Secretary.
	private var sortIsDue: Bool {
		switch SecretarySettings.sortMode {
		case .onRequest: return false
		case .arrival: return Date().timeIntervalSince(lastStatusScan) > 600
		case .twiceDaily:
			// The last 8 am or 4 pm that has passed: sort once after each.
			let cal = Calendar.current
			let now = Date()
			let marks = [8, 16].compactMap { cal.date(bySettingHour: $0, minute: 0, second: 0, of: now) }.filter { $0 <= now }
			let last = marks.max() ?? cal.date(byAdding: .day, value: -1, to: cal.date(bySettingHour: 16, minute: 0, second: 0, of: now) ?? now) ?? now
			return lastStatusScan < last
		}
	}

	/// Files inbox mail that an approved rule covers. Returns how many moved.
	@discardableResult
	func applyRules(_ store: MailStore, only rule: FolderRule? = nil) -> Int {
		guard let core = store.core else { return 0 }
		var moved = 0
		for accountID in Set((rule.map { [$0] } ?? rules).map(\.accountID)) {
			let accountRules = (rule.map { [$0] } ?? rules).filter { $0.accountID == accountID }
			guard let inbox = try? store.fetch(accountID, .role(role: "inbox"), limit: 300).list else { continue }
			for r in accountRules {
				// Conversations waiting on the user (or on a reply) stay in the inbox where they are seen.
				let ids = inbox.filter { m in
					guard r.matches(m) else { return false }
					let status = store.statuses.status(account: accountID, message: m.id, thread: m.threadId)
					return status != .needsReply && status != .waiting
				}.map(\.id)
				guard !ids.isEmpty else { continue }
				if (try? core.moveMessages(accountId: accountID, messageIds: ids, target: .mailbox(id: r.folderID))) != nil { moved += ids.count }
			}
		}
		if moved > 0 {
			store.invalidateCaches()
			store.refreshMailboxes()
			store.reload()
		}
		return moved
	}

	// MARK: Folder rules

	/// Looks at each folder's recent mail: a domain filed there three or more times, and almost
	/// always there, with mail from it now in the inbox, becomes a suggestion.
	private func scanRules(_ store: MailStore) {
		var found: [RuleSuggestion] = []
		for account in store.accountList where store.unifiedIncludes(account.id) {
			guard let inbox = try? store.fetch(account.id, .role(role: "inbox"), limit: 300).list else { continue }
			let inboxDomains = Dictionary(grouping: inbox, by: { Self.domain($0.fromEmail) }).mapValues(\.count)
			var placements: [String: [String: Int]] = [:]   // domain → folder id → count
			var names: [String: String] = [:]
			for folder in store.customFolders(of: account.id) {
				names[folder.id] = folder.name
				guard let filed = try? store.fetch(account.id, .mailbox(id: folder.id), limit: 150).list else { continue }
				for m in filed {
					let d = Self.domain(m.fromEmail)
					guard !d.isEmpty else { continue }
					placements[d, default: [:]][folder.id, default: 0] += 1
				}
			}
			for (domain, folders) in placements {
				guard !Self.sharedDomains.contains(domain), let waiting = inboxDomains[domain], waiting > 0,
					  let best = folders.max(by: { $0.value < $1.value }), best.value >= 3 else { continue }
				let total = folders.values.reduce(0, +)
				guard Double(best.value) / Double(total) >= 0.8 else { continue }
				let id = "\(account.id)|\(domain)"
				guard !dismissedRules.contains(id), !rules.contains(where: { $0.accountID == account.id && $0.match == domain }) else { continue }
				found.append(RuleSuggestion(accountID: account.id, folderID: best.key, folderName: names[best.key] ?? "Folder",
											domain: domain, filed: best.value, waiting: waiting))
			}
		}
		// A folder the user already picked for a suggestion is kept when the list is worked out again.
		let picked = Dictionary(ruleSuggestions.filter(\.changed).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
		ruleSuggestions = Array(found.sorted { $0.waiting * 10 + $0.filed > $1.waiting * 10 + $1.filed }.prefix(6)).map { s in
			guard let p = picked[s.id] else { return s }
			var kept = s
			kept.folderID = p.folderID; kept.folderName = p.folderName; kept.changed = true
			return kept
		}
	}

	/// Turns a suggestion into a rule and files the matching inbox mail now.
	func accept(_ suggestion: RuleSuggestion, store: MailStore) {
		let rule = FolderRule(accountID: suggestion.accountID, folderID: suggestion.folderID, folderName: suggestion.folderName, match: suggestion.domain)
		rules.append(rule)
		saveRules()
		ruleSuggestions.removeAll { $0.id == suggestion.id }
		let moved = applyRules(store, only: rule)
		store.showToast("Filing @\(suggestion.domain) into \(suggestion.folderName)", detail: moved > 0 ? "Moved \(moved) from the inbox." : "", icon: .folder)
	}

	/// Points a suggested rule at another folder before it is accepted.
	func change(_ suggestion: RuleSuggestion, toFolder id: String, name: String) {
		guard let i = ruleSuggestions.firstIndex(where: { $0.id == suggestion.id }) else { return }
		ruleSuggestions[i].folderID = id
		ruleSuggestions[i].folderName = name
		ruleSuggestions[i].changed = true
	}

	func dismiss(_ suggestion: RuleSuggestion) {
		dismissedRules.insert(suggestion.id)
		UserDefaults.standard.set(Array(dismissedRules), forKey: "folio.dismissedRules")
		ruleSuggestions.removeAll { $0.id == suggestion.id }
	}

	func removeRule(_ rule: FolderRule) {
		rules.removeAll { $0.id == rule.id }
		saveRules()
	}

	private static func domain(_ email: String) -> String {
		guard let at = email.lastIndex(of: "@") else { return "" }
		return String(email[email.index(after: at)...]).lowercased()
	}

	// MARK: Status suggestions

	/// Suggests statuses for recent inbox mail that has none, with the assistant when one is
	/// connected and simple rules otherwise. Nothing is applied here.
	func suggestStatuses(_ store: MailStore) async {
		guard !isSuggestingStatuses else { return }
		isSuggestingStatuses = true
		defer { isSuggestingStatuses = false }
		var items: [(account: String, summary: MessageSummary)] = []
		for account in store.accountList where store.unifiedIncludes(account.id) {
			guard let page = try? store.fetch(account.id, .role(role: "inbox"), limit: 40) else { continue }
			for m in page.list where store.statuses.status(account: account.id, message: m.id, thread: m.threadId) == nil
				&& !dismissedStatuses.contains("\(account.id)|\(m.id)")
				&& !statusSuggestions.contains(where: { $0.accountID == account.id && $0.summary.id == m.id }) {
				items.append((account.id, m))
			}
		}
		items = Array(items.sorted { $0.summary.receivedAt > $1.summary.receivedAt }.prefix(20))
		guard !items.isEmpty else { return }
		func item(_ index: Int) -> StatusAssistant.Item {
			let m = items[index].summary
			return StatusAssistant.Item(id: String(index), from: m.sender.formatted, subject: m.subject, preview: PreviewText.plain(m.preview),
										folders: store.libraryFolders(of: items[index].account).map(\.path))
		}
		var answers: [String: StatusAssistant.Suggestion] = [:]
		// The notebook and the approved folder rules decide first; the assistant reads the rest.
		var open: [Int] = []
		for (index, pair) in items.enumerated() {
			if let entry = Notebook.shared.rule(for: pair.summary, account: pair.account), let status = entry.status {
				answers[String(index)] = StatusAssistant.Suggestion(status: status, folderID: entry.folderID, folderName: entry.folderName, notebookID: entry.id)
			} else if let rule = rules.first(where: { $0.accountID == pair.account && $0.matches(pair.summary) }) {
				answers[String(index)] = StatusAssistant.Suggestion(status: .longTerm, folderID: rule.folderID, folderName: rule.folderName,
																		   folderReason: "Your rule: \(rule.label.prefix(1).lowercased() + rule.label.dropFirst())")
			} else {
				open.append(index)
			}
		}
		if let client = store.ai.backgroundClient, !open.isEmpty {
			// The on-device model reads a few at a time; the others take the batch at once.
			let batch = client.onDevice ? 5 : 20
			for start in stride(from: 0, to: open.count, by: batch) {
				let slice = open[start..<min(start + batch, open.count)].map(item)
				if var found = try? await StatusAssistant.classify(client: client, items: slice) {
					// The model names a folder; match it to that account's folder.
					for (key, value) in found {
						guard let name = value.folderName, let index = Int(key) else { continue }
						let match = store.libraryFolders(of: items[index].account).first { $0.path.caseInsensitiveCompare(name) == .orderedSame }
						found[key]?.folderID = match?.id
						found[key]?.folderName = match?.name
					}
					answers.merge(found) { _, new in new }
				}
			}
		}
		var added: [StatusSuggestion] = []
		for (index, pair) in items.enumerated() {
			guard var s = answers[String(index)] ?? StatusAssistant.guess(item(index)) else { continue }
			// A model that calls a promotion "Needs you" is overruled, unless the notebook said so.
			let m = pair.summary
			if s.status == .needsReply, s.notebookID == nil,
			   StatusAssistant.isBroadcast(from: m.sender.formatted, subject: m.subject, preview: PreviewText.plain(m.preview)) {
				s.status = .canArchive; s.kind = nil; s.ask = nil
			}
			// For mail going to the Library, the folder follows the user's own filing habit first.
			if s.notebookID == nil, s.folderReason == nil, let usual = store.usualFolder(for: pair.summary, accountID: pair.account) {
				// Kept for every email, so changing one to To file starts from the usual folder.
				s.folderID = usual.id; s.folderName = usual.name; s.folderReason = usual.reason
			} else if s.status == .longTerm, s.folderID != nil, s.folderReason == nil {
				s.folderReason = s.notebookID != nil ? "From \(SecretarySettings.possessive) notebook" : "\(SecretarySettings.name)'s best guess from the email"
			}
			added.append(StatusSuggestion(accountID: pair.account, summary: pair.summary, suggestion: s))
		}
		// Anything sorted meanwhile is left out.
		statusSuggestions = (statusSuggestions + added).filter {
			store.statuses.status(account: $0.accountID, message: $0.summary.id, thread: $0.summary.threadId) == nil
		}
	}

	/// Statuses the user picked in place of the suggested ones, before accepting, by suggestion id.
	var statusChoices: [String: ThreadStatus] = [:]
	/// Folders the user picked for To file, by suggestion id.
	var folderChoices: [String: (id: String, name: String)] = [:]

	func folder(of item: StatusSuggestion) -> (id: String, name: String)? {
		if let picked = folderChoices[item.id] { return picked }
		guard status(of: item) == .longTerm, let id = item.suggestion.folderID else { return nil }
		return (id, item.suggestion.folderName ?? "Folder")
	}

	/// Files a suggestion into a folder before it is accepted: it becomes To file there.
	func chooseFolder(_ id: String, name: String, for item: StatusSuggestion) {
		statusChoices[item.id] = item.suggestion.status == .longTerm ? nil : .longTerm
		folderChoices[item.id] = (id, name)
	}

	/// The status a suggestion will be accepted as: the user's pick, or the assistant's.
	func status(of item: StatusSuggestion) -> ThreadStatus { statusChoices[item.id] ?? item.suggestion.status }

	/// Changes a suggestion before it is accepted; nothing is applied yet.
	func choose(_ status: ThreadStatus, for item: StatusSuggestion) {
		statusChoices[item.id] = status == item.suggestion.status ? nil : status
		if status != .longTerm { folderChoices[item.id] = nil }
	}

	/// Confirms one suggestion. Confirming is the user's go-ahead: Can archive moves the mail to
	/// Archive and To file with a folder moves it there; the others become the conversation's tray.
	func accept(_ item: StatusSuggestion, as status: ThreadStatus? = nil, store: MailStore, quietly: Bool = false) {
		let s = item.suggestion
		let final = status ?? self.status(of: item)
		let folder = folder(of: item)
		defer { statusChoices[item.id] = nil; folderChoices[item.id] = nil }
		statusSuggestions.removeAll { $0.id == item.id }
		if let id = s.notebookID, final == s.status, folder?.id == s.folderID,
		   let entry = Notebook.shared.entries.first(where: { $0.id == id }) { Notebook.shared.confirmed(entry) }
		if !quietly {
			Notebook.shared.noticeChange(from: item.summary, account: item.accountID, to: final, suggested: s.status,
										 folderID: folder?.id, folderName: folder?.name)
		}
		switch final {
		case .canArchive:
			store.archive(item.summary.id, accountID: item.accountID)
		case .longTerm where folder != nil:
			store.file(item.summary.id, accountID: item.accountID, into: folder!.id, name: folder!.name, quietly: quietly)
		default:
			store.statuses.set(final, account: item.accountID, message: item.summary.id, summary: item.summary, ask: s.ask, due: s.due,
							   kind: final == .needsReply ? s.kind : nil, reason: "Sorted by \(SecretarySettings.name), confirmed by you")
		}
		if store.statusList != nil || store.statusFilter != .all { store.reload() }
	}

	func acceptAllStatuses(store: MailStore) {
		let all = statusSuggestions
		let chosen = all.map { status(of: $0) }
		for (item, status) in zip(all, chosen) { accept(item, as: status, store: store, quietly: true) }
		store.showToast("Sorted \(all.count) email\(all.count == 1 ? "" : "s")", icon: .sparkles)
	}

	func dismiss(_ item: StatusSuggestion) {
		dismissedStatuses.insert(item.id)
		UserDefaults.standard.set(Array(dismissedStatuses.suffix(2000)), forKey: "folio.dismissedStatusSuggestions")
		statusSuggestions.removeAll { $0.id == item.id }
		statusChoices[item.id] = nil
		folderChoices[item.id] = nil
	}

	/// Drops the suggestion for a message once it is given a status some other way.
	func resolved(account: String, message: String) {
		statusSuggestions.removeAll { $0.accountID == account && $0.summary.id == message }
	}
}
