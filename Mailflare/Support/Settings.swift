import Foundation
import ServiceManagement

/// The pages of the Settings view, listed in the sidebar in this order.
enum SettingsPage: String, CaseIterable, Identifiable {
	case general, accounts, secretary, desk, notebook, assistant, ai, mcp, notifications, license, support, about

	var id: String { rawValue }

	var title: String {
		switch self {
		case .general: "Preferences"
		case .notifications: "Notifications"
		case .accounts: "Accounts and folders"
		case .secretary: "Secretary"
		case .desk: "Desk, trays and Library"
		case .notebook: "Notebook"
		case .assistant: "AI engine and privacy"
		case .ai: "AI Providers"
		case .mcp: "MCP Credentials"
		case .license: "License"
		case .support: "Support"
		case .about: "Version"
		}
	}

	var icon: AppIcon {
		switch self {
		case .general: .settings
		case .notifications: .bell
		case .accounts: .allInboxes
		case .secretary: .person
		case .desk: .inbox
		case .notebook: .bookmark
		case .assistant: .aiContent
		case .ai: .sparkles
		case .mcp: .link
		case .license: .vip
		case .support: .support
		case .about: .info
		}
	}
}

/// How the sidebar groups the pages while Settings is open.
enum SettingsSection: CaseIterable, Identifiable {
	case general, about

	var id: Self { self }

	var title: String {
		switch self {
		case .general: "General"
		case .about: "About"
		}
	}

	var pages: [SettingsPage] {
		switch self {
		case .general: [.secretary, .desk, .notebook, .assistant, .general, .accounts, .notifications, .ai, .mcp]
		case .about: [.support, .about]
		}
	}
}

/// What the assistant may do with statuses; the Assistant page sets each.
enum AssistantSettings {
	static let suggestStatusKey = "assistant.suggestStatus"
	static let draftRepliesKey = "assistant.draftReplies"
	static let todayBriefKey = "assistant.todayBrief"
	static let autoArchiveKey = "assistant.autoArchive"
	static let suggestFoldersKey = "assistant.suggestFolders"

	private static func flag(_ key: String, default value: Bool) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? value }

	/// Suggest a status for the open message and when sorting new mail.
	static var suggestStatus: Bool { flag(suggestStatusKey, default: true) }
	/// Offer folder rules learned from where the user files mail.
	static var suggestFolders: Bool { flag(suggestFoldersKey, default: true) }
	/// Offer to draft a reply for conversations that need one.
	static var draftReplies: Bool { flag(draftRepliesKey, default: true) }
	/// Show the assistant's card on Today.
	static var todayBrief: Bool { flag(todayBriefKey, default: true) }
	/// Move Can archive conversations to Archive as soon as they are sorted.
	static var autoArchive: Bool { flag(autoArchiveKey, default: false) }
}

/// Keys and defaults of the preferences that code outside the Settings view reads.
enum ReadingSettings {
	static let markReadDelayKey = "markReadDelay"
	static let loadRemoteContentKey = "loadRemoteContent"
	static let autoCheckUpdatesKey = "autoCheckUpdates"
	static let showAvatarsKey = "showListAvatars"

	/// Whether the message list shows a sender avatar beside each row.
	static var showAvatars: Bool { UserDefaults.standard.object(forKey: showAvatarsKey) as? Bool ?? true }

	/// Seconds before an opened message is marked read: 0 at once, -1 never.
	static var markReadDelay: Int { UserDefaults.standard.object(forKey: markReadDelayKey) as? Int ?? 0 }
	static var autoCheckUpdates: Bool { UserDefaults.standard.object(forKey: autoCheckUpdatesKey) as? Bool ?? true }
}

enum LaunchAtLogin {
	static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

	/// Registers or removes the login item; returns whether the system now agrees.
	@discardableResult
	static func set(_ enabled: Bool) -> Bool {
		do {
			if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
		} catch {}
		return isEnabled == enabled
	}
}
