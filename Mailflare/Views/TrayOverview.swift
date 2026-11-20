import SwiftUI
import MailflareCore

/// A tray, when no email is open in it: what the tray is for, every email with Sam's note on it, and
/// the one click each needs (Archive, File in its usual folder, Open), plus the whole tray at once.
struct TrayOverview: View {
	@Environment(MailStore.self) private var store
	let status: ThreadStatus

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 18) {
				HStack(alignment: .firstTextBaseline, spacing: 12) {
					StatusDot(status: status, size: 11)
					Text(status.title).font(.system(size: 26, weight: .bold)).tracking(-0.8).foregroundStyle(Folio.ink)
					Text("\(store.messages.count) email\(store.messages.count == 1 ? "" : "s")").font(.system(size: 14)).foregroundStyle(Folio.meta)
					Spacer(minLength: 12)
					bulkAction
				}
				Text(DeskView.hint(status) + ".").font(.system(size: 14)).foregroundStyle(Folio.body)
				VStack(spacing: 0) {
					ForEach(Array(store.messages.enumerated()), id: \.element.id) { index, message in
						if index > 0 { Rectangle().fill(Folio.softLine).frame(height: 1) }
						TrayOverviewRow(message: message, status: status)
					}
				}
				.background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Folio.card))
				.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(status.tileStroke, lineWidth: 1))
				Text("Click an email to read it. Nothing moves until you press a button.")
					.font(.system(size: 12.5)).foregroundStyle(Folio.meta)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal, 40).padding(.vertical, 36)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.background(AppTheme.background)
		.task(id: store.messages.count) { if status == .longTerm { store.guessFolders(for: store.statuses.records(with: .longTerm)) } }
	}

	@ViewBuilder
	private var bulkAction: some View {
		switch status {
		case .canArchive:
			Button("Archive all \(store.messages.count)") { withAnimation(.snappy(duration: 0.25)) { store.archiveAll(in: .canArchive) } }
				.buttonStyle(FolioFilledButtonStyle(height: 36))
		case .longTerm:
			Button("File all as suggested") { withAnimation(.snappy(duration: 0.25)) { store.fileAllSuggested() } }
				.buttonStyle(FolioFilledButtonStyle(height: 36))
		default:
			EmptyView()
		}
	}
}

private struct TrayOverviewRow: View {
	@Environment(MailStore.self) private var store
	let message: MessageSummary
	let status: ThreadStatus
	@State private var hovering = false

	private var owner: (account: String, message: String) { store.ownerOf(message.id) }
	private var record: ThreadRecord? { store.statusRecord(of: message.id) }

	var body: some View {
		let usual = status == .longTerm ? store.suggestedFolder(for: message, accountID: owner.account) : nil
		HStack(alignment: .center, spacing: 14) {
			InitialsAvatar(name: message.senderDisplay, fill: status.avatarFill, ink: status.ink, size: 34)
			VStack(alignment: .leading, spacing: 3) {
				HStack(spacing: 8) {
					Text(MailStore.who(name: message.fromName, email: message.fromEmail)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Folio.ink).lineLimit(1)
					Text(MailDate.list(message.date)).font(.system(size: 12)).foregroundStyle(Folio.meta).fixedSize()
				}
				Text(message.subject.isEmpty ? "(No Subject)" : message.subject).font(.system(size: 13.5)).foregroundStyle(Folio.ink).lineLimit(1)
				Text(note(usual)).font(.system(size: 12.5)).foregroundStyle(status.ink).lineLimit(2)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.contentShape(Rectangle())
			.onTapGesture { store.select(message.id) }
			actions(usual)
		}
		.padding(.horizontal, 16).padding(.vertical, 12)
		.background(hovering ? AppTheme.rowHighlight : .clear)
		.onHover { hovering = $0 }
	}

	/// Sam's line on it: where it goes and why, what's asked, or how long it has waited.
	private func note(_ usual: (id: String, name: String, reason: String)?) -> String {
		switch status {
		case .longTerm:
			if let usual { return "Goes in \(usual.name). \(usual.reason)." }
			return "No usual folder yet. Choose one."
		case .canArchive:
			return record?.reason ?? "Nothing here asks anything of you."
		case .needsReply:
			return record?.ask ?? record?.reason ?? "Waiting for your answer."
		case .waiting:
			let days = record.map { Calendar.current.dateComponents([.day], from: $0.statusAt, to: .now).day ?? 0 } ?? 0
			return (record?.reason ?? "Waiting on them") + (days > 0 ? " · \(days) day\(days == 1 ? "" : "s")" : "")
		}
	}

	@ViewBuilder
	private func actions(_ usual: (id: String, name: String, reason: String)?) -> some View {
		switch status {
		case .canArchive:
			Button("Archive") { withAnimation(.snappy(duration: 0.2)) { store.archive(message.id) } }
				.buttonStyle(FolioOutlineButtonStyle(ink: Folio.selectionInk, stroke: Folio.accentStroke, height: 30))
		case .longTerm:
			HStack(spacing: 6) {
				if let usual {
					Button("File in \(usual.name)") {
						withAnimation(.snappy(duration: 0.2)) { store.file(owner.message, accountID: owner.account, into: usual.id, name: usual.name) }
					}
					.buttonStyle(FolioOutlineButtonStyle(ink: Folio.selectionInk, stroke: Folio.accentStroke, height: 30))
					.help(usual.reason)
				}
				Menu {
					ForEach(store.libraryFolders(of: owner.account)) { f in
						Button(f.path) { withAnimation(.snappy(duration: 0.2)) { store.file(owner.message, accountID: owner.account, into: f.id, name: f.path) } }
					}
				} label: {
					Text(usual == nil ? "Choose a folder" : "Other…").font(.system(size: 12.5, weight: .medium))
				}
				.menuStyle(.button).fixedSize()
			}
		default:
			Button("Open") { store.select(message.id) }
				.buttonStyle(FolioOutlineButtonStyle(height: 30))
		}
	}
}
