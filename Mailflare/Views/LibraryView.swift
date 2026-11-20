import SwiftUI
import MailflareCore

/// How a Library folder is shown: a table with the gist beside it, cards that turn over to their
/// summary, or the plain mail list. Kept per folder on this Mac.
enum LibraryMode: String, CaseIterable, Identifiable {
	case table, cards, list
	var id: String { rawValue }
	var title: String { rawValue.capitalized }
}

extension MailStore {
	/// Whether the sidebar has one of the user's own folders open: those show as the Library.
	var libraryFolder: Mailbox? {
		guard settingsPage == nil, screen == .mail, statusList == nil, case .mailbox(let id) = sidebar,
			  let box = mailbox(id), box.role == nil, !box.isAccount else { return nil }
		return box
	}

	var libraryMode: LibraryMode {
		guard let box = libraryFolder else { return .list }
		_ = libraryModeRevision
		let fallback = LibraryMode(rawValue: UserDefaults.standard.string(forKey: "library.defaultMode") ?? "") ?? .table
		return LibraryMode(rawValue: UserDefaults.standard.string(forKey: "library.mode.\(box.id)") ?? "") ?? fallback
	}

	func setLibraryMode(_ mode: LibraryMode) {
		guard let box = libraryFolder else { return }
		UserDefaults.standard.set(mode.rawValue, forKey: "library.mode.\(box.id)")
		libraryModeRevision += 1
	}

	/// The saved gist of a message, or a new one written now and saved with the message.
	func gist(for m: MessageSummary) async -> String? {
		if let known = summaries[m.id] { return known }
		let owner = ownerOf(m.id)
		if let saved = (try? core?.aiSummary(accountId: owner.account, messageId: owner.message)) ?? nil {
			summaries[m.id] = saved
			return saved
		}
		guard let client = ai.backgroundClient, let core,
			  let detail = try? await core.loadMessage(accountId: owner.account, messageId: owner.message) else { return nil }
		guard let text = try? await AISummarizer.summarize(client: client, subject: m.subject, from: m.sender.formatted,
														   text: AIText.plain(fromHTML: detail.html)) else { return nil }
		try? core.saveAiSummary(accountId: owner.account, messageId: owner.message, text: text)
		summaries[m.id] = text
		return text
	}

	/// The saved gist only, without asking the assistant: for long lists.
	func savedGist(for m: MessageSummary) -> String? {
		if let known = summaries[m.id] { return known }
		let owner = ownerOf(m.id)
		guard let saved = (try? core?.aiSummary(accountId: owner.account, messageId: owner.message)) ?? nil else { return nil }
		return saved
	}
}

struct LibraryView: View {
	@Environment(MailStore.self) private var store
	@State private var selected: String?
	@State private var showFull = false

	var body: some View {
		VStack(spacing: 0) {
			header
			Rectangle().fill(Folio.line).frame(height: 1)
			if store.messages.isEmpty {
				EmptyStateView(icon: .folder, title: "Nothing filed here yet")
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else if store.libraryMode == .cards {
				cards
			} else {
				HStack(spacing: 0) {
					table.frame(minWidth: 380, maxWidth: .infinity)
					Rectangle().fill(Folio.line).frame(width: 1)
					Group {
						if showFull, selected != nil { ReaderView() } else { gistPane }
					}
					.frame(width: showFull ? 560 : 400)
				}
			}
		}
		.background(Folio.card)
		.onChange(of: store.sidebar) { _, _ in selected = nil; showFull = false }
	}

	// MARK: Header

	private var header: some View {
		HStack(spacing: 16) {
			VStack(alignment: .leading, spacing: 2) {
				Text("LIBRARY").font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(ThreadStatus.longTerm.ink)
				HStack(alignment: .firstTextBaseline, spacing: 8) {
					Text(store.libraryFolder?.name ?? "Folder").font(.system(size: 22, weight: .bold)).foregroundStyle(Folio.ink)
					Text("· \(store.messages.count) emails").font(.system(size: 14)).foregroundStyle(Folio.meta)
				}
			}
			Spacer(minLength: 12)
			HStack(spacing: 2) {
				ForEach(LibraryMode.allCases) { mode in
					Button { store.setLibraryMode(mode) } label: {
						Text(mode.title).font(.system(size: 13, weight: .semibold))
							.foregroundStyle(store.libraryMode == mode ? Folio.onDark : Folio.body)
							.padding(.horizontal, 12).frame(height: 28)
							.background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(store.libraryMode == mode ? Folio.dark : .clear))
							.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					.accessibilityAddTraits(store.libraryMode == mode ? .isSelected : [])
				}
			}
			.padding(3)
			.overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Folio.line, lineWidth: 1))
		}
		.padding(.horizontal, 28).padding(.top, WindowChromeMetrics.titlebarHeight + 6).padding(.bottom, 16)
	}

	// MARK: Table

	private var table: some View {
		ScrollView {
			LazyVStack(spacing: 0) {
				HStack(spacing: 12) {
					Text("From").frame(width: 150, alignment: .leading)
					Text("The gist").frame(maxWidth: .infinity, alignment: .leading)
					Text("Date").frame(width: 90, alignment: .trailing)
				}
				.font(.system(size: 12, weight: .semibold)).foregroundStyle(Folio.meta)
				.padding(.horizontal, 20).padding(.vertical, 10)
				ForEach(store.messages, id: \.id) { m in
					Rectangle().fill(Folio.softLine).frame(height: 1)
					Button { choose(m) } label: {
						HStack(spacing: 12) {
							Text(m.senderDisplay).font(.system(size: 13, weight: .semibold)).foregroundStyle(Folio.ink)
								.lineLimit(1).frame(width: 150, alignment: .leading)
							Text(firstLine(store.savedGist(for: m)) ?? (m.subject.isEmpty ? PreviewText.plain(m.preview) : m.subject))
								.font(.system(size: 13)).foregroundStyle(Folio.body).lineLimit(1)
								.frame(maxWidth: .infinity, alignment: .leading)
							Text(shortDate(m.date)).font(.system(size: 12)).foregroundStyle(Folio.meta).frame(width: 90, alignment: .trailing)
						}
						.padding(.horizontal, 20).padding(.vertical, 11)
						.background(selected == m.id ? Folio.selection : .clear)
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
				}
			}
		}
	}

	private func choose(_ m: MessageSummary) {
		selected = m.id
		showFull = false
		store.select(m.id)
	}

	// MARK: Gist pane

	@ViewBuilder
	private var gistPane: some View {
		if let id = selected, let m = store.messages.first(where: { $0.id == id }) {
			GistPane(message: m, openFull: { showFull = true })
				.id(m.id)
		} else {
			VStack(spacing: 8) {
				Text("Pick an email to see its gist").font(.system(size: 14, weight: .semibold)).foregroundStyle(Folio.ink)
				Text("\(SecretarySettings.name) reads it for you and keeps the summary.").font(.system(size: 13)).foregroundStyle(Folio.meta)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.background(Folio.soft)
		}
	}

	// MARK: Cards

	private var cards: some View {
		ScrollView {
			LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 16)], spacing: 16) {
				ForEach(store.messages, id: \.id) { m in LibraryCard(message: m) }
			}
			.padding(24)
		}
		.background(Folio.sidebar)
	}
}

private func firstLine(_ text: String?) -> String? {
	guard let text else { return nil }
	let line = text.split(separator: "\n").first.map(String.init) ?? text
	return line.hasPrefix("- ") ? String(line.dropFirst(2)) : line
}

private func shortDate(_ date: Date) -> String {
	Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
		? date.formatted(.dateTime.day().month(.abbreviated))
		: date.formatted(.dateTime.day().month(.abbreviated).year())
}

/// The gist of one Library email: the summary, and ways to read more.
private struct GistPane: View {
	@Environment(MailStore.self) private var store
	let message: MessageSummary
	var openFull: () -> Void
	@State private var gist: String?
	@State private var loading = false

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 14) {
				Text("THE GIST").font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(Folio.meta)
				Text(message.subject.isEmpty ? "(No Subject)" : message.subject).font(.system(size: 18, weight: .bold)).foregroundStyle(Folio.ink)
					.fixedSize(horizontal: false, vertical: true)
				Text("\(message.senderDisplay) · \(message.date.formatted(date: .abbreviated, time: .shortened))")
					.font(.system(size: 12)).foregroundStyle(Folio.meta)
				Group {
					if let gist {
						Text(gist).font(.system(size: 14)).foregroundStyle(Folio.body).lineSpacing(4).textSelection(.enabled)
					} else if loading {
						HStack(spacing: 8) { ProgressView().controlSize(.small); Text("\(SecretarySettings.name) is reading it…").foregroundStyle(Folio.meta) }
							.font(.system(size: 13))
					} else {
						Text(PreviewText.plain(message.preview)).font(.system(size: 14)).foregroundStyle(Folio.body).lineSpacing(4)
					}
				}
				.fixedSize(horizontal: false, vertical: true)
				HStack(spacing: 8) {
					Button("Open full email", action: openFull).buttonStyle(FolioFilledButtonStyle(fill: Folio.dark, ink: Folio.onDark, height: 34))
					Button("Ask about this") {
						store.select(message.id)
						AskPanelController.shared.show(store: store)
					}
					.buttonStyle(FolioOutlineButtonStyle(ink: Folio.selectionInk, stroke: Folio.accentStroke, height: 34))
				}
				.padding(.top, 4)
			}
			.padding(24)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.background(Folio.soft)
		.task {
			gist = store.savedGist(for: message)
			guard gist == nil, store.ai.backgroundClient != nil else { return }
			loading = true
			gist = await store.gist(for: message)
			loading = false
		}
	}
}

/// A Library card: sender, subject and a line on the front; turned over, the full gist.
private struct LibraryCard: View {
	@Environment(MailStore.self) private var store
	let message: MessageSummary
	@State private var flipped = false
	@State private var gist: String?
	@State private var loading = false

	var body: some View {
		ZStack {
			front.opacity(flipped ? 0 : 1)
			back.opacity(flipped ? 1 : 0).rotation3DEffect(.degrees(180), axis: (0, 1, 0))
		}
		.frame(height: 200)
		.rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (0, 1, 0), perspective: 0.4)
		.animation(.snappy(duration: 0.35), value: flipped)
	}

	private var front: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("\(message.senderDisplay) · \(shortDate(message.date))").font(.system(size: 12)).foregroundStyle(Folio.meta).lineLimit(1)
			Text(message.subject.isEmpty ? "(No Subject)" : message.subject).font(.system(size: 15, weight: .semibold)).foregroundStyle(Folio.ink).lineLimit(2)
			Text(firstLine(gist ?? store.savedGist(for: message)) ?? PreviewText.plain(message.preview))
				.font(.system(size: 13)).foregroundStyle(Folio.body).lineLimit(3)
			Spacer(minLength: 0)
			Button("Show summary") { turn() }.buttonStyle(FolioOutlineButtonStyle(height: 28))
		}
		.padding(16)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Folio.card))
		.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Folio.line, lineWidth: 1))
	}

	private var back: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text("THE GIST").font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(Folio.meta)
				Spacer()
				Button { flipped = false } label: { HIcon(.close, size: 11).foregroundStyle(Folio.meta) }.buttonStyle(.plain)
			}
			ScrollView {
				Group {
					if let gist { Text(gist) } else if loading { Text("\(SecretarySettings.name) is reading it…").foregroundStyle(Folio.meta) }
					else { Text(PreviewText.plain(message.preview)) }
				}
				.font(.system(size: 13)).foregroundStyle(Folio.body).lineSpacing(3)
				.frame(maxWidth: .infinity, alignment: .leading)
				.textSelection(.enabled)
			}
			Button("Open full email") {
				store.setLibraryMode(.table)
				store.select(message.id)
			}
			.buttonStyle(FolioFilledButtonStyle(fill: Folio.dark, ink: Folio.onDark, height: 28))
		}
		.padding(16)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Folio.card))
		.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Folio.accent, lineWidth: 2))
	}

	private func turn() {
		flipped = true
		guard gist == nil else { return }
		gist = store.savedGist(for: message)
		guard gist == nil, store.ai.backgroundClient != nil else { return }
		loading = true
		Task {
			gist = await store.gist(for: message)
			loading = false
		}
	}
}
