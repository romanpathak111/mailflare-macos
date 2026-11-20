import SwiftUI
import MailflareCore

/// The Desk: the secretary's sort of new mail, waiting for the user's yes, the four trays, and
/// heads-ups about what's coming. Nothing moves until the user confirms it.
struct DeskView: View {
	@Environment(MailStore.self) private var store
	private var automation: Automation { Automation.shared }
	private var statuses: StatusStore { store.statuses }

	private static let dateLine: DateFormatter = {
		let f = DateFormatter()
		f.locale = Locale(identifier: "en_AU")
		f.dateFormat = "EEEE, d MMMM"
		return f
	}()

	var body: some View {
		let proposals = automation.statusSuggestions
		ScrollView {
			VStack(alignment: .leading, spacing: 22) {
				header(count: proposals.count)
				if let lesson = Notebook.shared.pending { LessonCard(lesson: lesson) }
				if proposals.isEmpty && automation.ruleSuggestions.isEmpty {
					caughtUp
				} else {
					ForEach(ThreadStatus.allCases) { status in
						let items = proposals.filter { automation.status(of: $0) == status }
						let rules = status == .longTerm ? automation.ruleSuggestions : []
						if !items.isEmpty || !rules.isEmpty { proposalSection(status, items: items, rules: rules) }
					}
				}
				trays
				headsUps
				needsYouList
			}
			.frame(maxWidth: 1040, alignment: .leading)
			.padding(.horizontal, 48).padding(.top, 44).padding(.bottom, 40)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.background(Folio.card)
		.task { automation.run(store) }
	}

	// MARK: Header

	private var greeting: String {
		let hour = Calendar.current.component(.hour, from: .now)
		let part = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
		guard let account = store.account else { return part }
		let name = firstName(of: store.accountName(account))
		return name.isEmpty || name.contains("@") ? part : "\(part), \(name)"
	}

	private func header(count: Int) -> some View {
		HStack(alignment: .bottom, spacing: 16) {
			VStack(alignment: .leading, spacing: 8) {
				Text(Self.dateLine.string(from: .now)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Folio.meta)
				Text(greeting).font(.system(size: 34, weight: .bold)).tracking(-1.1).foregroundStyle(Folio.ink)
				Text(subline(count: count)).font(.system(size: 15)).foregroundStyle(Folio.body).fixedSize(horizontal: false, vertical: true)
			}
			Spacer(minLength: 12)
			if automation.isSuggestingStatuses { ProgressView().controlSize(.small) }
			if count > 0 {
				Button("Looks right, sort all \(count)") { withAnimation(.snappy(duration: 0.25)) { automation.acceptAllStatuses(store: store) } }
					.buttonStyle(FolioFilledButtonStyle())
					.help("Confirms every suggestion below as it stands, with your changes")
			} else {
				Button("Sort new mail") { automation.run(store, force: true) }
					.buttonStyle(FolioOutlineButtonStyle(height: 40))
					.disabled(automation.isSuggestingStatuses)
			}
		}
	}

	private func subline(count: Int) -> String {
		let name = SecretarySettings.name
		if count > 0 {
			return "\(count) email\(count == 1 ? "" : "s") to sort. \(name) has pencilled each one in. Nothing moves until you say."
		}
		if automation.isSuggestingStatuses { return "\(name) is reading the new mail…" }
		return StatusAssistant.brief(needsReply: statuses.records(with: .needsReply), waiting: statuses.records(with: .waiting),
									 archivable: statuses.count(.canArchive), longTerm: statuses.count(.longTerm))
	}

	private var caughtUp: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Nothing new to sort").font(.system(size: 15, weight: .semibold)).foregroundStyle(Folio.ink)
			Text(SecretarySettings.sortMode == .onRequest
				 ? "\(SecretarySettings.name) sorts only when you ask. Press Sort new mail."
				 : "New mail is sorted as it comes, by your choice in Settings › Secretary.")
				.font(.system(size: 14)).foregroundStyle(Folio.body)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(18)
		.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Folio.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
	}

	// MARK: Proposals

	private func proposalSection(_ status: ThreadStatus, items: [StatusSuggestion], rules: [RuleSuggestion]) -> some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack {
				Text("\(status.title) · \(items.count)").font(.system(size: 14, weight: .semibold)).foregroundStyle(status.ink)
				Spacer()
				Text(Self.hint(status)).font(.system(size: 13)).foregroundStyle(Folio.body)
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
		case .longTerm: "Worth keeping; confirming files it"
		case .canArchive: "Nothing asked of you; confirming archives it"
		}
	}

	// MARK: Trays

	private var trays: some View {
		HStack(spacing: 12) {
			ForEach(ThreadStatus.allCases) { status in
				Button { store.openStatusList(status) } label: {
					VStack(alignment: .leading, spacing: 10) {
						HStack(spacing: 8) {
							StatusDot(status: status)
							Text(status.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
						}
						.foregroundStyle(status.ink)
						Text("\(statuses.count(status))").font(.system(size: 30, weight: .bold)).tracking(-1).foregroundStyle(Folio.ink)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.horizontal, 18).padding(.vertical, 14)
					.background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(status.tileFill))
					.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(status.tileStroke, lineWidth: 1))
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				.help("Open the \(status.title) tray")
			}
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
		return Array(items.prefix(SecretarySettings.headsUp == .proactive ? 6 : 3))
	}

	@ViewBuilder
	private var headsUps: some View {
		let items = headsUpItems
		if !items.isEmpty {
			VStack(alignment: .leading, spacing: 10) {
				Text("Heads-up").font(.system(size: 18, weight: .bold)).foregroundStyle(Folio.ink)
				ForEach(items, id: \.record.id) { item in
					HStack(spacing: 14) {
						HIcon(.sparkles, size: 13).foregroundStyle(Folio.onDark)
							.frame(width: 28, height: 28)
							.background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Folio.dark))
						Text(item.text).font(.system(size: 14)).foregroundStyle(Folio.body).lineLimit(2)
						Spacer(minLength: 8)
						Button("Open") { store.open(item.record) }
							.buttonStyle(FolioOutlineButtonStyle(ink: Folio.selectionInk, stroke: Folio.accentStroke, height: 32))
					}
					.padding(.horizontal, 14).padding(.vertical, 10)
					.overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Folio.line, lineWidth: 1))
				}
			}
		}
	}

	// MARK: Needs you

	@ViewBuilder
	private var needsYouList: some View {
		let records = statuses.records(with: .needsReply)
		if !records.isEmpty {
			VStack(alignment: .leading, spacing: 0) {
				Text("Needs you").font(.system(size: 18, weight: .bold)).foregroundStyle(Folio.ink).padding(.bottom, 10)
				ForEach(records) { record in
					Rectangle().fill(Folio.line).frame(height: 1)
					DeskRecordRow(record: record)
				}
				Rectangle().fill(Folio.line).frame(height: 1)
			}
		}
	}
}

/// One email Sam has pencilled in: who, what, the proposed tray (changeable), confirm and dismiss.
private struct ProposalRow: View {
	@Environment(MailStore.self) private var store
	let item: StatusSuggestion
	private var automation: Automation { Automation.shared }

	var body: some View {
		let status = automation.status(of: item)
		let folder = automation.folder(of: item)
		let changed = automation.statusChoices[item.id] != nil || automation.folderChoices[item.id] != nil
		HStack(spacing: 14) {
			InitialsAvatar(name: item.summary.senderDisplay, fill: status.avatarFill, ink: status.ink, size: 34)
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 6) {
					Text(item.summary.senderDisplay).font(.system(size: 14, weight: .semibold)).foregroundStyle(Folio.ink).lineLimit(1)
					Text("· " + (item.summary.subject.isEmpty ? "(No Subject)" : item.summary.subject))
						.font(.system(size: 14)).foregroundStyle(Folio.meta).lineLimit(1)
				}
				Text(item.suggestion.ask ?? PreviewText.plain(item.summary.preview))
					.font(.system(size: 13)).foregroundStyle(Folio.body).lineLimit(1)
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
				let folders = store.customFolders(of: item.accountID)
				if !folders.isEmpty {
					Divider()
					ForEach(folders, id: \.id) { box in
						Button { automation.chooseFolder(box.id, name: box.name, for: item) } label: {
							if folder?.id == box.id { Label("To file: \(box.name)", systemImage: "checkmark") } else { Text("To file: \(box.name)") }
						}
					}
				}
			} label: {
				HStack(spacing: 5) {
					Text(folder.map { "To file: \($0.name)" } ?? status.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
					Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
				}
				.foregroundStyle(status.ink)
				.padding(.horizontal, 10).frame(height: 30)
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
			Button { withAnimation(.snappy(duration: 0.2)) { automation.dismiss(item) } } label: {
				HIcon(.close, size: 12).foregroundStyle(Folio.meta).frame(width: 24, height: 30)
			}
			.buttonStyle(.plain).help("Leave it unsorted")
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

/// A Needs you conversation on the Desk: who, what kind of action, how long, and Open.
private struct DeskRecordRow: View {
	@Environment(MailStore.self) private var store
	let record: ThreadRecord
	@State private var hovering = false

	var body: some View {
		HStack(spacing: 14) {
			InitialsAvatar(name: record.senderDisplay, fill: ThreadStatus.needsReply.avatarFill, ink: ThreadStatus.needsReply.ink, size: 34)
			VStack(alignment: .leading, spacing: 2) {
				Text(record.subject.isEmpty ? "(No Subject)" : record.subject).font(.system(size: 14, weight: .semibold)).foregroundStyle(Folio.ink).lineLimit(1)
				Text(record.ask ?? record.senderDisplay).font(.system(size: 13)).foregroundStyle(Folio.body).lineLimit(1)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			Text((record.kind ?? .reply).title).font(.system(size: 12, weight: .semibold)).foregroundStyle(ThreadStatus.needsReply.ink)
				.padding(.horizontal, 8).padding(.vertical, 3)
				.background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ThreadStatus.needsReply.tileFill))
			Text(record.age()).font(.system(size: 13, weight: record.isDueToday ? .bold : .regular))
				.foregroundStyle(record.isDueToday ? ThreadStatus.needsReply.ink : Folio.meta)
				.frame(width: 90, alignment: .trailing)
		}
		.padding(.vertical, 12).padding(.horizontal, 6)
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
