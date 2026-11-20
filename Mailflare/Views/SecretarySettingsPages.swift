import SwiftUI
import UniformTypeIdentifiers

/// Settings › Secretary: who they are and how much they do on their own.
struct SecretarySettingsPage: View {
	@Environment(MailStore.self) private var store
	@AppStorage(SecretarySettings.nameKey) private var name = "Sam"
	@AppStorage(SecretarySettings.pronounKey) private var pronoun = SecretarySettings.Pronoun.name.rawValue
	@AppStorage(SecretarySettings.personalityKey) private var personality = SecretarySettings.Personality.brief.rawValue
	@AppStorage(SecretarySettings.sortModeKey) private var sortMode = SecretarySettings.SortMode.arrival.rawValue
	@AppStorage(SecretarySettings.headsUpKey) private var headsUp = SecretarySettings.HeadsUp.balanced.rawValue
	@AppStorage(SecretarySettings.autoWaitingKey) private var autoWaiting = true
	@AppStorage(SecretarySettings.autoBackKey) private var autoBack = true
	@AppStorage(SecretarySettings.autoRememberKey) private var autoRemember = false
	@AppStorage(SecretarySettings.autoFileKey) private var autoFile = false
	@AppStorage(SecretarySettings.askShortcutKey) private var askShortcut = true

	var body: some View {
		VStack(alignment: .leading, spacing: 28) {
			PageTitle("Secretary", "Your secretary sorts new mail, keeps track of who owes whom, and answers questions about your mail. Make them yours.")

			SecretaryGroup("Who they are") {
				HStack(alignment: .top, spacing: 16) {
					VStack(alignment: .leading, spacing: 6) {
						Text("Name").font(.system(size: 12)).foregroundStyle(Folio.meta)
						TextField("Sam", text: $name).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
					}
					VStack(alignment: .leading, spacing: 6) {
						Text("How SuperMail refers to them").font(.system(size: 12)).foregroundStyle(Folio.meta)
						Picker("", selection: $pronoun) {
							ForEach(SecretarySettings.Pronoun.allCases) { Text($0.title).tag($0.rawValue) }
						}
						.labelsHidden().frame(maxWidth: 200)
					}
				}
				Text("Personality").font(.system(size: 12)).foregroundStyle(Folio.meta).padding(.top, 6)
				HStack(spacing: 10) {
					ForEach(SecretarySettings.Personality.allCases) { p in
						Button { personality = p.rawValue } label: {
							VStack(alignment: .leading, spacing: 4) {
								Text(p.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Folio.ink)
								Text(p.sample).font(.system(size: 12)).foregroundStyle(Folio.body).fixedSize(horizontal: false, vertical: true)
							}
							.padding(12)
							.frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
							.background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(personality == p.rawValue ? Folio.accentSoft : Folio.card))
							.overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
								.strokeBorder(personality == p.rawValue ? Folio.accent : Folio.line, lineWidth: personality == p.rawValue ? 2 : 1))
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
						.accessibilityAddTraits(personality == p.rawValue ? .isSelected : [])
					}
				}
			}

			SecretaryGroup("How hands-on") {
				PickerRow("Sort new mail", selection: $sortMode, options: SecretarySettings.SortMode.allCases.map { ($0.rawValue, $0.title) })
				PickerRow("Heads-ups about what's coming", selection: $headsUp, options: SecretarySettings.HeadsUp.allCases.map { ($0.rawValue, $0.title) })
				ToggleRow("Ask from anywhere with ⌥ Space", "Also in the menu bar and at the top of the sidebar.", $askShortcut)
					.onChange(of: askShortcut) { _, on in
						if on { AskPanelController.shared.install(store: store) } else { AskPanelController.shared.uninstall() }
					}
				Text("Reply drafts are written only when you press Draft it for me.").font(.system(size: 12)).foregroundStyle(Folio.meta)
			}

			SecretaryGroup("What may happen without asking") {
				ToggleRow("Move a conversation to Waiting when I reply", "From any device: your phone, the web or here.", $autoWaiting)
				ToggleRow("Bring it back to Needs you when they answer", "", $autoBack)
				ToggleRow("Add notebook rules without asking me first", "Otherwise \(SecretarySettings.name) asks once: Yes, remember, or Just this once.", $autoRemember)
				ToggleRow("File and archive with rules I've approved", "Mail that matches an approved folder rule is filed as it arrives, without a stop on the Desk.", $autoFile)
				Text("Sending, deleting and unsubscribing always wait for you. They can't be switched on.")
					.font(.system(size: 12)).foregroundStyle(Folio.meta)
			}
		}
	}
}

/// Settings › Desk, trays and Library.
struct DeskSettingsPage: View {
	@AppStorage(SecretarySettings.chaseDaysKey) private var chaseDays = 3
	@AppStorage("library.defaultMode") private var libraryDefault = LibraryMode.table.rawValue
	@State private var names: [String: String] = Dictionary(uniqueKeysWithValues: ThreadStatus.allCases.map {
		($0.rawValue, UserDefaults.standard.string(forKey: "tray.name.\($0.rawValue)") ?? "")
	})

	var body: some View {
		VStack(alignment: .leading, spacing: 28) {
			PageTitle("Desk, trays and Library", "Name the trays your way and choose how the Library shows your folders.")

			SecretaryGroup("Trays") {
				ForEach(ThreadStatus.allCases) { status in
					HStack(spacing: 12) {
						StatusDot(status: status)
						Text(status.defaultTitle).font(.system(size: 14)).foregroundStyle(Folio.body).frame(width: 150, alignment: .leading)
						TextField("Your name for it", text: Binding(
							get: { names[status.rawValue] ?? "" },
							set: { names[status.rawValue] = $0; UserDefaults.standard.set($0, forKey: "tray.name.\(status.rawValue)") }
						))
						.textFieldStyle(.roundedBorder).frame(maxWidth: 220)
					}
				}
				Stepper("Flag a Waiting conversation after \(chaseDays) day\(chaseDays == 1 ? "" : "s") without an answer", value: $chaseDays, in: 1...21)
					.font(.system(size: 14)).padding(.top, 6)
			}

			SecretaryGroup("Library") {
				PickerRow("New folders open as", selection: $libraryDefault, options: LibraryMode.allCases.map { ($0.rawValue, $0.title) })
				Text("Your own folders and labels are the Library. Switch any one folder between Table, Cards and List from its header.")
					.font(.system(size: 12)).foregroundStyle(Folio.meta)
			}
		}
	}
}

/// Settings › Notebook: what the secretary has learned, editable, and the approved folder rules.
struct NotebookPage: View {
	@State private var newNote = ""
	@State private var editing: String?
	@State private var editText = ""
	@State private var confirmClear = false

	private var notebook: Notebook { Notebook.shared }

	var body: some View {
		VStack(alignment: .leading, spacing: 24) {
			PageTitle("\(SecretarySettings.possessive) notebook", "\(SecretarySettings.name) reads this before every sort and every answer. Edit or forget anything.")

			HStack(spacing: 10) {
				TextField("Tell \(SecretarySettings.name) something, e.g. Invoices over $500 always need me", text: $newNote)
					.textFieldStyle(.roundedBorder)
					.onSubmit(add)
				Button("Add", action: add).buttonStyle(FolioFilledButtonStyle(fill: Folio.dark, ink: Folio.onDark, height: 30))
			}

			VStack(spacing: 0) {
				ForEach(notebook.entries) { entry in
					Rectangle().fill(Folio.line).frame(height: 1)
					HStack(spacing: 12) {
						if editing == entry.id {
							TextField("", text: $editText).textFieldStyle(.roundedBorder).onSubmit { save(entry) }
							Button("Save") { save(entry) }.buttonStyle(FolioOutlineButtonStyle(height: 28))
						} else {
							VStack(alignment: .leading, spacing: 2) {
								Text(entry.text).font(.system(size: 14)).foregroundStyle(Folio.ink)
								Text(entry.confirmations > 0 ? "\(entry.source) · you confirmed it \(entry.confirmations) time\(entry.confirmations == 1 ? "" : "s")" : entry.source)
									.font(.system(size: 12)).foregroundStyle(Folio.meta)
							}
							Spacer(minLength: 8)
							Button("Edit") { editing = entry.id; editText = entry.text }.buttonStyle(FolioOutlineButtonStyle(height: 28))
							Button("Forget") { notebook.remove(entry) }.buttonStyle(FolioOutlineButtonStyle(height: 28))
						}
					}
					.padding(.vertical, 10)
				}
				ForEach(Automation.shared.rules) { rule in
					Rectangle().fill(Folio.line).frame(height: 1)
					HStack(spacing: 12) {
						VStack(alignment: .leading, spacing: 2) {
							Text("\(rule.label) → To file: \(rule.folderName)").font(.system(size: 14)).foregroundStyle(Folio.ink)
							Text("Folder rule you approved").font(.system(size: 12)).foregroundStyle(Folio.meta)
						}
						Spacer(minLength: 8)
						Button("Forget") { Automation.shared.removeRule(rule) }.buttonStyle(FolioOutlineButtonStyle(height: 28))
					}
					.padding(.vertical, 10)
				}
				Rectangle().fill(Folio.line).frame(height: 1)
			}

			HStack(spacing: 10) {
				Button("Export…", action: export).buttonStyle(FolioOutlineButtonStyle(height: 32))
				Button("Start fresh…") { confirmClear = true }.buttonStyle(FolioOutlineButtonStyle(height: 32))
			}
			.confirmationDialog("Forget everything in the notebook?", isPresented: $confirmClear) {
				Button("Forget everything", role: .destructive) { notebook.removeAll() }
			} message: {
				Text("\(SecretarySettings.name) will sort from scratch. Approved folder rules stay.")
			}
		}
	}

	private func add() {
		notebook.addInstruction(newNote)
		newNote = ""
	}

	private func save(_ entry: NotebookEntry) {
		var e = entry
		e.text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
		if !e.text.isEmpty { notebook.update(e) }
		editing = nil
	}

	private func export() {
		let panel = NSSavePanel()
		panel.nameFieldStringValue = "\(SecretarySettings.possessive) notebook.txt"
		panel.allowedContentTypes = [.plainText]
		guard panel.runModal() == .OK, let url = panel.url else { return }
		try? notebook.exportText.write(to: url, atomically: true, encoding: .utf8)
	}
}

// MARK: Building blocks

private struct PageTitle: View {
	var title: String
	var detail: String
	init(_ title: String, _ detail: String) { self.title = title; self.detail = detail }

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(title).font(.system(size: 30, weight: .bold)).tracking(-1).foregroundStyle(Folio.ink)
			Text(detail).font(.system(size: 14)).lineSpacing(3).foregroundStyle(Folio.body).fixedSize(horizontal: false, vertical: true)
		}
	}
}

private struct SecretaryGroup<Content: View>: View {
	var title: String
	var content: Content
	init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Folio.ink)
			content
		}
	}
}

private struct ToggleRow: View {
	var title: String
	var detail: String
	@Binding var isOn: Bool
	init(_ title: String, _ detail: String, _ isOn: Binding<Bool>) { self.title = title; self.detail = detail; _isOn = isOn }

	var body: some View {
		HStack(spacing: 16) {
			VStack(alignment: .leading, spacing: 2) {
				Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Folio.ink)
				if !detail.isEmpty { Text(detail).font(.system(size: 12)).foregroundStyle(Folio.meta).fixedSize(horizontal: false, vertical: true) }
			}
			Spacer(minLength: 12)
			Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(Folio.accent)
		}
	}
}

private struct PickerRow: View {
	var title: String
	@Binding var selection: String
	var options: [(String, String)]
	init(_ title: String, selection: Binding<String>, options: [(String, String)]) { self.title = title; _selection = selection; self.options = options }

	var body: some View {
		HStack(spacing: 16) {
			Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Folio.ink)
			Spacer(minLength: 12)
			Picker("", selection: $selection) {
				ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
			}
			.labelsHidden().frame(maxWidth: 240)
		}
	}
}
