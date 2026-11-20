import SwiftUI
import MailflareCore

/// One account's section of the Library: its folders as cards, each with what came in last.
struct ShelfView: View {
	@Environment(MailStore.self) private var store
	let accountID: String
	@State private var showHidden = false

	private let columns = [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 14)]

	var body: some View {
		let account = store.accountList.first { $0.id == accountID }
		let all = store.libraryFolders(of: accountID, includeHidden: true)
		let hidden = store.hiddenLibraryFolders
		// Folders with mail first; empty ones at the end.
		let shown = all.filter { !hidden.contains($0.id) && $0.depth == 0 }.sorted { ($0.total > 0 ? 0 : 1) < ($1.total > 0 ? 0 : 1) }
		let hiddenOnes = all.filter { hidden.contains($0.id) }
		VStack(alignment: .leading, spacing: 0) {
			HStack(alignment: .bottom, spacing: 12) {
				VStack(alignment: .leading, spacing: 4) {
					Text("LIBRARY").font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(ThreadStatus.longTerm.ink)
					HStack(alignment: .firstTextBaseline, spacing: 6) {
						Text(account.map(store.switcherName) ?? "Account").font(.system(size: 24, weight: .bold)).tracking(-0.6).foregroundStyle(Folio.ink)
						Text("· \(all.count - hiddenOnes.count) folders").font(.system(size: 15)).foregroundStyle(Folio.meta)
					}
					if let email = account?.email { Text(email).font(.system(size: 13)).foregroundStyle(Folio.meta) }
				}
				Spacer()
				if store.canCreateFolders(accountID: accountID) {
					Button(store.folderSupport(accountID: accountID)?.noun == "label" ? "New label" : "New folder") {
						store.folderRequest = .init(accountID: accountID, kind: .create(parentID: nil))
					}
					.buttonStyle(FolioOutlineButtonStyle(height: 34))
				}
			}
			.padding(.horizontal, 32).padding(.top, 30).padding(.bottom, 18)
			Rectangle().fill(Folio.line).frame(height: 1)
			ScrollView {
				VStack(alignment: .leading, spacing: 18) {
					if shown.isEmpty {
						Text("No folders here yet. Mail you file from the Desk for this account lands in its folders.")
							.font(.system(size: 14)).foregroundStyle(Folio.body)
					}
					LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
						ForEach(shown) { folder in
							ShelfCard(folder: folder, subfolders: all.filter { $0.parentID == folder.id && !hidden.contains($0.id) })
						}
					}
					if !hiddenOnes.isEmpty {
						Button(showHidden ? "Hide the hidden folders" : "\(hiddenOnes.count) hidden from the Library") {
							withAnimation(.snappy(duration: 0.2)) { showHidden.toggle() }
						}
						.buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(Folio.selectionInk)
						if showHidden {
							VStack(alignment: .leading, spacing: 6) {
								ForEach(hiddenOnes) { folder in
									HStack {
										Text(folder.path).font(.system(size: 13)).foregroundStyle(Folio.body)
										Spacer()
										Button("Show in the Library") { store.setLibraryFolder(folder.id, hidden: false) }
											.buttonStyle(FolioOutlineButtonStyle(height: 28))
									}
								}
							}
							.frame(maxWidth: 520)
						}
					}
				}
				.padding(32)
				.frame(maxWidth: .infinity, alignment: .leading)
			}
			.background(Folio.sidebar.opacity(0.6))
		}
		.background(Folio.card)
	}
}

private struct ShelfCard: View {
	@Environment(MailStore.self) private var store
	let folder: LibraryFolder
	let subfolders: [LibraryFolder]
	@State private var hovering = false

	var body: some View {
		let latest = store.latest(in: folder, limit: 2)
		Button { store.openLibraryFolder(folder) } label: {
			VStack(alignment: .leading, spacing: 8) {
				HStack(spacing: 8) {
					HIcon(.folder, size: 14).foregroundStyle(ThreadStatus.longTerm.ink)
					Text(folder.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Folio.ink).lineLimit(1)
					Spacer(minLength: 4)
					Text("\(folder.total)").font(.system(size: 12.5)).foregroundStyle(Folio.meta)
				}
				if latest.isEmpty {
					Text("Nothing filed yet").font(.system(size: 13)).foregroundStyle(Folio.meta)
				} else {
					ForEach(latest, id: \.id) { m in
						VStack(alignment: .leading, spacing: 1) {
							Text(store.savedGist(for: m) ?? m.subject).font(.system(size: 13)).foregroundStyle(Folio.body).lineLimit(1)
							Text("\(m.senderDisplay) · \(Date(timeIntervalSince1970: TimeInterval(m.receivedAt)).formatted(.dateTime.day().month(.abbreviated)))")
								.font(.system(size: 11.5)).foregroundStyle(Folio.meta).lineLimit(1)
						}
					}
				}
				if !subfolders.isEmpty {
					Text(subfolders.prefix(4).map(\.name).joined(separator: " · ") + (subfolders.count > 4 ? " · +\(subfolders.count - 4)" : ""))
						.font(.system(size: 12)).foregroundStyle(ThreadStatus.longTerm.ink).lineLimit(1)
				}
			}
			.frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
			.padding(16)
			.background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Folio.card))
			.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(hovering ? ThreadStatus.longTerm.tileStroke : Folio.line, lineWidth: 1))
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { hovering = $0 }
		.contextMenu {
			Button("Hide from the Library") { store.setLibraryFolder(folder.id, hidden: true) }
		}
	}
}
