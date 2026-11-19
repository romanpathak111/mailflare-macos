import SwiftUI

/// The home screen: what needs the user's reply, and who is waiting on whom, like a personal
/// assistant's morning note. It opens first and reads from the statuses given to conversations.
struct TodayView: View {
	@Environment(MailStore.self) private var store
	@AppStorage(AssistantSettings.todayBriefKey) private var showsAssistant = true
	@AppStorage(AssistantSettings.draftRepliesKey) private var draftsReplies = true

	private var statuses: StatusStore { store.statuses }

	/// "Thursday, 19 November".
	private static let dateLine: DateFormatter = {
		let f = DateFormatter()
		f.locale = Locale(identifier: "en_AU")
		f.dateFormat = "EEEE, d MMMM"
		return f
	}()

	var body: some View {
		let needsReply = statuses.records(with: .needsReply)
		let waiting = statuses.records(with: .waiting)
		let archivable = statuses.count(.canArchive)
		ScrollView {
			VStack(alignment: .leading, spacing: 32) {
				header(needsReply: needsReply, waiting: waiting, archivable: archivable)
				tiles
				if showsAssistant { assistantCard(needsReply: needsReply) }
				if needsReply.isEmpty && waiting.isEmpty {
					emptyNote(sorted: !statuses.records.isEmpty)
				} else {
					if !needsReply.isEmpty {
						section("Needs your reply", status: .needsReply, records: needsReply, showsBoardLink: true)
					}
					if !waiting.isEmpty {
						section("Waiting on others", status: .waiting, records: waiting, showsBoardLink: false)
					}
				}
			}
			.frame(maxWidth: 1040, alignment: .leading)
			.padding(.horizontal, 56).padding(.top, 56).padding(.bottom, 40)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.background(Folio.card)
		.task { Automation.shared.run(store) }
	}

	// MARK: Header

	private var greeting: String {
		let hour = Calendar.current.component(.hour, from: .now)
		let part = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
		guard let account = store.account else { return part }
		let name = store.accountName(account).split(separator: " ").first.map(String.init) ?? ""
		return name.isEmpty || name.contains("@") ? part : "\(part), \(name)"
	}

	private func header(needsReply: [ThreadRecord], waiting: [ThreadRecord], archivable: Int) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			// "Thursday, 19 November", as the mockup writes the date.
			Text(Self.dateLine.string(from: .now))
				.font(.system(size: 40, weight: .bold)).tracking(-1.4).foregroundStyle(Folio.ink)
			Text("\(greeting). " + StatusAssistant.brief(needsReply: needsReply, waiting: waiting, archivable: archivable, longTerm: statuses.count(.longTerm)))
				.font(.system(size: 17)).lineSpacing(3).foregroundStyle(Folio.body).fixedSize(horizontal: false, vertical: true)
		}
	}

	// MARK: Snapshot

	/// The four statuses and how many conversations each holds; each opens its list of mail.
	private var tiles: some View {
		HStack(spacing: 14) {
			ForEach(ThreadStatus.allCases) { status in
				Button { store.openStatusList(status) } label: {
					VStack(alignment: .leading, spacing: 14) {
						HStack(spacing: 8) {
							StatusDot(status: status)
							Text(status.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
						}
						.foregroundStyle(status.ink)
						Text("\(statuses.count(status))").font(.system(size: 36, weight: .bold)).tracking(-1.1).foregroundStyle(Folio.ink)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.horizontal, 20).padding(.vertical, 18)
					.background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(status.tileFill))
					.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(status.tileStroke, lineWidth: 1))
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				.help("Show the mail marked \(status.title)")
			}
		}
	}

	// MARK: Assistant

	/// The assistant's brief, with the one thing it can do next: draft the replies, or sort new mail.
	private func assistantCard(needsReply: [ThreadRecord]) -> some View {
		let connected = store.ai.isConfigured
		return HStack(spacing: 18) {
			HIcon(.sparkles, size: 18)
				.foregroundStyle(Folio.onDark)
				.frame(width: 40, height: 40)
				.background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Folio.dark))
			VStack(alignment: .leading, spacing: 3) {
				Text(connected ? "Assistant brief" : "Connect an assistant").font(.system(size: 15, weight: .semibold)).foregroundStyle(Folio.ink)
				Text(cardText(connected: connected, needsReply: needsReply.count))
					.font(.system(size: 14)).lineSpacing(2).foregroundStyle(Folio.body).fixedSize(horizontal: false, vertical: true)
				SuggestionsLine().padding(.top, 6)
			}
			Spacer(minLength: 8)
			if store.isSortingStatuses { ProgressView().controlSize(.small) }
			if !connected {
				Button("Connect") { store.settingsPage = .assistant }
					.buttonStyle(FolioFilledButtonStyle())
			} else if needsReply.isEmpty || !draftsReplies {
				Button("Sort unsorted mail") { store.sortUnsortedMail() }
					.buttonStyle(FolioFilledButtonStyle()).disabled(store.isSortingStatuses)
			} else {
				Button("Review drafts") {
					store.chatOpen = true
					store.chat.send(StatusAssistant.draftRepliesPrompt(for: needsReply), store: store)
				}
				.buttonStyle(FolioFilledButtonStyle())
				.help("Draft a reply to each conversation that needs one, for you to review")
			}
		}
		.padding(.horizontal, 20).padding(.vertical, 18)
		.background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Folio.soft))
		.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Folio.line, lineWidth: 1))
	}

	private func cardText(connected: Bool, needsReply: Int) -> String {
		if !connected { return "Connect Claude or Codex to draft replies and sort new mail. Until then, simple rules sort it." }
		if needsReply == 0 { return "Nothing waits for a reply. Sort new mail and I will tell you what needs you." }
		return "I can draft a reply to \(needsReply == 1 ? "the conversation" : "each of the \(needsReply) conversations") that needs one. Nothing is sent until you press Send."
	}

	// MARK: Lists

	private func section(_ title: String, status: ThreadStatus, records: [ThreadRecord], showsBoardLink: Bool) -> some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack(alignment: .firstTextBaseline) {
				Text(title).font(.system(size: 20, weight: .bold)).tracking(-0.4).foregroundStyle(Folio.ink)
				Spacer()
				if showsBoardLink {
					Button("Open board") { store.openScreen(.board) }
						.buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Folio.selectionInk)
				}
			}
			.padding(.bottom, 12)
			GeometryReader { proxy in
				let columns = TodayRow.Columns(width: proxy.size.width)
				VStack(spacing: 0) {
					ForEach(records) { record in
						Rectangle().fill(Folio.line).frame(height: 1)
						TodayRow(record: record, status: status, columns: columns)
					}
					Rectangle().fill(Folio.line).frame(height: 1)
				}
			}
			.frame(height: CGFloat(records.count) * 64 + CGFloat(records.count + 1))
		}
	}

	private func emptyNote(sorted: Bool) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(sorted ? "You're caught up" : "Nothing is sorted yet").font(.system(size: 15, weight: .semibold)).foregroundStyle(Folio.ink)
			Text(sorted ? "Nothing needs your reply and nobody is holding you up. The Status board has the rest."
				 : "Open a message and choose a status above it, or press Sort unsorted mail. Conversations that need you will show up here.")
				.font(.system(size: 14)).foregroundStyle(Folio.body).fixedSize(horizontal: false, vertical: true)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(20)
		.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Folio.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
	}
}

/// One conversation on Today: who, what they want, how long it has been, and the button for it.
private struct TodayRow: View {
	@Environment(MailStore.self) private var store
	let record: ThreadRecord
	let status: ThreadStatus
	let columns: Columns
	@State private var isHovering = false

	/// The mockup's grid: 36px avatar, subject 1.1fr, detail 1.6fr, 110px age, 84px button, 16px gaps.
	struct Columns {
		var subject: CGFloat
		var detail: CGFloat
		init(width: CGFloat) {
			let flexible = max(160, width - 36 - 110 - 84 - 16 * 4)
			subject = flexible * 1.1 / 2.7
			detail = flexible * 1.6 / 2.7
		}
	}

	private var detail: String {
		if let ask = record.ask, !ask.isEmpty { return ask }
		if status == .waiting {
			let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: record.statusAt), to: Calendar.current.startOfDay(for: .now)).day ?? 0
			return days >= 1 ? "Last sent \(record.statusAt.formatted(.dateTime.weekday(.wide))), no reply yet" : "Sent today"
		}
		return record.preview
	}

	private var isDue: Bool { record.age() == "Due today" }

	var body: some View {
		HStack(spacing: 16) {
			InitialsAvatar(name: record.senderDisplay, fill: status.avatarFill, ink: status.ink, size: 36)
			VStack(alignment: .leading, spacing: 2) {
				Text(record.subject.isEmpty ? "(No Subject)" : record.subject).font(.system(size: 15, weight: .semibold)).foregroundStyle(Folio.ink).lineLimit(1)
				Text(record.senderDisplay).font(.system(size: 13)).foregroundStyle(Folio.meta).lineLimit(1)
			}
			.frame(width: columns.subject, alignment: .leading)
			Text(detail).font(.system(size: 14)).foregroundStyle(Folio.body).lineLimit(1)
				.frame(width: columns.detail, alignment: .leading)
			Text(record.age())
				.font(.system(size: 13, weight: isDue ? .bold : .regular))
				.foregroundStyle(isDue ? status.ink : Folio.meta)
				.frame(width: 110, alignment: .trailing)
			Button(status == .waiting ? (waitedLong ? "Follow up" : "Nudge") : "Reply") { store.reply(to: record) }
				.buttonStyle(RowActionStyle(status: status, filled: isDue, strong: status != .waiting || waitedLong))
				.frame(width: 84)
		}
		.frame(height: 64)
		.background(Rectangle().fill(isHovering ? AppTheme.rowHighlight : .clear))
		.contentShape(Rectangle())
		.onHover { isHovering = $0 }
		.onTapGesture { store.open(record) }
		.contextMenu {
			ForEach(ThreadStatus.allCases.filter { $0 != status }) { other in
				Button("Move to \(other.title)") { store.setStatus(other, for: record) }
			}
			Divider()
			Button("Clear Status") { store.statuses.remove(account: record.accountID, message: record.messageID) }
		}
	}

	private var waitedLong: Bool {
		(Calendar.current.dateComponents([.day], from: record.statusAt, to: .now).day ?? 0) >= 2
	}
}

/// The button at the end of a row: outlined in its status's colour, filled blue when due today,
/// and plain grey for a gentle nudge.
private struct RowActionStyle: ButtonStyle {
	var status: ThreadStatus
	var filled: Bool
	var strong: Bool

	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.system(size: 13, weight: .semibold))
			.foregroundStyle(filled ? Color.white : (strong ? status.ink : Folio.body))
			.frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
			.background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(filled ? Folio.accent : Folio.card))
			.overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(filled ? .clear : (strong ? status.actionStroke : Folio.line), lineWidth: 1))
			.contentShape(Rectangle())
			.opacity(configuration.isPressed ? 0.7 : 1)
	}
}

/// The blue call to action.
struct AccentPillStyle: ButtonStyle {
	@Environment(\.isEnabled) private var isEnabled

	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.system(size: 13, weight: .semibold))
			.foregroundStyle(Color.white)
			.padding(.horizontal, 14).padding(.vertical, 7)
			.background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor))
			.opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.7 : 1)
	}
}
