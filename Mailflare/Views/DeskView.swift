import SwiftUI
import MailflareCore

/// The Desk, as the mockup lays it out: what Sam has pencilled in for Needs you, one row each;
/// Waiting, To file and Can archive as three tiles that say what's in them and open to the rows;
/// then heads-ups. Nothing moves until the user confirms it.
struct DeskView: View {
	@Environment(MailStore.self) private var store
	private var automation: Automation { Automation.shared }
	private var statuses: StatusStore { store.statuses }
	/// The tile opened to its rows, if any.
	@State private var open: ThreadStatus?
	@State private var notNow: Set<String> = []

	private static let tileStatuses: [ThreadStatus] = [.waiting, .longTerm, .canArchive]

	var body: some View {
		let proposals = automation.statusSuggestions
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				header(count: proposals.count)
				if let lesson = Notebook.shared.pending { LessonCard(lesson: lesson) }
				if proposals.isEmpty {
					standing
					if !automation.ruleSuggestions.isEmpty { proposalCard(.longTerm, items: [], rules: automation.ruleSuggestions) }
				} else {
					let needs = proposals.filter { automation.status(of: $0) == .needsReply }
					if !needs.isEmpty { proposalCard(.needsReply, items: needs, rules: []) }
					proposalTiles(proposals)
					if let open {
						let items = proposals.filter { automation.status(of: $0) == open }
						let rules = open == .longTerm ? automation.ruleSuggestions : []
						if !items.isEmpty || !rules.isEmpty { proposalCard(open, items: items, rules: rules) }
					}
				}
				headsUps
			}
			.frame(maxWidth: 980, alignment: .leading)
			.padding(.horizontal, 36).padding(.top, 40).padding(.bottom, 40)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.background(Folio.card)
		.task { automation.run(store) }
	}

	// MARK: Header

	private var greeting: String {
		let hour = Calendar.current.component(.hour, from: .now)
		let part = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
		guard let account = store.account ?? store.accountList.first else { return part }
		let name = firstName(of: store.accountName(account))
		return name.isEmpty || name.contains("@") ? part : "\(part), \(name)"
	}

	private func header(count: Int) -> some View {
		HStack(alignment: .center, spacing: 16) {
			VStack(alignment: .leading, spacing: 6) {
				Text(greeting).font(.system(size: 28, weight: .bold)).tracking(-0.8).foregroundStyle(Folio.ink)
				Text(subline(count: count)).font(.system(size: 15)).foregroundStyle(Folio.body).fixedSize(horizontal: false, vertical: true)
			}
			Spacer(minLength: 12)
			if automation.isSuggestingStatuses { ProgressView().controlSize(.small) }
			if count > 0 {
				Button("Looks right, sort all \(count)") { withAnimation(.snappy(duration: 0.25)) { automation.acceptAllStatuses(store: store) } }
					.buttonStyle(DeskPrimaryButtonStyle())
					.help("Confirms every suggestion as it stands, with your changes")
			} else {
				Button("Sort new mail") { automation.run(store, force: true) }
					.buttonStyle(FolioOutlineButtonStyle(height: 40))
					.disabled(automation.isSuggestingStatuses)
			}
		}
	}

	private func subline(count: Int) -> String {
		if count > 0 {
			return "\(count) email\(count == 1 ? "" : "s") came in. I've pencilled each one in. Nothing moves until you say."
		}
		if automation.isSuggestingStatuses { return "Reading the new mail…" }
		return StatusAssistant.brief(needsReply: statuses.records(with: .needsReply), waiting: statuses.records(with: .waiting),
									 archivable: statuses.count(.canArchive), longTerm: statuses.count(.longTerm))
	}

	// MARK: Pencilled in

	private func proposalCard(_ status: ThreadStatus, items: [StatusSuggestion], rules: [RuleSuggestion]) -> some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack {
				Text("\(status.title) · \(items.count)").font(.system(size: 14, weight: .semibold)).foregroundStyle(status.ink)
				Spacer()
				Text(Self.hint(status)).font(.system(size: 13)).foregroundStyle(Folio.body)
				if status != .needsReply {
					Button { withAnimation(.snappy(duration: 0.2)) { open = nil } } label: {
						HIcon(.close, size: 11).foregroundStyle(Folio.meta).frame(width: 22, height: 22)
					}
					.buttonStyle(.plain).help("Close")
				}
			}
			.padding(.horizontal, 16).padding(.vertical, 11)
			.background(status.tileFill)
			ForEach(items) { item in
				Rectangle().fill(Folio.softLine).frame(height: 1)
				ProposalRow(item: item)
			}
			ForEach(rules) { rule in
				Rectangle().fill(Folio.softLine).frame(height: 1)
				RuleSuggestionRow(suggestion: rule).padding(.horizontal, 16)
			}
		}
		.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(status.tileStroke, lineWidth: 1))
	}

	static func hint(_ status: ThreadStatus) -> String {
		switch status {
		case .needsReply: "Your input, a decision or a signature"
		case .waiting: "You've answered; the ball is with them"
		case .longTerm: "Confirming files each one in its folder"
		case .canArchive: "Nothing asked of you; confirming archives it"
		}
	}

	/// Waiting, To file and Can archive: what's in each, in a sentence or three.
	private func proposalTiles(_ proposals: [StatusSuggestion]) -> some View {
		HStack(alignment: .top, spacing: 12) {
			ForEach(Self.tileStatuses) { status in
				let items = proposals.filter { automation.status(of: $0) == status }
				Button {
					withAnimation(.snappy(duration: 0.2)) { open = open == status || items.isEmpty ? nil : status }
				} label: {
					DeskTile(status: status, title: "\(status.title) · \(items.count)", isOpen: open == status,
							 lines: tileLines(status, items), foot: items.isEmpty ? "Nothing new." : tileFoot(status))
				}
				.buttonStyle(.plain)
				.help(items.isEmpty ? "" : (open == status ? "Hide these" : "Check them one by one"))
			}
		}
	}

	private func tileLines(_ status: ThreadStatus, _ items: [StatusSuggestion]) -> [AttributedString] {
		guard !items.isEmpty else { return [] }
		switch status {
		case .longTerm:
			// "2 from Xero → Finance": grouped by sender and folder.
			var groups: [(who: String, folder: String?, count: Int)] = []
			for item in items {
				let who = item.summary.senderDisplay, folder = automation.folder(of: item)?.name
				if let i = groups.firstIndex(where: { $0.who == who && $0.folder == folder }) { groups[i].count += 1 }
				else { groups.append((who, folder, 1)) }
			}
			var lines = groups.prefix(3).map { g -> AttributedString in
				var line = AttributedString(g.count > 1 ? "\(g.count) from \(g.who)" : g.who)
				if let folder = g.folder {
					line += AttributedString(" → ")
					var f = AttributedString(folder); f.font = .system(size: 13.5, weight: .semibold); line += f
				} else {
					line += AttributedString(" · folder to choose")
				}
				return line
			}
			if groups.count > 3 { lines.append(AttributedString("and \(groups.count - 3) more")) }
			return lines
		case .canArchive:
			var counts: [(String, Int)] = []
			for item in items {
				let who = item.summary.senderDisplay
				if let i = counts.firstIndex(where: { $0.0 == who }) { counts[i].1 += 1 } else { counts.append((who, 1)) }
			}
			let named = counts.prefix(4).map { $0.1 > 1 ? "\($0.1) \($0.0)" : $0.0 }
			let more = counts.count > 4 ? " and \(counts.count - 4) more" : ""
			return [AttributedString(named.joined(separator: ", ") + more + ".")]
		default:
			return items.prefix(2).map { item in
				var who = AttributedString(item.summary.senderDisplay); who.font = .system(size: 13.5, weight: .semibold)
				return who + AttributedString(" " + (item.suggestion.gist ?? item.summary.subject))
			}
		}
	}

	private func tileFoot(_ status: ThreadStatus) -> String {
		switch status {
		case .waiting:
			let day = Calendar.current.date(byAdding: .day, value: SecretarySettings.chaseDays, to: .now) ?? .now
			return "I'll bring it back if they're quiet by \(day.formatted(.dateTime.weekday(.wide)))."
		case .longTerm: return "Folders follow where you've filed before. Change any of them."
		case .canArchive: return "Nothing here asks anything of you."
		case .needsReply: return ""
		}
	}

	// MARK: When everything is sorted

	@ViewBuilder
	private var standing: some View {
		let records = statuses.records(with: .needsReply)
		if !records.isEmpty {
			VStack(alignment: .leading, spacing: 0) {
				HStack {
					Text("Needs you · \(records.count)").font(.system(size: 14, weight: .semibold)).foregroundStyle(ThreadStatus.needsReply.ink)
					Spacer()
					Text(Self.hint(.needsReply)).font(.system(size: 13)).foregroundStyle(Folio.body)
				}
				.padding(.horizontal, 16).padding(.vertical, 11)
				.background(ThreadStatus.needsReply.tileFill)
				ForEach(records.prefix(8)) { record in
					Rectangle().fill(Folio.softLine).frame(height: 1)
					DeskRecordRow(record: record)
				}
				if records.count > 8 {
					Rectangle().fill(Folio.softLine).frame(height: 1)
					Button("See all \(records.count)") { store.openStatusList(.needsReply) }
						.buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(Folio.selectionInk)
						.padding(.horizontal, 16).padding(.vertical, 10)
				}
			}
			.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
			.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ThreadStatus.needsReply.tileStroke, lineWidth: 1))
		}
		HStack(alignment: .top, spacing: 12) {
			ForEach(Self.tileStatuses) { status in
				let records = statuses.records(with: status)
				Button { store.openStatusList(status) } label: {
					DeskTile(status: status, title: "\(status.title) · \(records.count)", isOpen: false,
							 lines: records.prefix(2).map { r in
								 var who = AttributedString(r.senderDisplay); who.font = .system(size: 13.5, weight: .semibold)
								 return who + AttributedString(" " + r.subject)
							 },
							 foot: records.isEmpty ? "Empty." : "Open the tray")
				}
				.buttonStyle(.plain)
			}
		}
		if records.isEmpty && statuses.records.isEmpty {
			Text(SecretarySettings.sortMode == .onRequest
				 ? "\(SecretarySettings.name) sorts only when you ask. Press Sort new mail."
				 : "New mail is sorted as it comes, by your choice in Settings › Secretary.")
				.font(.system(size: 13)).foregroundStyle(Folio.meta)
		}
	}

	// MARK: Heads-ups

	/// Things worth knowing before they become a problem: answers due today, and waits that have
	/// gone on too long. Quiet shows none; Proactive also shows what's due in the next few days.
	private var headsUpItems: [(record: ThreadRecord, text: String)] {
		guard SecretarySettings.headsUp != .quiet else { return [] }
		var items: [(ThreadRecord, String)] = []
		let cal = Calendar.current
		for r in statuses.records(with: .needsReply) {
			if r.isDueToday { items.append((r, "\(r.senderDisplay) needs an answer today: \(r.subject).")) }
			else if SecretarySettings.headsUp == .proactive, let due = r.due, due < cal.date(byAdding: .day, value: 4, to: .now)! {
				items.append((r, "\(r.senderDisplay): \(r.subject) is due \(due.formatted(.dateTime.weekday(.wide)))."))
			}
		}
		for r in statuses.records(with: .waiting) {
			let days = cal.dateComponents([.day], from: r.statusAt, to: .now).day ?? 0
			if days >= SecretarySettings.chaseDays {
				items.append((r, "No answer from \(r.senderDisplay) in \(days) days on \(r.subject). Worth a nudge?"))
			}
		}
		return Array(items.filter { !notNow.contains($0.0.id) }.prefix(SecretarySettings.headsUp == .proactive ? 6 : 3))
	}

	@ViewBuilder
	private var headsUps: some View {
		ForEach(headsUpItems, id: \.record.id) { item in
			HStack(spacing: 14) {
				HIcon(.sparkles, size: 13).foregroundStyle(Folio.onDark)
					.frame(width: 30, height: 30)
					.background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Folio.dark))
				(Text("Heads-up. ").fontWeight(.semibold) + Text(item.text))
					.font(.system(size: 14)).foregroundStyle(Folio.ink).lineLimit(2)
				Spacer(minLength: 8)
				Button("Open") { store.open(item.record) }
					.buttonStyle(FolioOutlineButtonStyle(ink: Folio.selectionInk, stroke: Folio.accentStroke, height: 32))
				Button("Not now") { withAnimation(.snappy(duration: 0.2)) { _ = notNow.insert(item.record.id) } }
					.buttonStyle(FolioOutlineButtonStyle(height: 32))
			}
			.padding(.horizontal, 16).padding(.vertical, 12)
			.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Folio.line, lineWidth: 1))
		}
	}
}

/// One of the three tiles under Needs you.
private struct DeskTile: View {
	let status: ThreadStatus
	let title: String
	let isOpen: Bool
	let lines: [AttributedString]
	let foot: String
	@State private var hovering = false

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(status.ink)
			ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
				Text(line).font(.system(size: 13.5)).foregroundStyle(Folio.ink).lineLimit(2)
			}
			Spacer(minLength: 0)
			Text(foot).font(.system(size: 12.5)).foregroundStyle(Folio.meta).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
		}
		.frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
		.padding(.horizontal, 16).padding(.vertical, 14)
		.background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(status.tileFill.opacity(hovering || isOpen ? 1 : 0.6)))
		.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(isOpen ? status.dot : status.tileStroke, lineWidth: isOpen ? 1.5 : 1))
		.contentShape(Rectangle())
		.onHover { hovering = $0 }
	}
}

/// The mockup's filled blue button.
private struct DeskPrimaryButtonStyle: ButtonStyle {
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
			.padding(.horizontal, 18).frame(height: 40)
			.background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Folio.accent.opacity(configuration.isPressed ? 0.85 : 1)))
	}
}

/// One email Sam has pencilled in: who, what it is, the proposed tray or folder (changeable), and ✓.
private struct ProposalRow: View {
	@Environment(MailStore.self) private var store
	let item: StatusSuggestion
	private var automation: Automation { Automation.shared }

	/// One line on what it is: Sam's gist, what they want, or the cleaned-up preview.
	private var line: String {
		item.suggestion.gist ?? item.suggestion.ask ?? PreviewText.plain(item.summary.preview)
			.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
			.trimmingCharacters(in: .whitespaces)
	}

	var body: some View {
		let status = automation.status(of: item)
		let folder = automation.folder(of: item)
		let changed = automation.statusChoices[item.id] != nil || automation.folderChoices[item.id] != nil
		let reason = automation.folderChoices[item.id] != nil ? "Your choice" : item.suggestion.folderReason
		HStack(spacing: 14) {
			InitialsAvatar(name: item.summary.senderDisplay, fill: status.avatarFill, ink: status.ink, size: 34)
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 6) {
					Text(item.summary.senderDisplay).font(.system(size: 14, weight: .semibold)).foregroundStyle(Folio.ink).lineLimit(1)
					Text("· " + (item.summary.subject.isEmpty ? "(No Subject)" : item.summary.subject))
						.font(.system(size: 14)).foregroundStyle(Folio.meta).lineLimit(1)
				}
				Text(line).font(.system(size: 13)).foregroundStyle(Folio.body).lineLimit(1)
				if status == .longTerm, folder != nil, let reason {
					Text(reason).font(.system(size: 12)).foregroundStyle(status.ink).lineLimit(1)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.contentShape(Rectangle())
			.onTapGesture { store.openMessage(accountID: item.accountID, messageID: item.summary.id) }
			if status == .needsReply, let kind = item.suggestion.kind {
				Text(kind.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(status.ink)
					.padding(.horizontal, 8).padding(.vertical, 3)
					.background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(status.tileFill))
			}
			Menu {
				ForEach(ThreadStatus.allCases) { s in
					Button { automation.choose(s, for: item) } label: {
						if s == status && folder == nil { Label(s.title, systemImage: "checkmark") } else { Text(s.title) }
					}
				}
				let folders = store.libraryFolders(of: item.accountID)
				if !folders.isEmpty {
					Divider()
					if let usualID = item.suggestion.folderID, let usual = folders.first(where: { $0.id == usualID }) {
						Section(item.suggestion.folderReason ?? "Suggested") {
							Button { automation.chooseFolder(usual.id, name: usual.path, for: item) } label: {
								if folder?.id == usual.id { Label("File in \(usual.path)", systemImage: "checkmark") } else { Text("File in \(usual.path)") }
							}
						}
					}
					Menu("File in another folder") {
						ForEach(folders) { f in
							Button { automation.chooseFolder(f.id, name: f.path, for: item) } label: {
								if folder?.id == f.id { Label(f.path, systemImage: "checkmark") } else { Text(f.path) }
							}
						}
					}
				}
				Divider()
				Button("Leave it unsorted") { withAnimation(.snappy(duration: 0.2)) { automation.dismiss(item) } }
			} label: {
				HStack(spacing: 5) {
					Text(folder.map { "→ \($0.name)" } ?? status.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
					Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
				}
				.foregroundStyle(status.ink)
				.padding(.horizontal, 10).frame(height: 30)
				.frame(maxWidth: 220)
				.background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(status.dropFill))
				.overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
					.strokeBorder(changed ? status.dot : status.dropStroke, style: StrokeStyle(lineWidth: 1, dash: changed ? [] : [4, 3])))
			}
			.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
			.help(changed ? "Your choice. Click ✓ to confirm." : "\(SecretarySettings.possessive) suggestion. Change it before confirming.")
			Button { withAnimation(.snappy(duration: 0.2)) { automation.accept(item, store: store) } } label: {
				Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Folio.selectionInk)
					.frame(width: 30, height: 30)
					.background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Folio.card))
					.overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Folio.accentStroke, lineWidth: 1))
			}
			.buttonStyle(.plain)
			.help(Self.confirmHelp(status, folder: folder?.name))
			.accessibilityLabel("Confirm")
		}
		.padding(.horizontal, 16).padding(.vertical, 11)
	}

	static func confirmHelp(_ status: ThreadStatus, folder: String?) -> String {
		switch status {
		case .canArchive: "Confirm: moves it to Archive"
		case .longTerm: folder.map { "Confirm: files it in \($0)" } ?? "Confirm: puts it in the To file tray"
		default: "Confirm: puts it in \(status.title)"
		}
	}
}

/// A Needs you conversation on the Desk: who, what kind of action, how long.
private struct DeskRecordRow: View {
	@Environment(MailStore.self) private var store
	let record: ThreadRecord
	@State private var hovering = false

	var body: some View {
		HStack(spacing: 14) {
			InitialsAvatar(name: record.senderDisplay, fill: ThreadStatus.needsReply.avatarFill, ink: ThreadStatus.needsReply.ink, size: 34)
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 6) {
					Text(record.senderDisplay).font(.system(size: 14, weight: .semibold)).foregroundStyle(Folio.ink).lineLimit(1)
					Text("· " + (record.subject.isEmpty ? "(No Subject)" : record.subject)).font(.system(size: 14)).foregroundStyle(Folio.meta).lineLimit(1)
				}
				if let ask = record.ask { Text(ask).font(.system(size: 13)).foregroundStyle(Folio.body).lineLimit(1) }
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			Text((record.kind ?? .reply).title).font(.system(size: 12, weight: .semibold)).foregroundStyle(ThreadStatus.needsReply.ink)
				.padding(.horizontal, 8).padding(.vertical, 3)
				.background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ThreadStatus.needsReply.tileFill))
			Text(record.age()).font(.system(size: 13, weight: record.isDueToday ? .bold : .regular))
				.foregroundStyle(record.isDueToday ? ThreadStatus.needsReply.ink : Folio.meta)
				.frame(width: 90, alignment: .trailing)
		}
		.padding(.vertical, 11).padding(.horizontal, 16)
		.background(hovering ? AppTheme.rowHighlight : .clear)
		.contentShape(Rectangle())
		.onHover { hovering = $0 }
		.onTapGesture { store.open(record) }
	}
}

/// "Should I do the same from now on?": asked once after a change that looks like a pattern.
struct LessonCard: View {
	let lesson: PendingLesson

	var body: some View {
		HStack(alignment: .top, spacing: 14) {
			HIcon(.sparkles, size: 13).foregroundStyle(Folio.onDark)
				.frame(width: 30, height: 30)
				.background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Folio.dark))
			VStack(alignment: .leading, spacing: 10) {
				Text(lesson.question).font(.system(size: 14.5)).foregroundStyle(Folio.ink).fixedSize(horizontal: false, vertical: true)
				HStack(spacing: 8) {
					Button("Yes, remember") { withAnimation(.snappy(duration: 0.2)) { Notebook.shared.acceptPending() } }
						.buttonStyle(FolioFilledButtonStyle(height: 32))
					Button("Just this once") { withAnimation(.snappy(duration: 0.2)) { Notebook.shared.pending = nil } }
						.buttonStyle(FolioOutlineButtonStyle(height: 32))
				}
			}
			Spacer(minLength: 0)
		}
		.padding(16)
		.background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Folio.card))
		.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Folio.accentStroke, lineWidth: 1))
		.shadow(color: .black.opacity(0.08), radius: 16, y: 6)
	}
}
