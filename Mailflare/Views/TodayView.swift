import SwiftUI

/// The home screen: what needs the user's reply, and who is waiting on whom, like a personal
/// assistant's morning note. It opens first and reads from the statuses given to conversations.
struct TodayView: View {
	@Environment(MailStore.self) private var store
	@AppStorage(AssistantSettings.todayBriefKey) private var showsAssistant = true
	@AppStorage(AssistantSettings.draftRepliesKey) private var draftsReplies = true

	private var statuses: StatusStore { store.statuses }

	var body: some View {
		let needsReply = statuses.records(with: .needsReply)
		let waiting = statuses.records(with: .waiting)
		let archivable = statuses.count(.canArchive)
		ScrollView {
			VStack(alignment: .leading, spacing: 28) {
				header(needsReply: needsReply, waiting: waiting, archivable: archivable)
				tiles
				if showsAssistant { assistantCard(needsReply: needsReply) }
				if needsReply.isEmpty && waiting.isEmpty {
					emptyNote
				} else {
					if !needsReply.isEmpty {
						section("Needs your reply", status: .needsReply, records: needsReply)
					}
					if !waiting.isEmpty {
						section("Waiting on others", status: .waiting, records: waiting)
					}
				}
			}
			.frame(maxWidth: 820, alignment: .leading)
			.padding(.horizontal, 40).padding(.vertical, 36)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.background(AppTheme.background)
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
		VStack(alignment: .leading, spacing: 8) {
			Text(Date.now.formatted(Date.FormatStyle().weekday(.wide).day().month(.wide)))
				.font(.system(size: 30, weight: .bold)).tracking(-0.6)
			Text("\(greeting). " + StatusAssistant.brief(needsReply: needsReply, waiting: waiting, archivable: archivable, longTerm: statuses.count(.longTerm)))
				.font(.system(size: 15)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
		}
	}

	// MARK: Snapshot

	/// The four statuses and how many conversations each holds; each opens its column on the board.
	private var tiles: some View {
		HStack(spacing: 12) {
			ForEach(ThreadStatus.allCases) { status in
				Button { store.openScreen(.board, status: status) } label: {
					VStack(alignment: .leading, spacing: 12) {
						HStack(spacing: 7) {
							StatusDot(status: status)
							Text(status.title).font(Typography.notice.weight(.semibold)).lineLimit(1)
						}
						.foregroundStyle(status.ink)
						Text("\(statuses.count(status))").font(.system(size: 32, weight: .bold)).tracking(-0.6)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.horizontal, 16).padding(.vertical, 14)
					.background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(status.tint))
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				.help("Open \(status.title) on the board")
			}
		}
	}

	// MARK: Assistant

	/// What the assistant can do now: draft the replies, or sort what has no status yet.
	private func assistantCard(needsReply: [ThreadRecord]) -> some View {
		let connected = store.ai.isConfigured
		return HStack(spacing: 14) {
			HIcon(.sparkles, size: 18)
				.foregroundStyle(AppTheme.prominentPillText)
				.frame(width: 38, height: 38)
				.background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(AppTheme.prominentPillFill))
			VStack(alignment: .leading, spacing: 2) {
				Text(connected ? "Assistant" : "Connect an assistant").font(Typography.bodySemibold)
				Text(cardText(connected: connected, needsReply: needsReply.count))
					.font(Typography.notice).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
			}
			Spacer(minLength: 8)
			if store.isSortingStatuses { ProgressView().controlSize(.small) }
			Button("Sort unsorted mail") { store.sortUnsortedMail() }
				.buttonStyle(.pill).disabled(store.isSortingStatuses)
			if connected {
				Button("Draft replies") {
					store.chatOpen = true
					store.chat.send(StatusAssistant.draftRepliesPrompt(for: needsReply), store: store)
				}
				.buttonStyle(AccentPillStyle()).disabled(needsReply.isEmpty || !draftsReplies)
			} else {
				Button("Connect") { store.settingsPage = .assistant }
					.buttonStyle(AccentPillStyle())
			}
		}
		.padding(.horizontal, 18).padding(.vertical, 14)
		.background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.composerContextFill))
	}

	private func cardText(connected: Bool, needsReply: Int) -> String {
		if !connected { return "Connect Claude or Codex to draft replies and sort new mail. Until then, simple rules sort it." }
		if needsReply == 0 { return "Nothing waits for a reply. Sort new mail and I will tell you what needs you." }
		return "I can draft a reply to \(needsReply == 1 ? "the conversation" : "each of the \(needsReply) conversations") that needs one. Nothing is sent until you press Send."
	}

	// MARK: Lists

	private func section(_ title: String, status: ThreadStatus, records: [ThreadRecord]) -> some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack(alignment: .firstTextBaseline) {
				Text(title).font(.system(size: 18, weight: .bold)).tracking(-0.3)
				Spacer()
				Button("Open board") { store.openScreen(.board, status: status) }
					.buttonStyle(.light).font(Typography.notice.weight(.semibold)).foregroundStyle(Color.accentColor)
			}
			.padding(.bottom, 10)
			ForEach(records) { record in
				Rectangle().fill(AppTheme.cardStroke).frame(height: 1)
				TodayRow(record: record, status: status)
			}
			Rectangle().fill(AppTheme.cardStroke).frame(height: 1)
		}
	}

	private var emptyNote: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Nothing is sorted yet").font(Typography.bodySemibold)
			Text("Open a message and choose a status above it, or press Sort unsorted mail. Conversations that need you will show up here.")
				.font(Typography.notice).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(18)
		.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AppTheme.cardStroke, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
	}
}

/// One conversation on Today: who, what they want, how long it has been, and the button for it.
private struct TodayRow: View {
	@Environment(MailStore.self) private var store
	let record: ThreadRecord
	let status: ThreadStatus
	@State private var isHovering = false

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
		HStack(spacing: 14) {
			SenderAvatar(email: record.fromEmail, name: record.senderDisplay, size: 36)
			VStack(alignment: .leading, spacing: 2) {
				Text(record.subject.isEmpty ? "(No Subject)" : record.subject).font(Typography.bodySemibold).lineLimit(1)
				Text(record.senderDisplay).font(Typography.notice).foregroundStyle(.secondary).lineLimit(1)
			}
			.frame(minWidth: 150, maxWidth: 260, alignment: .leading)
			Text(detail).font(Typography.body).foregroundStyle(.primary.opacity(0.85)).lineLimit(2)
				.frame(maxWidth: .infinity, alignment: .leading)
			Text(record.age())
				.font(isDue ? Typography.notice.weight(.bold) : Typography.notice)
				.foregroundStyle(isDue ? status.ink : Color.secondary)
				.frame(width: 80, alignment: .trailing)
			Button(status == .waiting ? (waitedLong ? "Follow up" : "Nudge") : "Reply") { store.reply(to: record) }
				.buttonStyle(RowActionStyle(status: status, filled: isDue))
				.frame(width: 84)
		}
		.padding(.vertical, 12)
		.padding(.horizontal, 6)
		.background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isHovering ? AppTheme.rowHighlight : .clear))
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

/// The button at the end of a row, in its status's colour; filled when the row is due today.
private struct RowActionStyle: ButtonStyle {
	var status: ThreadStatus
	var filled: Bool

	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.system(size: 13, weight: .semibold))
			.foregroundStyle(filled ? Color.white : status.ink)
			.frame(maxWidth: .infinity)
			.padding(.vertical, 6)
			.background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(filled ? Color.accentColor : status.tint))
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
