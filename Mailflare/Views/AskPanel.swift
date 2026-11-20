import AppKit
import Carbon.HIToolbox
import SwiftUI

/// "Ask Sam": a small floating box that opens over whatever the user is working in (⌥ Space, the
/// menu-bar envelope, or the sidebar), answers from their mail, and goes away with Esc. It shares
/// the assistant's conversation, so the panel in the main window shows the same chat.
@MainActor
final class AskPanelController {
	static let shared = AskPanelController()

	private var panel: NSPanel?
	private weak var store: MailStore?
	private var hotKey: EventHotKeyRef?
	private var handler: EventHandlerRef?

	/// Registers ⌥ Space once the store exists; works while SuperMail is in the background.
	func install(store: MailStore) {
		self.store = store
		guard hotKey == nil, SecretarySettings.askShortcut else { return }
		var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
		InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
			Task { @MainActor in AskPanelController.shared.toggle() }
			return noErr
		}, 1, &spec, nil, &handler)
		let id = EventHotKeyID(signature: OSType(0x534D_4153), id: 1) // "SMAS"
		RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
	}

	func uninstall() {
		if let hotKey { UnregisterEventHotKey(hotKey) }
		hotKey = nil
	}

	func toggle() {
		if panel?.isVisible == true { hide() } else if let store { show(store: store) }
	}

	func show(store: MailStore) {
		self.store = store
		if panel == nil {
			let p = AskWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
							  styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable], backing: .buffered, defer: false)
			p.titleVisibility = .hidden
			p.titlebarAppearsTransparent = true
			p.standardWindowButton(.closeButton)?.isHidden = true
			p.standardWindowButton(.miniaturizeButton)?.isHidden = true
			p.standardWindowButton(.zoomButton)?.isHidden = true
			p.isMovableByWindowBackground = true
			p.level = .floating
			p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
			p.hidesOnDeactivate = false
			p.isReleasedWhenClosed = false
			p.backgroundColor = .clear
			p.contentView = NSHostingView(rootView: SamView(mode: .floating { [weak self] in self?.hide() }).environment(store))
			panel = p
		}
		guard let panel else { return }
		if let screen = NSScreen.main {
			let frame = screen.visibleFrame
			panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - panel.frame.height - frame.height * 0.12))
		}
		panel.makeKeyAndOrderFront(nil)
	}

	func hide() { panel?.orderOut(nil) }
}

/// A panel that takes the keyboard without bringing SuperMail's main window forward.
private final class AskWindow: NSPanel {
	override var canBecomeKey: Bool { true }
	override func cancelOperation(_ sender: Any?) { orderOut(nil) }
	/// Like Spotlight: a click anywhere else puts it away.
	override func resignKey() {
		super.resignKey()
		orderOut(nil)
	}
}

/// Sam: ask in plain words, get a short answer and the emails themselves as cards that open them.
/// The same conversation shows in the floating box (⌥ Space) and in the Desk's right-hand column.
struct SamView: View {
	enum Mode {
		/// The floating box: closes with Esc, its ✕, or opening an email.
		case floating(close: () -> Void)
		/// A column of the Desk.
		case embedded
	}

	@Environment(MailStore.self) private var store
	let mode: Mode
	@State private var question = ""
	@FocusState private var focused: Bool

	private var chat: AIChatModel { store.chat }
	private var isFloating: Bool { if case .floating = mode { return true } else { return false } }
	private func close() { if case .floating(let close) = mode { close() } }

	var body: some View {
		VStack(spacing: 0) {
			askField
			Rectangle().fill(Folio.line).frame(height: 1)
			ScrollViewReader { scroller in
				ScrollView {
					VStack(alignment: .leading, spacing: 14) {
						if !store.ai.isConfigured {
							Text("Connect an assistant in Settings › AI engine to ask \(SecretarySettings.name) questions.")
								.font(.system(size: 14)).foregroundStyle(Folio.body)
						} else if chat.messages.isEmpty {
							examples
						} else {
							ForEach(chat.messages) { message in turn(message) }
							if chat.busy {
								HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Looking through your mail…") }
									.font(.system(size: 13)).foregroundStyle(Folio.meta)
							}
						}
						Color.clear.frame(height: 1).id("samEnd")
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(18)
				}
				.onChange(of: chat.messages.count) { _, _ in withAnimation(.snappy(duration: 0.25)) { scroller.scrollTo("samEnd", anchor: .bottom) } }
				.onChange(of: chat.messages.last?.text.count ?? 0) { _, _ in scroller.scrollTo("samEnd", anchor: .bottom) }
			}
			if !chat.messages.isEmpty && !chat.busy {
				Rectangle().fill(Folio.line).frame(height: 1)
				HStack {
					Button("New question") { chat.reset(); focused = true }
						.buttonStyle(.plain).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Folio.selectionInk)
					Spacer()
					Text("\(SecretarySettings.name) only looks. Nothing is moved or sent unless you ask.")
						.font(.system(size: 11.5)).foregroundStyle(Folio.meta).lineLimit(1)
				}
				.padding(.horizontal, 18).padding(.vertical, 10)
			}
		}
		.frame(minWidth: isFloating ? 560 : 0, minHeight: isFloating ? 300 : 0)
		.background(Folio.card)
		.clipShape(RoundedRectangle(cornerRadius: isFloating ? 16 : 14, style: .continuous))
		.overlay { if !isFloating { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Folio.line, lineWidth: 1) } }
		.onAppear { if isFloating { focused = true } }
		.task(id: store.currentAccountID) { if chat.messages.isEmpty { chat.loadHistory(accountID: store.currentAccountID) } }
	}

	// MARK: Asking

	private var askField: some View {
		HStack(spacing: 12) {
			HIcon(.sparkles, size: 14).foregroundStyle(Folio.onDark)
				.frame(width: 30, height: 30)
				.background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Folio.dark))
			TextField(chat.messages.isEmpty ? "Ask \(SecretarySettings.name) for any email…" : "Ask a follow-up…", text: $question)
				.textFieldStyle(.plain).font(.system(size: isFloating ? 18 : 15))
				.focused($focused)
				.onSubmit(ask)
				.onKeyPress(.escape) { if isFloating { close(); return .handled }; return .ignored }
			if chat.busy {
				Button { chat.reset() } label: { Text("Stop").font(.system(size: 12, weight: .medium)) }
					.buttonStyle(.plain).foregroundStyle(Folio.meta)
			}
			if isFloating {
				Text("Esc to close").font(.system(size: 11)).foregroundStyle(Folio.meta)
				Button(action: close) {
					HIcon(.close, size: 12).foregroundStyle(Folio.meta)
						.frame(width: 26, height: 26)
						.background(Circle().fill(Folio.soft))
						.contentShape(Circle())
				}
				.buttonStyle(.plain)
				.help("Close")
			}
		}
		.padding(.horizontal, isFloating ? 18 : 14).padding(.vertical, isFloating ? 16 : 12)
	}

	private var examples: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("Ask for the emails you want").font(.system(size: 13, weight: .semibold)).foregroundStyle(Folio.ink)
			ForEach(["Show me the last email from my accountant", "Invoices from this month", "When is my next payment due?", "What did RACGP send me this week?"], id: \.self) { example in
				Button { question = example; ask() } label: {
					HStack(spacing: 8) {
						HIcon(.search, size: 12).foregroundStyle(Folio.meta)
						Text(example).font(.system(size: 13.5)).foregroundStyle(Folio.selectionInk)
					}
				}
				.buttonStyle(.plain)
			}
			Text("\(SecretarySettings.name) searches every account and shows the emails themselves. Click one to open it.")
				.font(.system(size: 12)).foregroundStyle(Folio.meta).padding(.top, 4)
				.fixedSize(horizontal: false, vertical: true)
		}
	}

	private func ask() {
		let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !q.isEmpty, !chat.busy, store.ai.isConfigured else { return }
		chat.send(q, store: store)
		question = ""
	}

	// MARK: The conversation

	@ViewBuilder
	private func turn(_ message: ChatMessage) -> some View {
		if message.role == .user {
			HStack {
				Spacer(minLength: 40)
				Text(message.text).font(.system(size: 14)).foregroundStyle(Folio.ink)
					.padding(.horizontal, 12).padding(.vertical, 8)
					.background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Folio.accentSoft))
					.overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Folio.accentStroke, lineWidth: 1))
					.textSelection(.enabled)
			}
		} else {
			VStack(alignment: .leading, spacing: 10) {
				ForEach(message.tools) { run in
					if let approval = run.approval, run.status == .waiting {
						approvalCard(run, approval)
					}
				}
				if !message.text.isEmpty {
					Text(Self.markdown(message.text)).font(.system(size: 14.5)).foregroundStyle(message.isError ? .orange : Folio.ink).lineSpacing(3)
						.textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
				}
				let emails = message.tools.flatMap { $0.emails ?? [] }
				if !emails.isEmpty {
					VStack(spacing: 6) { ForEach(emails) { EmailCard(email: $0) { open($0) } } }
				}
			}
		}
	}

	private func approvalCard(_ run: ChatToolRun, _ approval: ToolApproval) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("\(SecretarySettings.name) wants to use \(approval.tool) on \(approval.server).").font(.system(size: 13, weight: .semibold))
			HStack(spacing: 8) {
				Button("Allow once") { chat.decide(run.id, .allowed) }.buttonStyle(FolioFilledButtonStyle(height: 28))
				Button("Don't allow") { chat.decide(run.id, .denied) }.buttonStyle(FolioOutlineButtonStyle(height: 28))
			}
		}
		.padding(12)
		.background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Folio.soft))
	}

	private func open(_ email: ShownEmail) {
		store.openMessage(accountID: email.accountID, messageID: email.messageID)
		close()
	}

	static func markdown(_ text: String) -> AttributedString {
		(try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
	}
}

/// One email Sam found: who, when, the subject and a line of it. Clicking opens it.
private struct EmailCard: View {
	@Environment(MailStore.self) private var store
	let email: ShownEmail
	let open: (ShownEmail) -> Void
	@State private var hovering = false

	var body: some View {
		Button { open(email) } label: {
			HStack(alignment: .top, spacing: 10) {
				InitialsAvatar(name: email.from, fill: Folio.accentSoft, ink: Folio.selectionInk, size: 30)
				VStack(alignment: .leading, spacing: 2) {
					HStack(spacing: 6) {
						Text(email.from).font(.system(size: 13, weight: .semibold)).foregroundStyle(Folio.ink).lineLimit(1)
						Spacer(minLength: 4)
						if store.accountList.count > 1, let account = store.accountList.first(where: { $0.id == email.accountID }) {
							Text(store.accountName(account)).font(.system(size: 11)).foregroundStyle(Folio.meta).lineLimit(1)
						}
						Text(MailDate.list(email.date)).font(.system(size: 11.5)).foregroundStyle(Folio.meta).fixedSize()
					}
					Text(email.subject.isEmpty ? "(No Subject)" : email.subject).font(.system(size: 13)).foregroundStyle(Folio.ink).lineLimit(1)
					if !email.preview.isEmpty {
						Text(email.preview).font(.system(size: 12)).foregroundStyle(Folio.meta).lineLimit(1)
					}
				}
			}
			.padding(10)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Folio.accentSoft : Folio.soft))
			.overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(hovering ? Folio.accentStroke : Folio.line, lineWidth: 1))
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { hovering = $0 }
		.help("Open this email")
	}
}
