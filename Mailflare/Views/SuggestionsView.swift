import SwiftUI
import MailflareCore

/// A folder rule SuperMail offers on the Desk: always file a sender's mail in one folder.
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
			Button("Always file") { Automation.shared.accept(suggestion, store: store) }
				.buttonStyle(FolioOutlineButtonStyle(ink: Folio.selectionInk, stroke: Folio.accentStroke, height: 30))
			Button { Automation.shared.dismiss(suggestion) } label: { HIcon(.close, size: 13).foregroundStyle(Folio.meta).frame(width: 24, height: 24) }
				.buttonStyle(.plain).help("Don't suggest this again")
		}
		.frame(minHeight: 56)
	}
}
