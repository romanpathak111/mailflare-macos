import Foundation

/// MCP servers already set up in Codex (~/.codex/config.toml) or Claude Code (~/.claude.json) on this
/// Mac. When the assistant runs through that CLI, the servers the user switches on here are loaded
/// for it and their tools pre-approved; every other one stays off. All are off until switched on,
/// since some can change data or send messages.
enum LocalMCP {
	static func servers(for cli: LocalCLI) -> [String] {
		let home = FileManager.default.homeDirectoryForCurrentUser
		switch cli {
		case .codex:
			guard let text = try? String(contentsOf: home.appendingPathComponent(".codex/config.toml"), encoding: .utf8) else { return [] }
			var names: [String] = []
			for line in text.split(separator: "\n") {
				let trimmed = line.trimmingCharacters(in: .whitespaces)
				guard trimmed.hasPrefix("[mcp_servers."), trimmed.hasSuffix("]") else { continue }
				var name = String(trimmed.dropFirst("[mcp_servers.".count).dropLast())
				// "[mcp_servers.x.env]" and the like belong to x.
				if name.hasPrefix("\"") { name = String(name.dropFirst().prefix { $0 != "\"" }) } else { name = String(name.prefix { $0 != "." }) }
				if !name.isEmpty, !names.contains(name) { names.append(name) }
			}
			return names
		case .claude:
			guard let data = try? Data(contentsOf: home.appendingPathComponent(".claude.json")),
				  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
				  let servers = json["mcpServers"] as? [String: Any] else { return [] }
			return servers.keys.sorted()
		}
	}

	private static func key(_ cli: LocalCLI) -> String { "localMCP.\(cli.rawValue)" }

	static func enabled(for cli: LocalCLI) -> Set<String> {
		Set(UserDefaults.standard.stringArray(forKey: key(cli)) ?? [])
	}

	static func set(_ name: String, on: Bool, for cli: LocalCLI) {
		var current = enabled(for: cli)
		if on { current.insert(name) } else { current.remove(name) }
		UserDefaults.standard.set(current.sorted(), forKey: key(cli))
	}

	/// TOML key text for a server name: bare when it can be, quoted otherwise.
	static func tomlKey(_ name: String) -> String {
		name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } ? name : "\"\(name.replacingOccurrences(of: "\"", with: ""))\""
	}

	/// Claude Code's permission name for all tools of a server: mcp__<name>.
	static func claudeToolPrefix(_ name: String) -> String {
		"mcp__" + String(name.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" ? $0 : "_" })
	}
}
