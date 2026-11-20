import Foundation
import Observation
import MailflareCore

/// Who the secretary is and how much they do on their own. Everything here is the user's choice in
/// Settings › Secretary; nothing that sends, deletes or unsubscribes can ever be switched on.
enum SecretarySettings {
	static let nameKey = "secretary.name"
	static let pronounKey = "secretary.pronoun"
	static let personalityKey = "secretary.personality"
	static let sortModeKey = "secretary.sortMode"
	static let headsUpKey = "secretary.headsUp"
	static let autoWaitingKey = "secretary.autoWaiting"
	static let autoBackKey = "secretary.autoBack"
	static let autoRememberKey = "secretary.autoRemember"
	static let autoFileKey = "secretary.autoFile"
	static let chaseDaysKey = "secretary.chaseDays"
	static let askShortcutKey = "secretary.askShortcut"

	enum Pronoun: String, CaseIterable, Identifiable {
		case name, they, she, he
		var id: String { rawValue }
		var title: String {
			switch self {
			case .name: "By name only"
			case .they: "they / them"
			case .she: "she / her"
			case .he: "he / him"
			}
		}
	}

	enum Personality: String, CaseIterable, Identifiable {
		case brief, warm, formal
		var id: String { rawValue }
		var title: String { rawValue.capitalized }
		var sample: String {
			switch self {
			case .brief: "“Mira wants Thursday. Yes or no?”"
			case .warm: "“Mira's asked to move to Thursday. Shall I…”"
			case .formal: "“Dr Chen requests a change to Thursday.”"
			}
		}
		/// How the assistant is told to sound.
		var instruction: String {
			switch self {
			case .brief: "Be brief and direct: short sentences, no pleasantries."
			case .warm: "Be warm and friendly, like a trusted colleague, but keep it short."
			case .formal: "Be formal and precise, as a professional executive assistant would."
			}
		}
	}

	enum SortMode: String, CaseIterable, Identifiable {
		case arrival, twiceDaily, onRequest
		var id: String { rawValue }
		var title: String {
			switch self {
			case .arrival: "As it arrives"
			case .twiceDaily: "Twice a day (8 am and 4 pm)"
			case .onRequest: "Only when I ask"
			}
		}
	}

	enum HeadsUp: String, CaseIterable, Identifiable {
		case quiet, balanced, proactive
		var id: String { rawValue }
		var title: String { rawValue.capitalized }
	}

	private static var d: UserDefaults { .standard }
	private static func flag(_ key: String, _ value: Bool) -> Bool { d.object(forKey: key) as? Bool ?? value }

	static var name: String {
		let n = (d.string(forKey: nameKey) ?? "").trimmingCharacters(in: .whitespaces)
		return n.isEmpty ? "Sam" : n
	}
	static var pronoun: Pronoun { Pronoun(rawValue: d.string(forKey: pronounKey) ?? "") ?? .name }
	static var personality: Personality { Personality(rawValue: d.string(forKey: personalityKey) ?? "") ?? .brief }
	static var sortMode: SortMode { SortMode(rawValue: d.string(forKey: sortModeKey) ?? "") ?? .arrival }
	static var headsUp: HeadsUp { HeadsUp(rawValue: d.string(forKey: headsUpKey) ?? "") ?? .balanced }
	/// Move a conversation to Waiting when the user replies, from any device.
	static var autoWaiting: Bool { flag(autoWaitingKey, true) }
	/// Bring a Waiting conversation back to Needs you when the other person answers.
	static var autoBack: Bool { flag(autoBackKey, true) }
	/// Add notebook entries without asking first.
	static var autoRemember: Bool { flag(autoRememberKey, false) }
	/// File and archive by notebook entries confirmed five times or more.
	static var autoFile: Bool { flag(autoFileKey, false) }
	/// Days without an answer before a Waiting conversation is flagged.
	static var chaseDays: Int { max(1, d.object(forKey: chaseDaysKey) as? Int ?? 3) }
	static var askShortcut: Bool { flag(askShortcutKey, true) }

	/// "Sam's notebook", "Ask Sam".
	static var possessive: String { name.hasSuffix("s") ? "\(name)'" : "\(name)'s" }

	/// The lines that set the assistant's character, for every prompt it gets.
	static var characterPrompt: String {
		var lines = ["You are \(name), the user's secretary inside the SuperMail Mac app.", personality.instruction]
		switch pronoun {
		case .name: lines.append("Never refer to yourself with a gendered pronoun.")
		case .they: lines.append("If you refer to yourself in the third person, use they/them.")
		case .she: lines.append("If you refer to yourself in the third person, use she/her.")
		case .he: lines.append("If you refer to yourself in the third person, use he/him.")
		}
		lines.append("Do not assume anyone's gender: refer to people by name unless their pronouns are clear from the email.")
		return lines.joined(separator: " ")
	}
}

/// One thing the secretary has learned or been told. A `match` (an address or a domain) makes it a
/// sorting rule; without one it is a standing instruction read before every sort.
struct NotebookEntry: Codable, Identifiable, Equatable {
	var id = UUID().uuidString
	var text: String
	var match: String?
	var status: ThreadStatus?
	var accountID: String?
	var folderID: String?
	var folderName: String?
	var created = Date()
	var source: String
	/// How many times the user confirmed a sort this entry proposed.
	var confirmations = 0

	func matches(_ m: MessageSummary, account: String) -> Bool {
		guard let match, !match.isEmpty else { return false }
		if let accountID, accountID != account { return false }
		let from = m.fromEmail.lowercased()
		return match.contains("@") ? from == match : from.hasSuffix("@" + match) || from.hasSuffix("." + match)
	}
}

/// What the user changed that looks worth remembering, waiting for "Yes, remember" or "Just this once".
struct PendingLesson: Identifiable, Equatable {
	var id = UUID().uuidString
	var entry: NotebookEntry
	var question: String
}

/// The secretary's notebook: kept on this Mac as one JSON file, readable and editable in Settings.
@MainActor
@Observable
final class Notebook {
	static let shared = Notebook()

	private(set) var entries: [NotebookEntry] = []
	var pending: PendingLesson?
	@ObservationIgnored private let file: URL?

	private init() {
		file = StatusStore.defaultFile()?.deletingLastPathComponent().appendingPathComponent("notebook.json")
		if let file, let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([NotebookEntry].self, from: data) {
			entries = saved
			Self.sharedPromptText = promptText
		} else {
			entries = [NotebookEntry(text: "Don't write reply drafts unless I ask.", source: "Standing instruction")]
			save()
		}
	}

	private func save() {
		Self.sharedPromptText = promptText
		guard let file, let data = try? JSONEncoder().encode(entries) else { return }
		try? data.write(to: file, options: .atomic)
	}

	func add(_ entry: NotebookEntry) {
		// One entry per sender: a newer lesson replaces the older one.
		if let match = entry.match { entries.removeAll { $0.match == match && $0.accountID == entry.accountID } }
		entries.insert(entry, at: 0)
		save()
	}

	func addInstruction(_ text: String) {
		let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !t.isEmpty else { return }
		add(NotebookEntry(text: t, source: "You told \(SecretarySettings.name)"))
	}

	func update(_ entry: NotebookEntry) {
		guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
		entries[i] = entry
		save()
	}

	func remove(_ entry: NotebookEntry) {
		entries.removeAll { $0.id == entry.id }
		save()
	}

	func removeAll() { entries = []; save() }

	/// The sorting rule for a message, if the notebook has one.
	func rule(for m: MessageSummary, account: String) -> NotebookEntry? {
		entries.first { $0.status != nil && $0.matches(m, account: account) }
	}

	func confirmed(_ entry: NotebookEntry) {
		guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
		entries[i].confirmations += 1
		save()
	}

	/// The notebook as the assistant reads it before sorting or answering.
	var promptText: String {
		guard !entries.isEmpty else { return "" }
		return "What the user has taught you (follow these):\n" + entries.prefix(60).map { "- \($0.text)" }.joined(separator: "\n")
	}

	/// The prompt text, readable from the background tasks that build prompts.
	nonisolated(unsafe) static var sharedPromptText = ""

	/// The notebook as plain text, for Export.
	var exportText: String {
		entries.map { "\($0.text)  (\($0.source), \($0.created.formatted(date: .abbreviated, time: .omitted)))" }.joined(separator: "\n")
	}

	// MARK: Learning from a change

	/// The user moved a conversation from what was suggested to `status`. When the sender looks like
	/// a pattern (automated mail, or a domain of its own), ask once whether to remember it.
	func noticeChange(from summary: MessageSummary, account: String, to status: ThreadStatus, suggested: ThreadStatus?, folderID: String? = nil, folderName: String? = nil) {
		guard status != suggested else { return }
		let email = summary.fromEmail.lowercased()
		guard let at = email.lastIndex(of: "@") else { return }
		let domain = String(email[email.index(after: at)...])
		let shared = Automation.isSharedDomain(domain)
		let match = shared ? email : domain
		let who = summary.fromName.isEmpty ? (shared ? email : domain) : summary.fromName
		let target = status == .longTerm && folderName != nil ? "To file: \(folderName!)" : status.title
		var entry = NotebookEntry(text: "Mail from \(who) → \(target)", match: match, status: status, accountID: account,
								  folderID: folderID, folderName: folderName, source: "From your change on \(Date().formatted(date: .abbreviated, time: .omitted))")
		if entries.contains(where: { $0.match == match && $0.status == status && $0.folderID == folderID }) { return }
		if SecretarySettings.autoRemember {
			entry.source = "Learned on its own"
			add(entry)
			return
		}
		pending = PendingLesson(entry: entry, question: "Moved to \(target). Should I do the same with mail from \(who) from now on?")
	}

	func acceptPending() {
		guard let p = pending else { return }
		add(p.entry)
		pending = nil
	}
}
