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
			let p = AskWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
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
			p.contentView = NSHostingView(rootView: AskView { [weak self] in self?.hide() }.environment(store))
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
}

private struct AskView: View {
	@Environment(MailStore.self) private var store
	var close: () -> Void
	@State private var question = ""
	@State private var askedAt: Int?
	@FocusState private var focused: Bool

	private var chat: AIChatModel { store.chat }

	/// The latest answer, once a question has been asked here.
	private var answer: ChatMessage? {
		guard let askedAt, chat.messages.count > askedAt else { return nil }
		return chat.messages[askedAt...].last { $0.role == .assistant }
	}

	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 12) {
				HIcon(.sparkles, size: 14).foregroundStyle(Folio.onDark)
					.frame(width: 30, height: 30)
					.background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Folio.dark))
				TextField("Ask \(SecretarySettings.name) about your mail…", text: $question)
					.textFieldStyle(.plain).font(.system(size: 18))
					.focused($focused)
					.onSubmit(ask)
				if chat.busy { ProgressView().controlSize(.small) }
				Text("⌥ Space").font(.system(size: 11)).foregroundStyle(Folio.meta)
					.padding(.horizontal, 7).padding(.vertical, 3)
					.overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Folio.line, lineWidth: 1))
			}
			.padding(.horizontal, 18).padding(.vertical, 16)
			Rectangle().fill(Folio.line).frame(height: 1)
			ScrollView {
				VStack(alignment: .leading, spacing: 12) {
					if !store.ai.isConfigured {
						Text("Connect an assistant in Settings › AI engine to ask \(SecretarySettings.name) questions.")
							.font(.system(size: 14)).foregroundStyle(Folio.body)
					} else if let answer {
						if !answer.tools.isEmpty && answer.text.isEmpty {
							Text("Looking through your mail…").font(.system(size: 14)).foregroundStyle(Folio.meta)
						}
						Text(Self.markdown(answer.text)).font(.system(size: 15)).foregroundStyle(Folio.ink).lineSpacing(4)
							.textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
						if !chat.busy {
							HStack(spacing: 8) {
								Button("Continue in the assistant panel") {
									store.chatOpen = true
									NSApp.activate(ignoringOtherApps: true)
									close()
								}
								.buttonStyle(FolioOutlineButtonStyle(ink: Folio.selectionInk, stroke: Folio.accentStroke, height: 30))
							}
						}
					} else if chat.busy {
						Text("Looking through your mail…").font(.system(size: 14)).foregroundStyle(Folio.meta)
					} else {
						VStack(alignment: .leading, spacing: 8) {
							Text("For example").font(.system(size: 12, weight: .semibold)).foregroundStyle(Folio.meta)
							ForEach(["When did I last speak with my accountant?", "When is my next payment due?", "What did I agree with Mira about Thursday?"], id: \.self) { example in
								Button { question = example; ask() } label: {
									Text(example).font(.system(size: 14)).foregroundStyle(Folio.selectionInk)
								}
								.buttonStyle(.plain)
							}
							Text("\(SecretarySettings.name) only looks. Nothing is moved, filed or sent unless you ask.")
								.font(.system(size: 12)).foregroundStyle(Folio.meta).padding(.top, 6)
						}
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(18)
			}
		}
		.frame(minWidth: 520, minHeight: 240)
		.background(Folio.card)
		.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
		.onAppear { focused = true }
	}

	private func ask() {
		let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !q.isEmpty, !chat.busy, store.ai.isConfigured else { return }
		askedAt = chat.messages.count
		chat.send(q, store: store)
		question = ""
	}

	static func markdown(_ text: String) -> AttributedString {
		(try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
	}
}
