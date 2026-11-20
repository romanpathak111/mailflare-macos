import Foundation
import MailflareCore

/// One folder of the Library, in the department (account) it belongs to.
/// A folder guessed for a To file email, and why.
struct FolderGuess: Hashable {
	var id: String
	var name: String
	var reason: String
}

struct LibraryFolder: Identifiable, Hashable {
	var id: String
	var accountID: String
	/// The folder's own name, readable (IMAP's encoded names decoded).
	var name: String
	/// The whole path, "Parent / Child", as the assistant and menus show it.
	var path: String
	var depth: Int
	var parentID: String?
	var unread: Int
	var total: Int
}

extension MailStore {
	// MARK: Names

	/// IMAP folder names arrive in modified UTF-7 ("&2D3c5Q-" is an emoji): decoded for people.
	nonisolated static func readableFolderName(_ raw: String) -> String {
		guard raw.contains("&") else { return raw }
		var out = ""
		var i = raw.startIndex
		while i < raw.endIndex {
			let c = raw[i]
			guard c == "&", let dash = raw[raw.index(after: i)...].firstIndex(of: "-") else {
				out.append(c); i = raw.index(after: i); continue
			}
			let chunk = String(raw[raw.index(after: i)..<dash])
			if chunk.isEmpty {
				out.append("&")
			} else {
				var b64 = chunk.replacingOccurrences(of: ",", with: "/")
				while b64.count % 4 != 0 { b64 += "=" }
				if let data = Data(base64Encoded: b64), let text = String(data: data, encoding: .utf16BigEndian) {
					out += text
				} else {
					out += "&" + chunk + "-"
				}
			}
			i = raw.index(after: dash)
		}
		return out
	}

	/// The readable last part of a folder's name.
	func folderTitle(_ box: Mailbox) -> String {
		let full = Self.readableFolderName(box.name)
		return full.split(separator: "/").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? full
	}

	// MARK: Folders by department

	private static let libraryHiddenKey = "library.hidden"
	var hiddenLibraryFolders: Set<String> {
		_ = libraryModeRevision
		return Set(UserDefaults.standard.stringArray(forKey: Self.libraryHiddenKey) ?? [])
	}

	func setLibraryFolder(_ id: String, hidden: Bool) {
		var set = hiddenLibraryFolders
		if hidden { set.insert(id) } else { set.remove(id) }
		UserDefaults.standard.set(Array(set), forKey: Self.libraryHiddenKey)
		libraryModeRevision += 1
	}

	/// An account's own folders and labels, parents before their children, alphabetical. Server
	/// folders ([Gmail] and its system boxes, the address inboxes) are left out.
	func libraryFolders(of accountID: String, includeHidden: Bool = false) -> [LibraryFolder] {
		let boxes = mailboxes(of: accountID)
		let addresses = Set(Self.addressMailboxes(in: boxes).map(\.id))
		let byID = Dictionary(boxes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
		let hidden = includeHidden ? [] : hiddenLibraryFolders
		let system: Set<String> = ["[gmail]", "[google mail]", "inbox", "sync issues", "conflicts", "local failures", "server failures"]
		let own = boxes.filter { box in
			guard box.role == nil, !addresses.contains(box.id), !hidden.contains(box.id) else { return false }
			let lower = box.name.lowercased()
			return !system.contains(lower) && !system.contains(where: { lower.hasPrefix($0 + "/") })
		}
		let ownIDs = Set(own.map(\.id))
		let names = Set(own.map(\.name))
		// The parent in the Library: the server's parent, or the folder whose name is the path prefix.
		func parent(of box: Mailbox) -> String? {
			if let p = box.parentId, ownIDs.contains(p) { return p }
			guard let slash = box.name.lastIndex(of: "/") else { return nil }
			let prefix = String(box.name[..<slash])
			guard names.contains(prefix) else { return nil }
			return own.first { $0.name == prefix }?.id
		}
		let parents = Dictionary(own.map { ($0.id, parent(of: $0)) }, uniquingKeysWith: { a, _ in a })
		var children: [String?: [Mailbox]] = [:]
		for box in own { children[parents[box.id] ?? nil, default: []].append(box) }
		var result: [LibraryFolder] = []
		func walk(_ key: String?, depth: Int, path: String) {
			let kids = (children[key] ?? []).sorted { folderTitle($0).localizedCaseInsensitiveCompare(folderTitle($1)) == .orderedAscending }
			for box in kids {
				let title = folderTitle(box)
				let full = path.isEmpty ? title : path + " / " + title
				result.append(LibraryFolder(id: box.id, accountID: accountID, name: title, path: full, depth: depth,
											parentID: parents[box.id] ?? nil, unread: Int(box.unreadEmails), total: Int(box.totalEmails)))
				walk(box.id, depth: depth + 1, path: full)
			}
		}
		walk(nil, depth: 0, path: "")
		_ = byID
		return result
	}

	// MARK: Where mail like this has been filed before

	/// For each sender address and domain, the folder its mail has been filed in most, from what is in
	/// the folders now. Worked out from the saved lists, so it is quick and works offline.
	func filingHistory(of accountID: String) -> [String: (id: String, name: String, count: Int)] {
		if let cached = filingCache[accountID], Date().timeIntervalSince(cached.at) < 600 { return cached.map }
		var counts: [String: [String: Int]] = [:]
		let folders = libraryFolders(of: accountID)
		for folder in folders {
			guard let list = try? fetch(accountID, .mailbox(id: folder.id), limit: 200).list else { continue }
			for m in list {
				let email = m.fromEmail.lowercased()
				guard !email.isEmpty else { continue }
				counts[email, default: [:]][folder.id, default: 0] += 1
				if let domain = email.split(separator: "@").last.map(String.init), !Self.isSharedDomain(domain) {
					counts["@" + domain, default: [:]][folder.id, default: 0] += 1
				}
			}
		}
		let names = Dictionary(folders.map { ($0.id, $0.path) }, uniquingKeysWith: { a, _ in a })
		var map: [String: (id: String, name: String, count: Int)] = [:]
		for (key, perFolder) in counts {
			guard let best = perFolder.max(by: { $0.value < $1.value }), let name = names[best.key] else { continue }
			map[key] = (best.key, name, best.value)
		}
		filingCache[accountID] = (Date(), map)
		return map
	}

	/// The folder mail from this sender usually goes in, and why, when there is a habit to go on.
	func usualFolder(for m: MessageSummary, accountID: String) -> (id: String, name: String, reason: String)? {
		let history = filingHistory(of: accountID)
		let email = m.fromEmail.lowercased()
		let who = m.senderDisplay
		if let hit = history[email], hit.count >= 1 {
			return (hit.id, hit.name, "You've filed \(hit.count) from \(who) here")
		}
		if let domain = email.split(separator: "@").last, let hit = history["@" + domain], hit.count >= 2 {
			return (hit.id, hit.name, "You've filed \(hit.count) from \(domain) here")
		}
		return nil
	}

	/// Where a To file email should go: the usual folder for its sender, or else the guess made for it.
	func suggestedFolder(for m: MessageSummary, accountID: String) -> (id: String, name: String, reason: String)? {
		if let usual = usualFolder(for: m, accountID: accountID) { return usual }
		let raw = ViewMessageID.split(m.id).message
		guard let guess = folderGuesses[StatusStore.key(account: accountID, message: raw)] else { return nil }
		return (guess.id, guess.name, guess.reason)
	}

	/// Guesses a folder for each To file email that has no usual one: first a folder whose name the
	/// email's sender or subject contains, then Sam reads the rest against the account's folder list.
	func guessFolders(for records: [ThreadRecord]) {
		let open = records.filter { r in
			guard r.status == .longTerm, !folderGuessesAsked.contains(r.id) else { return false }
			let summary = MessageSummary.stand(in: r)
			return usualFolder(for: summary, accountID: r.accountID) == nil
		}
		guard !open.isEmpty else { return }
		open.forEach { folderGuessesAsked.insert($0.id) }
		var left: [ThreadRecord] = []
		for r in open {
			if let hit = Self.nameMatch(r, folders: libraryFolders(of: r.accountID)) { folderGuesses[r.id] = hit } else { left.append(r) }
		}
		guard !left.isEmpty, let client = ai.backgroundClient else { return }
		Task { [weak self] in
			guard let self else { return }
			let items = left.map { r in
				StatusAssistant.Item(id: r.id, from: r.senderDisplay + " <" + r.fromEmail + ">", subject: r.subject, preview: r.preview,
									 folders: libraryFolders(of: r.accountID).map(\.path))
			}
			guard let found = try? await StatusAssistant.classify(client: client, items: items) else { return }
			for r in left {
				guard let name = found[r.id]?.folderName,
					  let folder = libraryFolders(of: r.accountID).first(where: { $0.path.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
				folderGuesses[r.id] = FolderGuess(id: folder.id, name: folder.path, reason: "\(SecretarySettings.possessive) guess from the email")
			}
		}
	}

	/// A folder whose name shares a distinctive word with the sender, their address or the subject.
	private static func nameMatch(_ r: ThreadRecord, folders: [LibraryFolder]) -> FolderGuess? {
		let common: Set<String> = ["mail", "email", "inbox", "info", "notification", "notifications", "with", "from", "your", "this", "that",
								   "about", "update", "updates", "news", "team", "other", "misc", "important", "personal", "work", "later", "reply"]
		func words(_ text: String) -> Set<String> {
			Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 4 && $0.allSatisfy(\.isLetter) && !common.contains($0) })
		}
		let haystack = words(r.fromName + " " + r.fromEmail + " " + r.subject)
		var best: (LibraryFolder, String)?
		for folder in folders {
			if let word = words(folder.name).first(where: { haystack.contains($0) }) {
				if best == nil || folder.depth > best!.0.depth { best = (folder, word) }
			}
		}
		return best.map { FolderGuess(id: $0.0.id, name: $0.0.path, reason: "Its name matches \u{201C}\($0.1)\u{201D}") }
	}

	nonisolated static func isSharedDomain(_ domain: String) -> Bool {
		["gmail.com", "googlemail.com", "outlook.com", "hotmail.com", "live.com", "icloud.com", "me.com", "yahoo.com",
		 "bigpond.com", "proton.me", "protonmail.com"].contains(domain.lowercased())
	}
}

extension MailStore {
	/// Opens one account's section of the Library.
	func openShelf(_ accountID: String) {
		settingsPage = nil
		boardFocus = nil
		statusList = nil
		screen = .shelf(accountID)
	}

	/// Opens a Library folder, in its own account.
	func openLibraryFolder(_ folder: LibraryFolder) {
		statusList = nil
		openAccountItem(.mailbox(folder.id), accountID: folder.accountID)
	}

	/// The newest few messages of a folder, from the saved list.
	func latest(in folder: LibraryFolder, limit: UInt32 = 3) -> [MessageSummary] {
		(try? fetch(folder.accountID, .mailbox(id: folder.id), limit: limit).list) ?? []
	}
}

extension MailStore {
	/// How Sam refers to someone in a sentence: a person's first name at a personal address, the
	/// whole name at a company ("Tax Expert"), or the company from the address ("Youi") when there is
	/// no name or the address is a no-reply one.
	nonisolated static func who(name: String, email: String) -> String {
		let lower = email.lowercased()
		let domain = lower.split(separator: "@").last.map(String.init) ?? ""
		let local = lower.split(separator: "@").first.map(String.init) ?? ""
		let robot = ["noreply", "no-reply", "donotreply", "do-not-reply", "notifications", "info", "support", "hello", "team"].contains(where: { local.contains($0) })
		let trimmed = name.trimmingCharacters(in: .whitespaces)
		if !trimmed.isEmpty && !trimmed.contains("@") && !robot {
			return isSharedDomain(domain) ? firstName(of: trimmed) : trimmed
		}
		// The organisation, from the address: "mail.youi.com.au" → "Youi".
		let parts = domain.split(separator: ".").map(String.init)
		let skip: Set<String> = ["com", "net", "org", "au", "co", "uk", "io", "gov", "edu", "mail", "email", "e", "info", "news"]
		if let org = parts.first(where: { !skip.contains($0) }), !isSharedDomain(domain) {
			return org.prefix(1).uppercased() + org.dropFirst()
		}
		return trimmed.isEmpty ? email : trimmed
	}
}

extension MessageSummary {
	/// A summary standing in for a tray record, enough for the filing history (sender and id).
	static func stand(in r: ThreadRecord) -> MessageSummary {
		MessageSummary(id: r.messageID, threadId: r.threadID ?? "", mailboxId: "", fromName: r.fromName, fromEmail: r.fromEmail,
					   toDisplay: "", subject: r.subject, preview: r.preview, receivedAt: Int64(r.receivedAt.timeIntervalSince1970),
					   seen: true, flagged: false, hasAttachment: false)
	}
}
