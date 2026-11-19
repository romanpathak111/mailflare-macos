import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence: Apple's on-device model, through the Foundation Models framework. Free,
/// private and offline. It is small, with a working memory of a few thousand words, so SuperMail
/// gives it a short list of email tools and trims long emails and tool results to fit.
enum AppleIntelligence {
	/// Whether the model can be used on this Mac now (Apple silicon, Apple Intelligence turned on).
	static var isAvailable: Bool {
		#if canImport(FoundationModels)
		if #available(macOS 26.0, *) {
			if case .available = SystemLanguageModel.default.availability { return true }
		}
		#endif
		return false
	}

	/// Why it can't be used, in plain words, when it can't.
	static var unavailableReason: String? {
		#if canImport(FoundationModels)
		if #available(macOS 26.0, *) {
			switch SystemLanguageModel.default.availability {
			case .available: return nil
			case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in System Settings to use it."
			case .unavailable(.deviceNotEligible): return "This Mac can't run Apple Intelligence."
			case .unavailable(.modelNotReady): return "Apple Intelligence is still downloading its model."
			default: return "Apple Intelligence isn't available right now."
			}
		}
		#endif
		return "Apple Intelligence needs macOS 26 or later."
	}

	/// The email tools it is given: enough to read, tag, file, archive and draft.
	static let toolNames: Set<String> = [
		"get_current_email", "get_email", "get_thread", "search_emails", "list_emails",
		"set_status", "move_to_folder", "list_folders", "move_email", "move_emails",
		"mark_email_read", "draft_reply", "review_draft_send",
	]

	/// A tool definition cut down to its first sentence and its parameter names and types.
	static func compact(_ tool: [String: Any]) -> [String: Any] {
		guard var function = tool["function"] as? [String: Any] else { return tool }
		if let description = function["description"] as? String {
			let first = description.split(separator: ".", maxSplits: 1).first.map { String($0) + "." } ?? description
			function["description"] = first
		}
		if var parameters = function["parameters"] as? [String: Any], let properties = parameters["properties"] as? [String: Any] {
			var slim: [String: Any] = [:]
			for (key, value) in properties {
				var p = (value as? [String: Any]) ?? [:]
				p["description"] = nil
				slim[key] = p
			}
			parameters["properties"] = slim
			function["parameters"] = parameters
		}
		var copy = tool
		copy["function"] = function
		return copy
	}

	/// The conversation trimmed to fit: the system prompt shortened, long messages and tool results
	/// cut, and only the latest turns kept.
	static func fit(_ messages: [[String: Any]]) -> [[String: Any]] {
		var out: [[String: Any]] = []
		var budget = 12_000   // characters for the turns, after the system prompt
		for message in messages.reversed() {
			var m = message
			let role = m["role"] as? String ?? ""
			let limit = role == "system" ? 2_400 : (role == "tool" ? 3_000 : 2_000)
			if let text = m["content"] as? String, text.count > limit { m["content"] = String(text.prefix(limit)) + " … [shortened to fit Apple Intelligence; the email itself is complete]" }
			if role == "system" { out.insert(m, at: 0); continue }
			let size = (m["content"] as? String)?.count ?? 200
			if budget - size < 0 && !out.isEmpty { break }
			budget -= size
			out.insert(m, at: out.first?["role"] as? String == "system" ? 1 : 0)
		}
		// A tool result must follow the assistant turn that asked for it.
		while let first = out.first(where: { ($0["role"] as? String) != "system" }), (first["role"] as? String) == "tool",
			  let index = out.firstIndex(where: { ($0["role"] as? String) == "tool" }) {
			out.remove(at: index)
		}
		return out
	}
}

#if canImport(FoundationModels)
/// One step of the on-device assistant, forced into this shape by guided generation: what to say,
/// and at most one tool to run next. The model never sees or writes a tool result itself.
@available(macOS 26.0, *)
@Generable
struct AgentStep {
	@Guide(description: "The tool to run next, or none when you can answer now.", .anyOf([
		"none", "get_current_email", "get_email", "get_thread", "search_emails", "list_emails",
		"set_status", "move_to_folder", "list_folders", "move_email", "move_emails",
		"mark_email_read", "draft_reply", "review_draft_send",
	]))
	var tool: String
	@Guide(description: "The tool's arguments as a JSON object, using only emailIds that a tool result gave you. {} when the tool takes none or tool is none.")
	var arguments: String
	@Guide(description: "What to tell the user. Short. When tool is not none, a few words on what you are doing.")
	var reply: String
}
#endif

/// Runs one assistant turn on the on-device model and streams it like `AIClient.stream`. With
/// tools, each turn is one structured step (see `AgentStep`); without, plain text.
struct AppleIntelligenceClient {
	func stream(messages: [[String: Any]], tools: [[String: Any]]) -> AsyncThrowingStream<AIStreamEvent, Error> {
		let fitted = AppleIntelligence.fit(messages)
		let slimTools = tools.filter { tool in
			((tool["function"] as? [String: Any])?["name"] as? String).map(AppleIntelligence.toolNames.contains) ?? false
		}.map(AppleIntelligence.compact)
		return AsyncThrowingStream { continuation in
			let task = Task {
				#if canImport(FoundationModels)
				guard #available(macOS 26.0, *), AppleIntelligence.isAvailable else {
					continuation.finish(throwing: AIError(message: AppleIntelligence.unavailableReason ?? "Apple Intelligence isn't available."))
					return
				}
				do {
					if slimTools.isEmpty {
						let rendered = LocalCLIPrompt.render(messages: fitted, tools: [])
						let session = LanguageModelSession(instructions: rendered.system)
						var shown = 0
						for try await snapshot in session.streamResponse(to: rendered.prompt) {
							let text = snapshot.content
							if text.count > shown { continuation.yield(.text(String(text.dropFirst(shown)))); shown = text.count }
						}
					} else {
						let (instructions, prompt) = Self.agentPrompt(fitted, tools: slimTools)
						let session = LanguageModelSession(instructions: instructions)
						let step = try await session.respond(to: prompt, generating: AgentStep.self).content
						#if DEBUG
						if ProcessInfo.processInfo.environment["SUPERMAIL_AI_DEBUG"] != nil { print("STEP>>>", step.tool, step.arguments, "|", step.reply) }
						#endif
						let reply = step.reply.trimmingCharacters(in: .whitespacesAndNewlines)
						if !reply.isEmpty { continuation.yield(.text(reply + (step.tool == "none" ? "" : "\n"))) }
						if step.tool != "none" {
							var args = step.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
							if args.isEmpty || (try? JSONSerialization.jsonObject(with: Data(args.utf8))) == nil { args = "{}" }
							continuation.yield(.toolCalls([AIToolCall(id: "call_" + UUID().uuidString.prefix(8).lowercased(), name: step.tool, arguments: args)]))
						}
					}
					continuation.finish()
				} catch is CancellationError {
					continuation.finish()
				} catch let error as LanguageModelSession.GenerationError {
					switch error {
					case .exceededContextWindowSize:
						continuation.finish(throwing: AIError(message: "This is too long for Apple Intelligence. Try a shorter request, or switch this chat to Codex or Claude."))
					case .guardrailViolation:
						continuation.finish(throwing: AIError(message: "Apple Intelligence declined this content. Try Codex or Claude for it."))
					default:
						continuation.finish(throwing: AIError(message: "Apple Intelligence: \(error.localizedDescription)"))
					}
				} catch {
					continuation.finish(throwing: AIError(message: "Apple Intelligence: \(error.localizedDescription)"))
				}
				#else
				continuation.finish(throwing: AIError(message: "This build has no Apple Intelligence support."))
				#endif
			}
			continuation.onTermination = { _ in task.cancel() }
		}
	}

	/// The system prompt with the tools listed, and the conversation so far as plain text: earlier
	/// tool calls and their real results included, so the model knows what is done.
	static func agentPrompt(_ messages: [[String: Any]], tools: [[String: Any]]) -> (String, String) {
		var system: [String] = []
		var lines: [String] = []
		var names: [String: String] = [:]
		for m in messages {
			let role = m["role"] as? String ?? "user"
			let text = (m["content"] as? String) ?? ((m["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: "\n") ?? "")
			switch role {
			case "system": system.append(text)
			case "assistant":
				if !text.isEmpty { lines.append("Assistant: " + text) }
				for call in (m["tool_calls"] as? [[String: Any]]) ?? [] {
					let f = call["function"] as? [String: Any] ?? [:]
					let name = f["name"] as? String ?? ""
					names[call["id"] as? String ?? ""] = name
					lines.append("Assistant ran \(name) with \(f["arguments"] as? String ?? "{}")")
				}
			case "tool": lines.append("Result of \(names[m["tool_call_id"] as? String ?? ""] ?? "tool"): " + text)
			default: lines.append("User: " + text)
			}
		}
		let toolList = tools.compactMap { t -> String? in
			guard let f = t["function"] as? [String: Any], let name = f["name"] as? String else { return nil }
			let params = ((f["parameters"] as? [String: Any])?["properties"] as? [String: Any]).map { $0.keys.sorted().joined(separator: ", ") } ?? ""
			return "- \(name)(\(params)): \(f["description"] as? String ?? "")"
		}.joined(separator: "\n")
		system.append("""
		Tools you can run, one per step:
		\(toolList)
		Choose the next step. To act on "this email", first run get_current_email to learn its emailId. \
		Only use emailIds that appear in a result above. When the results above already did what the user asked, \
		set tool to none and tell the user what was done. Never claim something was done unless a result above says so.
		""")
		return (system.joined(separator: "\n\n"), lines.joined(separator: "\n") + "\n\nWhat is the next step?")
	}
}
