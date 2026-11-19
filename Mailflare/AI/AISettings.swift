import Foundation
import Observation
import Security

/// The services the assistant can talk to. The first two run the Claude Code or Codex CLI on this
/// Mac with the user's own login; the rest speak the OpenAI chat-completions protocol (Anthropic
/// through its compatibility endpoint), so one client serves them all.
enum AIProviderPreset: String, CaseIterable, Identifiable, Codable {
	case claudeCLI = "claude-cli", codexCLI = "codex-cli"
	case openai, anthropic, openrouter, groq, deepseek, cloudflare, ollama, custom

	var id: String { rawValue }

	var title: String {
		switch self {
		case .claudeCLI: "Claude Code (this Mac)"
		case .codexCLI: "Codex (this Mac)"
		case .openai: "OpenAI"
		case .anthropic: "Anthropic"
		case .openrouter: "OpenRouter"
		case .groq: "Groq"
		case .deepseek: "DeepSeek"
		case .cloudflare: "Cloudflare Workers AI"
		case .ollama: "Ollama (local)"
		case .custom: "Custom (OpenAI-compatible)"
		}
	}

	var baseURL: String {
		switch self {
		case .openai: "https://api.openai.com/v1"
		case .anthropic: "https://api.anthropic.com/v1"
		case .openrouter: "https://openrouter.ai/api/v1"
		case .groq: "https://api.groq.com/openai/v1"
		case .deepseek: "https://api.deepseek.com/v1"
		// Needs the account id: see `AIProviderConfig.baseURLString`.
		case .cloudflare: ""
		case .ollama: "http://localhost:11434/v1"
		case .custom, .claudeCLI, .codexCLI: ""
		}
	}

	var defaultModel: String {
		switch self {
		case .openai: "gpt-4.1-mini"
		case .anthropic: "claude-sonnet-5-5"
		case .openrouter: "openai/gpt-4.1-mini"
		case .groq: "llama-3.3-70b-versatile"
		case .deepseek: "deepseek-chat"
		case .cloudflare: "@cf/meta/llama-3.3-70b-instruct-fp8-fast"
		case .ollama: "llama3.1"
		case .custom: ""
		case .claudeCLI, .codexCLI: localCLI?.defaultModel ?? ""
		}
	}

	/// The CLI behind a "this Mac" preset.
	var localCLI: LocalCLI? {
		switch self {
		case .claudeCLI: .claude
		case .codexCLI: .codex
		default: nil
		}
	}

	/// Ollama and the CLIs run on this Mac and take no key.
	var needsKey: Bool { self != .ollama && localCLI == nil }
}

/// One configured provider: a preset (or custom address), a model and, in the Keychain, a key.
struct AIProviderConfig: Identifiable, Codable, Equatable {
	var id = UUID().uuidString
	var preset: AIProviderPreset
	var name: String
	var customBaseURL = ""
	/// The Cloudflare account that Workers AI requests go through.
	var cloudflareAccountID: String?
	var model: String
	/// Model ids the provider listed the last time "Load Models" ran.
	var models: [String] = []

	init(preset: AIProviderPreset) {
		self.preset = preset
		name = preset.title
		model = preset.defaultModel
		models = preset.localCLI?.models ?? []
	}

	var baseURLString: String {
		switch preset {
		case .custom: customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
		case .cloudflare:
			(cloudflareAccountID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ""
				: "https://api.cloudflare.com/client/v4/accounts/\((cloudflareAccountID ?? "").trimmingCharacters(in: .whitespacesAndNewlines))/ai/v1"
		default: preset.baseURL
		}
	}

	var baseURL: URL? {
		var s = baseURLString
		while s.hasSuffix("/") { s.removeLast() }
		guard let url = URL(string: s), ["http", "https"].contains(url.scheme ?? ""), url.host != nil else { return nil }
		return url
	}

	/// Models to offer: the listed ones, or just the chosen one.
	var choices: [String] {
		let current = model.trimmingCharacters(in: .whitespaces)
		return models.isEmpty ? (current.isEmpty ? [] : [current]) : (models.contains(current) || current.isEmpty ? models : [current] + models)
	}
}

/// The providers the assistant can use, and which one (and model) is active. Keys live in the
/// Keychain under each provider's id; the rest is JSON in UserDefaults.
@MainActor
@Observable
final class AISettings {
	private enum Keys {
		static let providers = "ai.providers"
		static let active = "ai.activeProvider"
		static let instructions = "ai.instructions"
		static let writer = "ai.writerModel"
		static let writerInstructions = "ai.writerInstructions"
		static let localAdded = "ai.localProvidersAdded"
	}

	private(set) var providers: [AIProviderConfig]
	private(set) var activeID: String?
	private var keys: [String: String] = [:]
	/// The user's own prompt for the assistant (tone, sign-off), added to its instructions.
	var instructions: String {
		didSet { UserDefaults.standard.set(instructions, forKey: Keys.instructions) }
	}
	/// The same for AI Writer in the composer.
	var writerInstructions: String {
		didSet { UserDefaults.standard.set(writerInstructions, forKey: Keys.writerInstructions) }
	}

	/// A provider and one of its models, as picked for a feature.
	struct ModelChoice: Codable, Equatable {
		var providerID: String
		var model: String
	}

	/// The model AI Writer uses; nil follows the assistant's model.
	private(set) var writerChoice: ModelChoice?

	init() {
		let defaults = UserDefaults.standard
		writerChoice = defaults.data(forKey: Keys.writer).flatMap { try? JSONDecoder().decode(ModelChoice.self, from: $0) }
		instructions = defaults.string(forKey: Keys.instructions) ?? ""
		writerInstructions = defaults.string(forKey: Keys.writerInstructions) ?? ""
		if let data = defaults.data(forKey: Keys.providers), let saved = try? JSONDecoder().decode([AIProviderConfig].self, from: data) {
			providers = saved
		} else {
			providers = Self.migrateSingleProvider(defaults)
		}
		for p in providers { if let key = AIKeychain.load(p.id) { keys[p.id] = key } }
		let chosen = defaults.string(forKey: Keys.active)
		activeID = providers.contains { $0.id == chosen } ? chosen : providers.first?.id
		if defaults.data(forKey: Keys.providers) == nil, !providers.isEmpty { persist() }
		addLocalProvidersOnce()
	}

	/// The first time, connects Claude Code and Codex when they are installed, and uses one of them,
	/// so the assistant works through the user's own logins without an API key.
	private func addLocalProvidersOnce() {
		let defaults = UserDefaults.standard
		guard !defaults.bool(forKey: Keys.localAdded) else { return }
		defaults.set(true, forKey: Keys.localAdded)
		var added: [AIProviderConfig] = []
		for preset in [AIProviderPreset.claudeCLI, .codexCLI] where preset.localCLI?.isInstalled == true && !providers.contains(where: { $0.preset == preset }) {
			let config = AIProviderConfig(preset: preset)
			providers.append(config)
			added.append(config)
		}
		guard !added.isEmpty else { return }
		// Prefer Codex, then Claude Code, over any API provider set up before.
		activeID = (added.first { $0.preset == .codexCLI } ?? added[0]).id
		persist()
	}

	/// The first version kept one setting per preset; each one that had a key becomes a provider.
	private static func migrateSingleProvider(_ defaults: UserDefaults) -> [AIProviderConfig] {
		AIProviderPreset.allCases.compactMap { preset in
			guard let key = AIKeychain.load(preset.rawValue) else { return nil }
			var config = AIProviderConfig(preset: preset)
			if let model = defaults.string(forKey: "ai.model.\(preset.rawValue)") { config.model = model }
			if preset == .custom { config.customBaseURL = defaults.string(forKey: "ai.customBaseURL") ?? "" }
			_ = AIKeychain.save(config.id, key)
			return config
		}
	}

	private func persist() {
		let defaults = UserDefaults.standard
		defaults.set(try? JSONEncoder().encode(providers), forKey: Keys.providers)
		defaults.set(activeID, forKey: Keys.active)
	}

	func apiKey(for id: String) -> String { keys[id] ?? "" }

	func isReady(_ config: AIProviderConfig) -> Bool {
		if let cli = config.preset.localCLI { return cli.isInstalled && !config.model.trimmingCharacters(in: .whitespaces).isEmpty }
		return config.baseURL != nil && !config.model.trimmingCharacters(in: .whitespaces).isEmpty
			&& (!config.preset.needsKey || !apiKey(for: config.id).isEmpty)
	}

	var readyProviders: [AIProviderConfig] { providers.filter(isReady) }

	/// Whether the assistant can be used at all: some provider is complete.
	var isConfigured: Bool { !readyProviders.isEmpty }

	var active: AIProviderConfig? {
		readyProviders.first { $0.id == activeID } ?? readyProviders.first
	}

	var client: AIClient? {
		guard let active else { return nil }
		return makeClient(active, model: active.model)
	}

	/// A client for a ready provider and model: the CLI for a "this Mac" provider, else HTTP.
	private func makeClient(_ provider: AIProviderConfig, model: String) -> AIClient? {
		let model = model.trimmingCharacters(in: .whitespaces)
		if let cli = provider.preset.localCLI { return .local(cli, model: model) }
		guard let baseURL = provider.baseURL else { return nil }
		return AIClient(baseURL: baseURL, apiKey: apiKey(for: provider.id), model: model)
	}

	/// The client for AI Writer: its own model when one is chosen and still usable, else the assistant's.
	var writerClient: AIClient? {
		guard let choice = writerChoice, let provider = readyProviders.first(where: { $0.id == choice.providerID }),
			  !choice.model.trimmingCharacters(in: .whitespaces).isEmpty
		else { return client }
		return makeClient(provider, model: choice.model) ?? client
	}

	/// The client for `model` on a provider, when both are set and usable; otherwise AI Writer's.
	func writerClient(providerID: String?, model: String?) -> AIClient? {
		guard let providerID, let model = model?.trimmingCharacters(in: .whitespaces), !model.isEmpty,
			  let provider = readyProviders.first(where: { $0.id == providerID })
		else { return writerClient }
		return makeClient(provider, model: model) ?? writerClient
	}

	/// Picks the model for AI Writer, or nil to follow the assistant.
	func selectWriter(_ choice: ModelChoice?) {
		writerChoice = choice
		UserDefaults.standard.set(choice.flatMap { try? JSONEncoder().encode($0) }, forKey: Keys.writer)
	}

	/// Adds a provider or replaces the one with the same id.
	func save(_ config: AIProviderConfig, key: String) {
		let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
		keys[config.id] = trimmed.isEmpty ? nil : trimmed
		if trimmed.isEmpty { AIKeychain.delete(config.id) } else { _ = AIKeychain.save(config.id, trimmed) }
		if let index = providers.firstIndex(where: { $0.id == config.id }) { providers[index] = config } else { providers.append(config) }
		if activeID == nil || !providers.contains(where: { $0.id == activeID }) { activeID = config.id }
		persist()
	}

	func remove(_ id: String) {
		providers.removeAll { $0.id == id }
		keys[id] = nil
		AIKeychain.delete(id)
		if activeID == id { activeID = providers.first?.id }
		persist()
	}

	/// Makes a provider and one of its models the ones the assistant uses.
	func select(providerID: String, model: String) {
		guard let index = providers.firstIndex(where: { $0.id == providerID }) else { return }
		providers[index].model = model
		activeID = providerID
		persist()
	}

	/// Remembers the model list a provider returned.
	func cacheModels(_ models: [String], for id: String) {
		guard let index = providers.firstIndex(where: { $0.id == id }), providers[index].models != models else { return }
		providers[index].models = models
		persist()
	}
}

/// API keys in the Keychain, apart from account secrets and the license key.
enum AIKeychain {
	private static let service = "xyz.hieunguyen.Mailflare.ai"

	private static func query(_ account: String) -> [String: Any] {
		[kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
	}

	static func load(_ account: String) -> String? {
		var request = query(account)
		request[kSecReturnData as String] = true
		request[kSecMatchLimit as String] = kSecMatchLimitOne
		var item: CFTypeRef?
		guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
		return String(data: data, encoding: .utf8)
	}

	static func save(_ account: String, _ secret: String) -> Bool {
		let data = Data(secret.utf8)
		let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
		if status == errSecSuccess { return true }
		guard status == errSecItemNotFound else { return false }
		var insert = query(account)
		insert[kSecValueData as String] = data
		insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
		return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
	}

	static func delete(_ account: String) { SecItemDelete(query(account) as CFDictionary) }
}
