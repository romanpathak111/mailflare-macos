import Foundation
import Observation
import MailflareCore

/// A conversation with a status, and enough of its message to show it on Today and the board
/// without loading the mail again.
struct ThreadRecord: Codable, Identifiable, Hashable {
	var accountID: String
	var messageID: String
	var status: ThreadStatus
	var subject: String
	var fromName: String
	var fromEmail: String
	var preview: String
	var receivedAt: Date
	/// When the status was given: how long a thread has been waiting counts from here.
	var statusAt: Date
	/// The conversation the message belongs to, so one conversation never sits in two columns.
	var threadID: String?
	/// Set by the assistant (or by hand) when a reply is due on a given day.
	var due: Date?
	/// The assistant's one-line reason or ask ("Confirm Friday's session").
	var ask: String?

	var id: String { StatusStore.key(account: accountID, message: messageID) }
	var senderDisplay: String { fromName.isEmpty ? fromEmail : fromName }

	/// When the wait began: for mail that needs a reply, when it arrived (however late it was sorted);
	/// for a conversation waiting on someone else, when the status was given, which is when the reply went out.
	var since: Date { status == .needsReply ? min(receivedAt, statusAt) : statusAt }

	var isDueToday: Bool { status == .needsReply && (due.map { Calendar.current.isDateInToday($0) } ?? false) }

	/// "3 days", "Yesterday", "Due today": what Today shows at the end of a row.
	func age(now: Date = .now) -> String {
		let calendar = Calendar.current
		if status == .needsReply, let due, calendar.isDate(due, inSameDayAs: now) { return "Due today" }
		let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: since), to: calendar.startOfDay(for: now)).day ?? 0
		switch days {
		case ..<1: return "Today"
		case 1: return "Yesterday"
		default: return "\(days) days"
		}
	}
}

/// Statuses given to conversations, kept on this Mac as one JSON file. A conversation is the message
/// it was given to, by account and message id.
@MainActor
@Observable
final class StatusStore {
	private(set) var records: [String: ThreadRecord] = [:]
	@ObservationIgnored private let file: URL?

	init(file: URL? = StatusStore.defaultFile()) {
		self.file = file
		guard let file, let data = try? Data(contentsOf: file) else { return }
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .secondsSince1970
		if let saved = try? decoder.decode([ThreadRecord].self, from: data) {
			records = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
		}
	}

	nonisolated static func key(account: String, message: String) -> String { "\(account)\u{1F}\(message)" }

	nonisolated static func defaultFile() -> URL? {
		var base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
			.appendingPathComponent("Mailflare", isDirectory: true)
		#if DEBUG
		if let scratch = ProcessInfo.processInfo.environment["MAILFLARE_DATA_DIR"] { base = URL(fileURLWithPath: scratch, isDirectory: true) }
		#endif
		guard let base else { return nil }
		try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
		return base.appendingPathComponent("thread-status.json")
	}

	// MARK: Reading

	func status(account: String, message: String) -> ThreadStatus? { records[Self.key(account: account, message: message)]?.status }

	func record(account: String, message: String) -> ThreadRecord? { records[Self.key(account: account, message: message)] }

	/// The status of the conversation a message is in: its own, or the one given to another message of the thread.
	func status(account: String, message: String, thread: String?) -> ThreadStatus? {
		if let own = status(account: account, message: message) { return own }
		guard let thread, !thread.isEmpty else { return nil }
		return records.values.first { $0.accountID == account && $0.threadID == thread }?.status
	}

	/// Sets or clears the day a reply is due.
	func setDue(_ due: Date?, account: String, message: String) {
		let key = Self.key(account: account, message: message)
		guard var record = records[key] else { return }
		record.due = due
		records[key] = record
		save()
	}

	/// The conversations with `status`: the ones due first, then the longest waiting.
	func records(with status: ThreadStatus) -> [ThreadRecord] {
		records.values.filter { $0.status == status }.sorted { a, b in
			switch (a.due, b.due) {
			case let (x?, y?) where x != y: return x < y
			case (_?, nil): return true
			case (nil, _?): return false
			default: return a.since < b.since
			}
		}
	}

	func count(_ status: ThreadStatus) -> Int { records.values.lazy.filter { $0.status == status }.count }

	// MARK: Changing

	/// Gives a conversation a status. Setting the status it already has changes nothing, so its age is kept.
	func set(_ status: ThreadStatus, account: String, message: String, summary: MessageSummary?, ask: String? = nil, due: Date? = nil) {
		let key = Self.key(account: account, message: message)
		if var existing = records[key] {
			if existing.status != status { existing.status = status; existing.statusAt = .now; existing.due = due; existing.ask = ask }
			else { existing.ask = ask ?? existing.ask; existing.due = due ?? existing.due }
			if let summary { existing.fill(from: summary) }
			records[key] = existing
			dropSiblings(of: existing)
		} else {
			var record = ThreadRecord(accountID: account, messageID: message, status: status, subject: "", fromName: "", fromEmail: "",
									  preview: "", receivedAt: .now, statusAt: .now, due: due, ask: ask)
			if let summary { record.fill(from: summary) }
			records[key] = record
			dropSiblings(of: record)
		}
		save()
	}

	/// A conversation has one status: giving it to one message takes it off the others in its thread.
	private func dropSiblings(of record: ThreadRecord) {
		guard let thread = record.threadID, !thread.isEmpty else { return }
		for (key, other) in records where key != record.id && other.accountID == record.accountID && other.threadID == thread {
			records[key] = nil
		}
	}

	func remove(account: String, message: String) {
		guard records.removeValue(forKey: Self.key(account: account, message: message)) != nil else { return }
		save()
	}

	/// Drops everything for an account that was signed out.
	func forget(account: String) {
		let before = records.count
		records = records.filter { $0.value.accountID != account }
		if records.count != before { save() }
	}

	private func save() {
		guard let file else { return }
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .secondsSince1970
		if let data = try? encoder.encode(Array(records.values)) { try? data.write(to: file, options: .atomic) }
	}
}

private extension ThreadRecord {
	mutating func fill(from summary: MessageSummary) {
		threadID = summary.threadId
		subject = summary.subject
		fromName = summary.fromName
		fromEmail = summary.fromEmail
		preview = PreviewText.plain(summary.preview)
		receivedAt = summary.date
	}
}
