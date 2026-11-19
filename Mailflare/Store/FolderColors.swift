import AppKit
import SwiftUI
import Observation

/// The colour of each folder's icon in the sidebar. A folder keeps the colour the user chose; one
/// that was never coloured gets a stable one from its id, so folders look different from the start.
@MainActor
@Observable
final class FolderColors {
	struct Swatch: Identifiable {
		var name: String
		var color: Color
		var id: String { name }
	}

	static let swatches: [Swatch] = [
		Swatch(name: "Indigo", color: AppTheme.adaptive(dark: 0x9C94FF, light: NSColor(rgb: 0x5B4FD8))),
		Swatch(name: "Teal", color: AppTheme.adaptive(dark: 0x3FC3CD, light: NSColor(rgb: 0x0E7C86))),
		Swatch(name: "Rust", color: AppTheme.adaptive(dark: 0xF0935B, light: NSColor(rgb: 0xB4531E))),
		Swatch(name: "Berry", color: AppTheme.adaptive(dark: 0xF076A8, light: NSColor(rgb: 0x9A1F52))),
		Swatch(name: "Green", color: AppTheme.adaptive(dark: 0x3DCB9C, light: NSColor(rgb: 0x0F9B72))),
		Swatch(name: "Blue", color: AppTheme.adaptive(dark: 0x6F8CFF, light: NSColor(rgb: 0x2F5BFF))),
		Swatch(name: "Slate", color: AppTheme.adaptive(dark: 0x9AA2B3, light: NSColor(rgb: 0x5B6376))),
	]

	private static let key = "folderColors"
	private(set) var chosen: [String: Int]

	init() {
		chosen = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: Int] ?? [:]
	}

	func index(for folderID: String) -> Int {
		if let saved = chosen[folderID], Self.swatches.indices.contains(saved) { return saved }
		// djb2: the same folder always lands on the same swatch.
		let hash = folderID.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
		return abs(hash % Self.swatches.count)
	}

	func color(for folderID: String) -> Color { Self.swatches[index(for: folderID)].color }

	func set(_ index: Int, for folderID: String) {
		guard Self.swatches.indices.contains(index) else { return }
		chosen[folderID] = index
		UserDefaults.standard.set(chosen, forKey: Self.key)
	}
}
