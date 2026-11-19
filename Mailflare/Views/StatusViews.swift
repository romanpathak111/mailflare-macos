import SwiftUI
import MailflareCore

/// A status as a small coloured dot.
struct StatusDot: View {
	var status: ThreadStatus
	var size: CGFloat = 8

	var body: some View {
		Circle().fill(status.dot).frame(width: size, height: size)
	}
}

/// A status as a pill: its dot and name on its soft fill.
struct StatusChip: View {
	var status: ThreadStatus
	var short = true

	var body: some View {
		HStack(spacing: 5) {
			StatusDot(status: status, size: 6)
			Text(short ? status.shortTitle : status.title).font(Typography.meta.weight(.semibold)).lineLimit(1)
		}
		.foregroundStyle(status.ink)
		.padding(.horizontal, 8).padding(.vertical, 2)
		.background(Capsule().fill(status.tint))
		.fixedSize()
	}
}

/// One status in a dropdown: its dot, its name, and a check when it is the conversation's status.
struct StatusMenuRow: View {
	var status: ThreadStatus
	var isSelected: Bool
	var verticalPadding: CGFloat = 8
	var font: Font = Typography.body
	var action: () -> Void

	@State private var isHovering = false

	var body: some View {
		Button(action: action) {
			HStack(spacing: 10) {
				StatusDot(status: status, size: 9)
				Text(status.title).font(isSelected ? font.weight(.semibold) : font).lineLimit(1)
					.foregroundStyle(isSelected ? status.ink : Folio.body)
				Spacer(minLength: 8)
				if isSelected { HIcon(.check, size: 14) }
			}
			.foregroundStyle(isSelected ? status.ink : Color.primary)
			.padding(.horizontal, 10).padding(.vertical, verticalPadding)
			.background(RoundedRectangle(cornerRadius: 9, style: .continuous)
				.fill(isSelected ? status.tint : (isHovering ? AppTheme.rowHighlight : .clear)))
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { isHovering = $0 }
	}
}

/// The status of the open message as a button that drops the four statuses, with a check on the
/// current one. Below it, the assistant's suggestion when there is none yet.
struct StatusPicker: View {
	@Environment(MailStore.self) private var store
	let message: MessageSummary
	@State private var isOpen = false
	@AppStorage(AssistantSettings.suggestStatusKey) private var suggestsStatus = true
	@AppStorage(AssistantSettings.draftRepliesKey) private var draftsReplies = true

	private var current: ThreadStatus? { store.status(of: message) }
	private var dueToday: Bool { store.statusRecord(of: message.id)?.isDueToday ?? false }

	/// What the rules make of this message, when it has no status and sits in the inbox.
	private var suggestion: StatusAssistant.Suggestion? {
		guard suggestsStatus, current == nil, store.role(of: message) == "inbox" else { return nil }
		let parts = ViewMessageID.split(message.id)
		if let found = Automation.shared.statusSuggestion(account: parts.account ?? store.account?.id ?? "", message: parts.message) { return found }
		return StatusAssistant.guess(.init(id: message.id, from: message.sender.formatted, subject: message.subject, preview: PreviewText.plain(message.preview)))
	}

	var body: some View {
		HStack(spacing: 10) {
			button
			if let suggestion {
				HStack(spacing: 6) {
					Text("Looks like").font(Typography.notice).foregroundStyle(.secondary)
					StatusChip(status: suggestion.status)
					Button("Accept") { withAnimation(.snappy(duration: 0.2)) { store.setStatus(suggestion.status, for: [message.id], due: suggestion.due) } }
						.buttonStyle(.light).font(Typography.notice.weight(.semibold)).foregroundStyle(Color.accentColor)
				}
				.transition(.opacity)
			}
			Spacer(minLength: 0)
			// A reply for Needs reply mail is suggested in its own card at the end of the message.
		}
		.zIndex(isOpen ? 10 : 0)
		.onChange(of: message.id) { _, _ in isOpen = false }
	}

	private var button: some View {
		Button {
			withAnimation(.snappy(duration: 0.2)) { isOpen.toggle() }
		} label: {
			HStack(spacing: 10) {
				if let current { StatusDot(status: current, size: 9) }
				Text(current?.title ?? "Set status").font(.system(size: 15, weight: .semibold)).lineLimit(1)
				Spacer(minLength: 12)
				HIcon(.chevronDown, size: 13)
			}
			.foregroundStyle(current?.ink ?? Folio.body)
			.padding(.horizontal, 16)
			.frame(width: 230, height: 40)
			.background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(current?.tileFill ?? Folio.chip))
			.overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(current?.actionStroke ?? Folio.line, lineWidth: 1))
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.help("Status of this conversation")
		.overlay(alignment: .topLeading) {
			if isOpen {
				DropdownCard(width: 230, anchor: .topLeading) {
					ForEach(ThreadStatus.allCases) { status in
						StatusMenuRow(status: status, isSelected: status == current) { choose(status) }
					}
					if current == .needsReply {
						DropdownDivider()
						DropdownRow(label: "Due today", icon: .clock, isSelected: dueToday) {
							withAnimation(.snappy(duration: 0.2)) { isOpen = false; store.setDueToday(!dueToday, for: message.id) }
						}
					}
					if current != nil {
						DropdownDivider()
						DropdownRow(label: "Clear status", icon: .cancel) { choose(nil) }
					}
				}
				.offset(y: 46)
			}
		}
		.clickAway(isActive: isOpen) { withAnimation(.snappy(duration: 0.2)) { isOpen = false } }
	}

	private func choose(_ status: ThreadStatus?) {
		withAnimation(.snappy(duration: 0.2)) {
			isOpen = false
			store.setStatus(status, for: message.id)
		}
	}
}

/// The status rows of a message's context menu: one per status, the current one checked.
struct StatusMenuRows: View {
	@Environment(MailStore.self) private var store
	var ids: [String]
	var font: Font
	var verticalPadding: CGFloat
	var choose: (@escaping () -> Void) -> Void

	var body: some View {
		let shared: ThreadStatus? = {
			let all = Set(ids.map { store.status(of: $0) })
			return all.count == 1 ? all.first.flatMap { $0 } : nil
		}()
		ForEach(ThreadStatus.allCases) { status in
			StatusMenuRow(status: status, isSelected: status == shared, verticalPadding: verticalPadding, font: font) {
				choose { store.setStatus(status, for: ids) }
			}
		}
		if ids.contains(where: { store.status(of: $0) != nil }) {
			DropdownRow(label: "Clear Status", icon: .cancel, labelFont: font, verticalPadding: verticalPadding) {
				choose { store.setStatus(nil, for: ids) }
			}
		}
	}
}
