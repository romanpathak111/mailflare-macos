import SwiftUI
import MailflareCore

/// Everything the assistant suggests, in one place: statuses for new mail and folder rules. Each
/// can be accepted, changed or dismissed; nothing happens until the user says so.
struct SuggestionsSheet: View {
	@Environment(MailStore.self) private var store
	@Environment(\.dismiss) private var dismiss
	private var automation: Automation { Automation.shared }

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack(alignment: .firstTextBaseline) {
				Text("Suggestions").font(.system(size: 24, weight: .bold)).tracking(-0.6).foregroundStyle(Folio.ink)
				Spacer()
				Button("Done") { dismiss() }.buttonStyle(FolioOutlineButtonStyle(height: 34)).keyboardShortcut(.cancelAction)
			}
			.padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)
			Rectangle().fill(Folio.line).frame(height: 1)
			ScrollView {
				VStack(alignment: .leading, spacing: 28) {
					if automation.statusSuggestions.isEmpty && automation.ruleSuggestions.isEmpty {
						Text(automation.isSuggestingStatuses ? "Looking at new mail…" : "Nothing to suggest right now.")
							.font(.system(size: 14)).foregroundStyle(Folio.meta)
					}
					if !automation.ruleSuggestions.isEmpty { rulesSection }
					if !automation.statusSuggestions.isEmpty { statusSection }
				}
				.padding(28)
			}
		}
		.frame(width: 640, height: 560)
		.background(Folio.card)
	}

	private var statusSection: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack(alignment: .firstTextBaseline) {
				Text("Statuses for new mail").font(.system(size: 17, weight: .bold)).foregroundStyle(Folio.ink)
				Spacer()
				Button("Accept all \(automation.statusSuggestions.count)") { automation.acceptAllStatuses(store: store) }
					.buttonStyle(FolioFilledButtonStyle(height: 32))
			}
			.padding(.bottom, 10)
			ForEach(automation.statusSuggestions) { item in
				Rectangle().fill(Folio.line).frame(height: 1)
				HStack(spacing: 12) {
					VStack(alignment: .leading, spacing: 2) {
						Text(item.summary.subject.isEmpty ? "(No Subject)" : item.summary.subject)
							.font(.system(size: 14, weight: .semibold)).foregroundStyle(Folio.ink).lineLimit(1)
						Text(item.summary.senderDisplay + (item.suggestion.ask.map { " · \($0)" } ?? ""))
							.font(.system(size: 12)).foregroundStyle(Folio.meta).lineLimit(1)
					}
					Spacer(minLength: 8)
					// The status it will be accepted as; pick another to change it first.
					Menu {
						ForEach(ThreadStatus.allCases) { status in
							Button { automation.choose(status, for: item) } label: {
								if status == automation.status(of: item) { Label(status.title, systemImage: "checkmark") } else { Text(status.title) }
							}
						}
					} label: {
						HStack(spacing: 4) {
							StatusChip(status: automation.status(of: item), short: false)
							Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Folio.meta)
						}
					}
					.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
					.help("Change the status before accepting")
					Button("Accept") { automation.accept(item, store: store) }
						.buttonStyle(FolioOutlineButtonStyle(ink: Folio.selectionInk, stroke: Folio.accentStroke, height: 30))
					Button { automation.dismiss(item) } label: { HIcon(.close, size: 13).foregroundStyle(Folio.meta).frame(width: 24, height: 24) }
						.buttonStyle(.plain).help("Not this one")
				}
				.frame(minHeight: 56)
			}
			Rectangle().fill(Folio.line).frame(height: 1)
		}
	}

	private var rulesSection: some View {
		VStack(alignment: .leading, spacing: 0) {
			Text("Folder rules").font(.system(size: 17, weight: .bold)).foregroundStyle(Folio.ink).padding(.bottom, 4)
			Text("Learned from where you file mail. Accepting files the waiting mail now and new mail from then on.")
				.font(.system(size: 12)).foregroundStyle(Folio.meta).padding(.bottom, 10)
			ForEach(automation.ruleSuggestions) { suggestion in
				Rectangle().fill(Folio.line).frame(height: 1)
				RuleSuggestionRow(suggestion: suggestion)
			}
			Rectangle().fill(Folio.line).frame(height: 1)
		}
	}
}

/// One suggested folder rule with Change (another folder), Accept and Dismiss.
struct RuleSuggestionRow: View {
	@Environment(MailStore.self) private var store
	let suggestion: RuleSuggestion

	var body: some View {
		HStack(spacing: 12) {
			HIcon(.folder, size: 16).foregroundStyle(store.folderColors.color(for: suggestion.folderID) ?? Folio.body)
			VStack(alignment: .leading, spacing: 2) {
				Text("File @\(suggestion.domain) into \(suggestion.folderName)")
					.font(.system(size: 14, weight: .semibold)).foregroundStyle(Folio.ink).lineLimit(1)
				Text(suggestion.changed
					 ? "Your choice · \(suggestion.waiting) in the inbox now"
					 : "\(suggestion.filed) already filed there · \(suggestion.waiting) in the inbox now")
					.font(.system(size: 12)).foregroundStyle(Folio.meta).lineLimit(1)
			}
			Spacer(minLength: 8)
			// Another folder for the rule, chosen before accepting.
			Menu {
				ForEach(store.customFolders(of: suggestion.accountID), id: \.id) { box in
					Button { Automation.shared.change(suggestion, toFolder: box.id, name: box.name) } label: {
						if box.id == suggestion.folderID { Label(box.name, systemImage: "checkmark") } else { Text(box.name) }
					}
				}
			} label: {
				HStack(spacing: 4) {
					Text("Change").font(.system(size: 13, weight: .semibold)).foregroundStyle(Folio.body)
					Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Folio.meta)
				}
				.padding(.horizontal, 10).frame(height: 30)
				.background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Folio.card))
				.overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Folio.line, lineWidth: 1))
			}
			.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
			.help("File this sender's mail into a different folder")
			Button("Accept") { Automation.shared.accept(suggestion, store: store) }
				.buttonStyle(FolioOutlineButtonStyle(ink: Folio.selectionInk, stroke: Folio.accentStroke, height: 30))
			Button { Automation.shared.dismiss(suggestion) } label: { HIcon(.close, size: 13).foregroundStyle(Folio.meta).frame(width: 24, height: 24) }
				.buttonStyle(.plain).help("Don't suggest this again")
		}
		.frame(minHeight: 56)
	}
}

/// The line under the assistant brief: how many suggestions wait, and the way to review them.
struct SuggestionsLine: View {
	@Environment(MailStore.self) private var store
	@State private var showing = false
	private var automation: Automation { Automation.shared }

	var body: some View {
		let statuses = automation.statusSuggestions.count
		let rules = automation.ruleSuggestions.count
		if statuses + rules > 0 || automation.isSuggestingStatuses {
			HStack(spacing: 8) {
				if automation.isSuggestingStatuses && statuses == 0 {
					ProgressView().controlSize(.mini)
					Text("Looking at new mail…").font(.system(size: 13)).foregroundStyle(Folio.meta)
				}
				if statuses > 0 { chip("\(statuses) status suggestion\(statuses == 1 ? "" : "s")", dot: ThreadStatus.needsReply.dot) }
				if rules > 0 { chip("\(rules) folder rule\(rules == 1 ? "" : "s")", dot: ThreadStatus.longTerm.dot) }
				if statuses + rules > 0 {
					Button("Review") { showing = true }
						.buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Folio.selectionInk)
				}
			}
			.sheet(isPresented: $showing) { SuggestionsSheet() }
		}
	}

	private func chip(_ text: String, dot: Color) -> some View {
		Button { showing = true } label: {
			HStack(spacing: 6) {
				Circle().fill(dot).frame(width: 6, height: 6)
				Text(text).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Folio.body)
			}
			.padding(.horizontal, 10).padding(.vertical, 5)
			.background(Capsule().fill(Folio.chip))
		}
		.buttonStyle(.plain)
	}
}
