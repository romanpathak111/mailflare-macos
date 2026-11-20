import SwiftUI
import MailflareCore

/// "Where this stands": the secretary's one-paragraph note at the top of a sorted conversation, with
/// a button to draft a reply when one is wanted. Nothing is drafted until the button is pressed.
struct StandingNote: View {
	@Environment(MailStore.self) private var store
	let message: MessageSummary
	@Binding var draftRequested: Bool

	var body: some View {
		if let record = store.statusRecord(of: message.id) {
			HStack(alignment: .top, spacing: 12) {
				HIcon(.sparkles, size: 12)
					.foregroundStyle(Folio.onDark)
					.frame(width: 26, height: 26)
					.background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Folio.dark))
				VStack(alignment: .leading, spacing: 10) {
					(Text("Where this stands: ").fontWeight(.semibold).foregroundColor(Folio.ink) + Text(store.standing(of: record)))
						.font(.system(size: 14)).foregroundStyle(Folio.body).lineSpacing(3)
						.fixedSize(horizontal: false, vertical: true)
						.textSelection(.enabled)
					if record.status == .needsReply, (record.kind ?? .reply) == .reply, store.ai.isConfigured, !draftRequested {
						Button { withAnimation(.snappy(duration: 0.25)) { draftRequested = true } } label: {
							HStack(spacing: 6) { HIcon(.sparkles, size: 11); Text("Draft it for me") }
						}
						.buttonStyle(FolioOutlineButtonStyle(ink: Folio.selectionInk, stroke: Folio.accentStroke, height: 32))
						.help("\(SecretarySettings.name) writes a short reply for you to check. Nothing is sent.")
					}
				}
				Spacer(minLength: 0)
			}
			.padding(14)
			.background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Folio.soft))
			.overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Folio.line, lineWidth: 1))
		}
	}
}

/// The other messages of the open message's conversation, from any folder (your replies in Sent
/// included), each a line that opens to its text. `before` lists the older ones, otherwise the newer.
struct ConversationTrail: View {
	@Environment(MailStore.self) private var store
	let message: MessageSummary
	let before: Bool

	@State private var others: [MessageSummary] = []
	@State private var showAllOlder = false

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			let shown = before && !showAllOlder && others.count > 2 ? Array(others.suffix(2)) : others
			if before && !showAllOlder && others.count > 2 {
				Button { withAnimation(.snappy(duration: 0.2)) { showAllOlder = true } } label: {
					Text("\(others.count - 2) earlier message\(others.count - 2 == 1 ? "" : "s")")
						.font(.system(size: 12)).foregroundStyle(Folio.meta)
						.padding(.horizontal, 14).frame(height: 26)
						.background(Capsule().strokeBorder(Folio.line, lineWidth: 1))
				}
				.buttonStyle(.plain)
				.frame(maxWidth: .infinity)
			}
			ForEach(shown, id: \.id) { m in TrailMessage(summary: m, accountID: account, mine: store.isMine(m, accountID: account)) }
		}
		.task(id: message.id) { load() }
		.onChange(of: store.mailRevision) { _, _ in load() }
	}

	private var account: String { store.ownerOf(message.id).account }

	private func load() {
		let raw = store.ownerOf(message.id).message
		let all = store.conversation(of: message, accountID: account)
		let pivot = message.receivedAt
		others = all.filter { $0.id != raw && $0.id != message.id && (before ? $0.receivedAt <= pivot : $0.receivedAt > pivot) }
	}
}

/// One message of a conversation trail: who, when and a line of it, opening to the full text.
private struct TrailMessage: View {
	@Environment(MailStore.self) private var store
	let summary: MessageSummary
	let accountID: String
	let mine: Bool
	@State private var open = false
	@State private var text: String?

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Button { toggle() } label: {
				HStack(spacing: 10) {
					InitialsAvatar(name: mine ? "You" : summary.senderDisplay, fill: mine ? Folio.dark : Folio.selection,
								   ink: mine ? Folio.onDark : Folio.selectionInk, size: 28)
					VStack(alignment: .leading, spacing: 2) {
						HStack(spacing: 6) {
							Text(mine ? "You" : summary.senderDisplay).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Folio.ink)
							Text(MailStore.when(summary.date)).font(.system(size: 12)).foregroundStyle(Folio.meta)
						}
						if !open {
							Text(PreviewText.plain(summary.preview)).font(.system(size: 13)).foregroundStyle(Folio.body).lineLimit(1)
						}
					}
					Spacer(minLength: 0)
					HIcon(.chevronDown, size: 11).foregroundStyle(Folio.meta).rotationEffect(.degrees(open ? 180 : 0))
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			if open {
				Group {
					if let text { Text(text) } else { Text("Loading…").foregroundStyle(Folio.meta) }
				}
				.font(.system(size: 14)).foregroundStyle(Folio.body).lineSpacing(4)
				.textSelection(.enabled)
				.fixedSize(horizontal: false, vertical: true)
				.padding(.leading, 38)
			}
		}
		.padding(.horizontal, 14).padding(.vertical, 11)
		.background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(mine ? Folio.accentSoft : Folio.card))
		.overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(mine ? Folio.accentStroke : Folio.line, lineWidth: 1))
	}

	private func toggle() {
		withAnimation(.snappy(duration: 0.2)) { open.toggle() }
		guard open, text == nil, let core = store.core else { return }
		Task {
			let detail = try? await core.loadMessage(accountId: accountID, messageId: summary.id)
			let plain = detail.map { AIText.plain(fromHTML: $0.html) } ?? PreviewText.plain(summary.preview)
			text = Self.dropQuoted(plain)
		}
	}

	/// Leaves out the quoted history under "On … wrote:", which the trail already shows.
	private static func dropQuoted(_ text: String) -> String {
		let lines = text.components(separatedBy: "\n")
		var kept: [String] = []
		for line in lines {
			let t = line.trimmingCharacters(in: .whitespaces)
			if (t.hasPrefix("On ") && t.hasSuffix("wrote:")) || t.hasPrefix("-----Original Message") || t.hasPrefix("From: ") && !kept.isEmpty { break }
			kept.append(line)
		}
		return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
	}
}
