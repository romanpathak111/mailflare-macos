import AppKit
import SwiftUI

/// What a conversation needs from the user. Every status has one colour, used the same way in the
/// sidebar, the message list, the reader, Today and the Status board.
enum ThreadStatus: String, CaseIterable, Codable, Identifiable {
	case needsReply, waiting, longTerm, canArchive

	var id: String { rawValue }

	/// The tray's name: the user's own from Settings › Desk, or the standard one.
	var title: String { Self.customName(self) ?? defaultTitle }

	static func customName(_ status: ThreadStatus) -> String? {
		let n = (UserDefaults.standard.string(forKey: "tray.name.\(status.rawValue)") ?? "").trimmingCharacters(in: .whitespaces)
		return n.isEmpty ? nil : n
	}

	var defaultTitle: String {
		switch self {
		case .needsReply: "Needs you"
		case .waiting: "Waiting on others"
		case .canArchive: "Can archive"
		case .longTerm: "To file"
		}
	}

	/// For tight places: filter chips and the message list.
	var shortTitle: String {
		if let custom = Self.customName(self) { return custom }
		switch self {
		case .needsReply: return "Needs you"
		case .waiting: return "Waiting"
		case .canArchive: return "Can archive"
		case .longTerm: return "To file"
		}
	}

	/// The dot, and the colour of anything drawn as a mark.
	var dot: Color {
		switch self {
		case .needsReply: AppTheme.adaptive(dark: 0x6F8CFF, light: NSColor(rgb: 0x2F5BFF))
		case .waiting: AppTheme.adaptive(dark: 0xF0A63A, light: NSColor(rgb: 0xD9820B))
		case .canArchive: AppTheme.adaptive(dark: 0x9AA2B3, light: NSColor(rgb: 0x7A8294))
		case .longTerm: AppTheme.adaptive(dark: 0x3DCB9C, light: NSColor(rgb: 0x0F9B72))
		}
	}

	/// The soft fill behind a chip, a tile or a column heading.
	var tint: Color {
		switch self {
		case .needsReply: AppTheme.adaptive(dark: 0x1E2748, light: NSColor(rgb: 0xE8EEFF))
		case .waiting: AppTheme.adaptive(dark: 0x3A2A12, light: NSColor(rgb: 0xFFF1DB))
		case .canArchive: AppTheme.adaptive(dark: 0x2A2D35, light: NSColor(rgb: 0xEEF0F4))
		case .longTerm: AppTheme.adaptive(dark: 0x12332A, light: NSColor(rgb: 0xDDF5EC))
		}
	}

	/// Text on `tint`: dark enough to read at small sizes.
	var ink: Color {
		switch self {
		case .needsReply: AppTheme.adaptive(dark: 0xA9BBFF, light: NSColor(rgb: 0x1F3FB8))
		case .waiting: AppTheme.adaptive(dark: 0xF7C57A, light: NSColor(rgb: 0x8A4B00))
		case .canArchive: AppTheme.adaptive(dark: 0xC7CCD8, light: NSColor(rgb: 0x454C5C))
		case .longTerm: AppTheme.adaptive(dark: 0x8FE3C3, light: NSColor(rgb: 0x0A6B4F))
		}
	}

	/// The icon of the status in menus.
	var icon: AppIcon {
		switch self {
		case .needsReply: .reply
		case .waiting: .clock
		case .canArchive: .archive
		case .longTerm: .bookmark
		}
	}

	/// What the assistant is told about each status.
	var meaning: String {
		switch self {
		case .needsReply: "the user must act: answer, decide, sign, pay or read something closely"
		case .waiting: "the user already answered and is waiting for the other person"
		case .canArchive: "nothing to do: newsletters, receipts, notifications, finished threads"
		case .longTerm: "nothing to do now but worth keeping in a folder: receipts, invoices, statements, certificates, contracts, references"
		}
	}
}

/// The inbox filter in the message list's header.
enum StatusFilter: String, CaseIterable, Identifiable {
	case all, needsReply, waiting, unsorted

	var id: String { rawValue }

	var title: String {
		switch self {
		case .all: "All"
		case .needsReply: "Needs you"
		case .waiting: "Waiting"
		case .unsorted: "Unsorted"
		}
	}

	var status: ThreadStatus? {
		switch self {
		case .needsReply: .needsReply
		case .waiting: .waiting
		default: nil
		}
	}
}

/// Which full-width screen the main card shows. `mail` is the usual list and reader.
enum AppScreen: Equatable {
	case home, board, mail
	/// One account's section of the Library.
	case shelf(String)
}

/// What a Needs you conversation asks of the user, shown as a small tag beside it.
enum NeedKind: String, CaseIterable, Codable, Identifiable {
	case reply, decide, sign, pay, read

	var id: String { rawValue }
	var title: String { rawValue.capitalized }
}
