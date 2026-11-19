import AppKit
import SwiftUI

/// The colours of the SuperMail mockups (Today, Inbox, Status board, Assistant, Accounts), so every
/// screen draws from the same values. Dark mode has matching shades.
enum Folio {
	static let ink = AppTheme.adaptive(dark: 0xF1F3F7, light: NSColor(rgb: 0x12141A))
	static let body = AppTheme.adaptive(dark: 0xC5CAD6, light: NSColor(rgb: 0x3A4152))
	static let meta = AppTheme.adaptive(dark: 0x9AA2B3, light: NSColor(rgb: 0x5B6376))
	static let line = AppTheme.adaptive(dark: 0x2C3039, light: NSColor(rgb: 0xE2E6EE))
	static let softLine = AppTheme.adaptive(dark: 0x262A32, light: NSColor(rgb: 0xE9ECF2))
	static let sidebar = AppTheme.adaptive(dark: 0x16181D, light: NSColor(rgb: 0xF3F5F9))
	static let card = AppTheme.adaptive(dark: 0x1D2026, light: NSColor(rgb: 0xFFFFFF))
	static let soft = AppTheme.adaptive(dark: 0x1A1C21, light: NSColor(rgb: 0xFAFBFD))
	static let chip = AppTheme.adaptive(dark: 0x262A32, light: NSColor(rgb: 0xF3F5F9))
	static let selection = AppTheme.adaptive(dark: 0x1E2748, light: NSColor(rgb: 0xE3EAFF))
	static let selectionInk = AppTheme.adaptive(dark: 0xA9BBFF, light: NSColor(rgb: 0x1F3FB8))
	static let accent = AppTheme.adaptive(dark: 0x5B7BFF, light: NSColor(rgb: 0x2F5BFF))
	static let accentStroke = AppTheme.adaptive(dark: 0x34407A, light: NSColor(rgb: 0xC9D3F5))
	static let accentSoft = AppTheme.adaptive(dark: 0x1A2038, light: NSColor(rgb: 0xF7F9FF))
	static let dark = AppTheme.adaptive(dark: 0xF1F3F7, light: NSColor(rgb: 0x12141A))
	static let onDark = AppTheme.adaptive(dark: 0x12141A, light: NSColor(rgb: 0xFFFFFF))
	static let connectedFill = AppTheme.adaptive(dark: 0x12332A, light: NSColor(rgb: 0xDDF5EC))
	static let connectedInk = AppTheme.adaptive(dark: 0x8FE3C3, light: NSColor(rgb: 0x0A6B4F))
	static let connectedDot = AppTheme.adaptive(dark: 0x3DCB9C, light: NSColor(rgb: 0x0F9B72))
}

extension ThreadStatus {
	/// The Today tile behind the count.
	var tileFill: Color {
		switch self {
		case .needsReply: AppTheme.adaptive(dark: 0x1B2342, light: NSColor(rgb: 0xEEF2FF))
		case .waiting: AppTheme.adaptive(dark: 0x33260F, light: NSColor(rgb: 0xFFF6E6))
		case .canArchive: AppTheme.adaptive(dark: 0x23262D, light: NSColor(rgb: 0xF3F5F9))
		case .longTerm: AppTheme.adaptive(dark: 0x112D25, light: NSColor(rgb: 0xEAF8F2))
		}
	}

	var tileStroke: Color {
		switch self {
		case .needsReply: AppTheme.adaptive(dark: 0x2D3B70, light: NSColor(rgb: 0xD6E0FF))
		case .waiting: AppTheme.adaptive(dark: 0x5A4219, light: NSColor(rgb: 0xF8DFB5))
		case .canArchive: AppTheme.adaptive(dark: 0x343842, light: NSColor(rgb: 0xE2E6EE))
		case .longTerm: AppTheme.adaptive(dark: 0x1F5544, light: NSColor(rgb: 0xC7EBDD))
		}
	}

	/// The outline of a row's button (Reply, Follow up).
	var actionStroke: Color {
		switch self {
		case .needsReply: Folio.accentStroke
		case .waiting: AppTheme.adaptive(dark: 0x6B4E1C, light: NSColor(rgb: 0xF0CF98))
		default: Folio.line
		}
	}

	/// The circle behind a sender's initials.
	var avatarFill: Color {
		switch self {
		case .needsReply: Folio.selection
		case .waiting: AppTheme.adaptive(dark: 0x3A2A12, light: NSColor(rgb: 0xFFEFD1))
		default: tint
		}
	}

	/// The dashed drop target on the board.
	var dropFill: Color {
		switch self {
		case .needsReply: AppTheme.adaptive(dark: 0x18203A, light: NSColor(rgb: 0xF5F8FF))
		case .waiting: AppTheme.adaptive(dark: 0x2E220E, light: NSColor(rgb: 0xFFFAF0))
		case .canArchive: AppTheme.adaptive(dark: 0x202329, light: NSColor(rgb: 0xF8F9FB))
		case .longTerm: AppTheme.adaptive(dark: 0x0F2720, light: NSColor(rgb: 0xF2FBF7))
		}
	}

	var dropStroke: Color {
		switch self {
		case .needsReply: AppTheme.adaptive(dark: 0x4A62C0, light: NSColor(rgb: 0x9DB1FF))
		case .waiting: AppTheme.adaptive(dark: 0x8A6420, light: NSColor(rgb: 0xE3B567))
		case .canArchive: AppTheme.adaptive(dark: 0x5A606C, light: NSColor(rgb: 0xB9BFCC))
		case .longTerm: AppTheme.adaptive(dark: 0x2A7A60, light: NSColor(rgb: 0x8FD6BB))
		}
	}
}

/// Initials in a circle, as the mockups draw senders: "Mira Chen" → "MC".
struct InitialsAvatar: View {
	var name: String
	var fill: Color
	var ink: Color
	var size: CGFloat = 36

	private var initials: String {
		let words = name.replacingOccurrences(of: "\"", with: "").split { $0 == " " || $0 == "." || $0 == "_" }.filter { !$0.isEmpty }
		let letters = words.prefix(2).compactMap { $0.first.map(String.init) }
		let text = letters.joined().uppercased()
		return text.isEmpty ? "?" : text
	}

	var body: some View {
		Text(initials)
			.font(.system(size: size * 0.36, weight: .semibold))
			.foregroundStyle(ink)
			.frame(width: size, height: size)
			.background(Circle().fill(fill))
	}
}

/// The mockups' outlined button: white, a hairline border, semibold text.
struct FolioOutlineButtonStyle: ButtonStyle {
	var ink: Color = Folio.body
	var stroke: Color = Folio.line
	var height: CGFloat = 40
	var fullWidth = false
	@Environment(\.isEnabled) private var isEnabled

	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.system(size: 14, weight: .semibold))
			.foregroundStyle(ink)
			.padding(.horizontal, 16)
			.frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height, maxHeight: height)
			.background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Folio.card))
			.overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(stroke, lineWidth: 1))
			.contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
			.opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.7 : 1)
	}
}

/// The mockups' filled button: blue by default, or near-black for Sort unsorted mail.
struct FolioFilledButtonStyle: ButtonStyle {
	var fill: Color = Folio.accent
	var ink: Color = .white
	var height: CGFloat = 40
	@Environment(\.isEnabled) private var isEnabled

	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.system(size: 14, weight: .semibold))
			.foregroundStyle(ink)
			.padding(.horizontal, 18)
			.frame(minHeight: height, maxHeight: height)
			.background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill))
			.contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
			.opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.7 : 1)
	}
}
