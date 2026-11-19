import Foundation

/// A coding-agent CLI installed on this Mac, used through the login the user already has (a Claude or
/// ChatGPT subscription), so no API key is needed. Mailflare runs it once per assistant turn.
enum LocalCLI: String, Codable {
	case claude, codex

	var title: String {
		switch self {
		case .claude: "Claude Code"
		case .codex: "Codex"
		}
	}

	var command: String { rawValue }

	/// Model names offered in the pickers. "default" lets the CLI choose (for Codex, the model in
	/// ~/.codex/config.toml).
	var models: [String] {
		switch self {
		case .claude: ["sonnet", "opus", "haiku"]
		case .codex: ["default"]
		}
	}

	var defaultModel: String { models[0] }

	/// Where the CLI is installed, or nil when it is not.
	var executable: URL? { LocalCLIEnvironment.shared.locate(command) }
	var isInstalled: Bool { executable != nil }
}

/// The login shell's PATH and the CLI locations, looked up once. Apps opened from the Finder get a
/// minimal PATH, and Codex is a Node script that needs `node` on the PATH to start.
final class LocalCLIEnvironment: @unchecked Sendable {
	static let shared = LocalCLIEnvironment()

	private let lock = NSLock()
	private var cachedPath: String?
	private var located: [String: URL] = [:]

	var path: String {
		lock.lock(); defer { lock.unlock() }
		if let cachedPath { return cachedPath }
		let home = FileManager.default.homeDirectoryForCurrentUser.path
		var parts = (Self.run("/bin/zsh", ["-lc", "print -r -- $PATH"]) ?? "")
			.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":").map(String.init)
		for extra in ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin", "\(home)/.bun/bin",
					  "/usr/bin", "/bin", "/usr/sbin", "/sbin"] where !parts.contains(extra) {
			parts.append(extra)
		}
		let value = parts.joined(separator: ":")
		cachedPath = value
		return value
	}

	/// Where the CLIs are usually installed. Checked first, so finding one never has to start a
	/// shell (which is slow, and must not happen while SwiftUI is drawing).
	private static var usualDirectories: [String] {
		let home = FileManager.default.homeDirectoryForCurrentUser.path
		return ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.claude/local"]
	}

	func locate(_ command: String) -> URL? {
		lock.lock()
		if let url = located[command], FileManager.default.isExecutableFile(atPath: url.path) { lock.unlock(); return url }
		for dir in Self.usualDirectories {
			let candidate = URL(fileURLWithPath: dir).appendingPathComponent(command)
			if FileManager.default.isExecutableFile(atPath: candidate.path) {
				located[command] = candidate
				lock.unlock()
				return candidate
			}
		}
		lock.unlock()
		// Elsewhere: look along the login shell's PATH, but never from the main thread.
		guard !Thread.isMainThread else { return nil }
		let searchPath = path
		lock.lock(); defer { lock.unlock() }
		for dir in searchPath.split(separator: ":") {
			let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(command)
			if FileManager.default.isExecutableFile(atPath: candidate.path) {
				located[command] = candidate
				return candidate
			}
		}
		return nil
	}

	/// An empty folder for the CLIs to run in, so they never pick up a project's files or instructions.
	var workingDirectory: URL {
		let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("Mailflare/LocalAI", isDirectory: true)
		try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
		return base
	}

	/// The model chosen in ~/.codex/config.toml, if any.
	var codexConfiguredModel: String? {
		let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml")
		guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
		for line in text.split(separator: "\n") {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if trimmed.hasPrefix("[") { break } // Only the top-level key, not a profile's.
			guard trimmed.hasPrefix("model"), let eq = trimmed.firstIndex(of: "=") else { continue }
			guard trimmed[..<eq].trimmingCharacters(in: .whitespaces) == "model" else { continue }
			let value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
				.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
			return value.isEmpty ? nil : value
		}
		return nil
	}

	private static func run(_ launch: String, _ args: [String]) -> String? {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: launch)
		process.arguments = args
		let out = Pipe()
		process.standardOutput = out
		process.standardError = FileHandle.nullDevice
		process.standardInput = FileHandle.nullDevice
		do { try process.run() } catch { return nil }
		let data = out.fileHandleForReading.readDataToEndOfFile()
		// Not waitUntilExit: it runs the current run loop, which can re-enter SwiftUI mid-update.
		while process.isRunning { usleep(2_000) }
		return String(data: data, encoding: .utf8)
	}
}

/// Turns one chat-completions request (messages and tools in the OpenAI JSON shape) into a single
/// prompt for a CLI, and reads tool calls back out of its answer. The CLIs' own tools stay off: the
/// model asks for Mailflare's tools with `<tool_call>` blocks and Mailflare runs them, as it does
/// for an API provider.
enum LocalCLIPrompt {
	static let openTag = "<tool_call>"
	static let closeTag = "</tool_call>"

	struct Rendered {
		var system: String
		var prompt: String
		var images: [(mediaType: String, data: Data)]
	}

	static func render(messages: [[String: Any]], tools: [[String: Any]]) -> Rendered {
		var system: [String] = []
		var transcript: [String] = []
		var images: [(String, Data)] = []
		var toolNames: [String: String] = [:]

		for message in messages {
			let role = message["role"] as? String ?? "user"
			let (text, found) = content(message["content"])
			switch role {
			case "system":
				system.append(text)
			case "assistant":
				var body = text
				for call in (message["tool_calls"] as? [[String: Any]]) ?? [] {
					let id = call["id"] as? String ?? ""
					let function = call["function"] as? [String: Any] ?? [:]
					let name = function["name"] as? String ?? ""
					toolNames[id] = name
					let args = function["arguments"] as? String ?? "{}"
					body += (body.isEmpty ? "" : "\n") + "\(openTag){\"name\": \(jsonString(name)), \"arguments\": \(args)}\(closeTag)"
				}
				transcript.append("<assistant>\n\(body)\n</assistant>")
			case "tool":
				let id = message["tool_call_id"] as? String ?? ""
				let name = toolNames[id] ?? "tool"
				transcript.append("<tool_result name=\"\(name)\">\n\(text)\n</tool_result>")
			default:
				images += found
				let note = found.isEmpty ? "" : "\n[\(found.count) image(s) attached to this message.]"
				transcript.append("<user>\n\(text)\(note)\n</user>")
			}
		}

		if !tools.isEmpty { system.append(toolInstructions(tools)) }
		system.append("""
		You are running inside the SuperMail email app, not in a terminal or code project. \
		Do not use any built-in tools of your own: do not run commands, read or write files, or browse the web. \
		Everything you need comes from the conversation\(tools.isEmpty ? "" : " and the SuperMail tools above").
		""")

		let prompt: String
		if transcript.count == 1, messages.last?["role"] as? String == "user" {
			// A single request (summaries, AI Writer): just the text.
			prompt = String(transcript[0].dropFirst("<user>\n".count).dropLast("\n</user>".count))
		} else {
			prompt = """
			The conversation so far is below. User messages are in <user>, your earlier replies in <assistant> and tool results in <tool_result>.

			\(transcript.joined(separator: "\n\n"))

			Write your next reply as the assistant. Do not repeat the tags around it.
			"""
		}
		return Rendered(system: system.joined(separator: "\n\n"), prompt: prompt, images: images)
	}

	private static func toolInstructions(_ tools: [[String: Any]]) -> String {
		let list = tools.compactMap { tool -> String? in
			guard let function = tool["function"] as? [String: Any], let name = function["name"] as? String else { return nil }
			let description = function["description"] as? String ?? ""
			let parameters = function["parameters"].flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
				.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
			return "- \(name): \(description)\n  parameters (JSON Schema): \(parameters)"
		}.joined(separator: "\n")
		return """
		# SuperMail tools

		You can use these tools, which SuperMail runs for you:
		\(list)

		To use tools, end your reply with one or more blocks in exactly this form, one per call:
		\(openTag){"name": "tool_name", "arguments": {"key": "value"}}\(closeTag)
		The arguments must be a valid JSON object that matches the tool's parameters. You may write a short sentence before the blocks, but nothing after them. \
		SuperMail then runs the tools and sends you their results in <tool_result> blocks, and you continue. \
		Never write a <tool_result> yourself and never guess what a tool would return. When you need no tool, just answer.
		"""
	}

	/// The text of a message's content, plus any images in it (as data URLs from attachments).
	private static func content(_ value: Any?) -> (String, [(String, Data)]) {
		if let text = value as? String { return (text, []) }
		var texts: [String] = []
		var images: [(String, Data)] = []
		for part in (value as? [[String: Any]]) ?? [] {
			if let text = part["text"] as? String { texts.append(text) }
			if let url = (part["image_url"] as? [String: Any])?["url"] as? String, let image = decodeDataURL(url) { images.append(image) }
		}
		return (texts.joined(separator: "\n"), images)
	}

	private static func decodeDataURL(_ url: String) -> (String, Data)? {
		guard url.hasPrefix("data:"), let comma = url.firstIndex(of: ","), url[..<comma].hasSuffix(";base64") else { return nil }
		let mediaType = String(url[url.index(url.startIndex, offsetBy: 5)..<comma].dropLast(";base64".count))
		guard let data = Data(base64Encoded: String(url[url.index(after: comma)...])) else { return nil }
		return (mediaType.isEmpty ? "image/png" : mediaType, data)
	}

	private static func jsonString(_ s: String) -> String {
		(try? JSONSerialization.data(withJSONObject: [s])).map { String(decoding: $0, as: UTF8.self).dropFirst().dropLast() }.map(String.init) ?? "\"\(s)\""
	}

	/// Splits a finished answer into its text and the tool calls at its end.
	static func parse(_ answer: String) -> (text: String, calls: [AIToolCall]) {
		guard let first = answer.range(of: openTag) else { return (answer.trimmingCharacters(in: .whitespacesAndNewlines), []) }
		let text = String(answer[..<first.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
		var calls: [AIToolCall] = []
		var rest = answer[first.lowerBound...]
		while let open = rest.range(of: openTag) {
			let afterOpen = rest[open.upperBound...]
			let close = afterOpen.range(of: closeTag)
			let body = close.map { afterOpen[..<$0.lowerBound] } ?? afterOpen
			if let call = toolCall(String(body)) { calls.append(call) }
			guard let close else { break }
			rest = afterOpen[close.upperBound...]
		}
		return (text, calls)
	}

	private static func toolCall(_ body: String) -> AIToolCall? {
		var json = body.trimmingCharacters(in: .whitespacesAndNewlines)
		// Some models wrap the JSON in a code fence.
		if json.hasPrefix("```") {
			json = json.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n")
			if json.hasSuffix("```") { json = String(json.dropLast(3)) }
		}
		guard let data = json.data(using: .utf8),
			  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let name = object["name"] as? String, !name.isEmpty else { return nil }
		let arguments: String
		if let args = object["arguments"] as? [String: Any], let encoded = try? JSONSerialization.data(withJSONObject: args) {
			arguments = String(decoding: encoded, as: UTF8.self)
		} else if let args = object["arguments"] as? String {
			arguments = args
		} else {
			arguments = "{}"
		}
		return AIToolCall(id: "call_" + UUID().uuidString.prefix(8).lowercased(), name: name, arguments: arguments)
	}

	/// How much of `buffer` can be shown now: everything before a tool call, and before a `<` that
	/// may still turn into one.
	static func safePrefixLength(_ buffer: String) -> Int {
		if let range = buffer.range(of: openTag) { return buffer.distance(from: buffer.startIndex, to: range.lowerBound) }
		if let lt = buffer.lastIndex(of: "<") {
			let tail = buffer[lt...]
			if openTag.hasPrefix(tail) { return buffer.distance(from: buffer.startIndex, to: lt) }
		}
		return buffer.count
	}
}

/// Runs one assistant turn through a local CLI and streams it back like `AIClient.stream`.
struct LocalCLIClient {
	var cli: LocalCLI
	var model: String

	func stream(messages: [[String: Any]], tools: [[String: Any]]) -> AsyncThrowingStream<AIStreamEvent, Error> {
		let rendered = LocalCLIPrompt.render(messages: messages, tools: tools)
		let cli = cli
		let model = model.trimmingCharacters(in: .whitespaces)
		let quick = tools.isEmpty
		return AsyncThrowingStream { continuation in
			let runner = LocalCLIRun()
			let task = Task.detached {
				do {
					guard let executable = cli.executable else {
						throw AIError(message: "\(cli.title) is not installed on this Mac. Install the \(cli.command) command and sign in to it, then try again.")
					}
					let env = LocalCLIEnvironment.shared
					var answer = ""
					var shown = 0
					func emit(final: Bool) {
						var limit = final ? LocalCLIPrompt.parse(answer).text.count : LocalCLIPrompt.safePrefixLength(answer)
						// Hold back trailing blank space: it may be all that stands before a tool call.
						if !final {
							var index = answer.index(answer.startIndex, offsetBy: limit)
							while limit > shown, index > answer.startIndex, answer[answer.index(before: index)].isWhitespace {
								index = answer.index(before: index); limit -= 1
							}
						}
						guard !final else {
							let text = LocalCLIPrompt.parse(answer).text
							if text.count > shown { continuation.yield(.text(String(text.dropFirst(shown)))) }
							shown = max(shown, limit)
							return
						}
						if limit > shown {
							let start = answer.index(answer.startIndex, offsetBy: shown)
							let end = answer.index(answer.startIndex, offsetBy: limit)
							continuation.yield(.text(String(answer[start..<end])))
							shown = limit
						}
					}

					switch cli {
					case .claude:
						let mcpOn = LocalMCP.enabled(for: .claude).intersection(LocalMCP.servers(for: .claude))
						var args = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
									"--include-partial-messages", "--tools", "",
									"--no-session-persistence", "--disable-slash-commands", "--system-prompt", rendered.system]
						if mcpOn.isEmpty {
							args += ["--strict-mcp-config", "--setting-sources", ""]
						} else {
							// The user's own servers load; only the ones switched on in SuperMail may be used.
							args += ["--allowedTools"] + mcpOn.sorted().map(LocalMCP.claudeToolPrefix)
							let off = Set(LocalMCP.servers(for: .claude)).subtracting(mcpOn)
							if !off.isEmpty { args += ["--disallowedTools"] + off.sorted().map(LocalMCP.claudeToolPrefix) }
						}
						if !model.isEmpty, model != "default" { args += ["--model", model] }
						var content: [[String: Any]] = [["type": "text", "text": rendered.prompt]]
						for image in rendered.images {
							content.append(["type": "image", "source": ["type": "base64", "media_type": image.mediaType, "data": image.data.base64EncodedString()]])
						}
						let input: [String: Any] = ["type": "user", "message": ["role": "user", "content": content]]
						var stdin = try JSONSerialization.data(withJSONObject: input)
						stdin.append(0x0A)
						var sawDelta = false
						var failure: String?
						var result: String?
						let exit = try await runner.run(executable: executable, arguments: args, stdin: stdin, path: env.path, cwd: env.workingDirectory) { line in
							guard let data = line.data(using: .utf8),
								  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
							switch object["type"] as? String {
							case "stream_event":
								if let event = object["event"] as? [String: Any], event["type"] as? String == "content_block_delta",
								   let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
								   let text = delta["text"] as? String {
									sawDelta = true
									answer += text
									emit(final: false)
								}
							case "result":
								if object["is_error"] as? Bool == true {
									failure = (object["result"] as? String) ?? (object["subtype"] as? String) ?? "Claude Code reported an error."
								} else {
									result = object["result"] as? String
								}
							default: break
							}
						}
						if let failure { throw AIError(message: "Claude Code: \(failure)") }
						if result == nil, !sawDelta { try exit.check(cli.title) }
						if !sawDelta, let result { answer = result }

					case .codex:
						let allServers = LocalMCP.servers(for: .codex)
						let mcpOn = LocalMCP.enabled(for: .codex).intersection(allServers)
						var args = ["exec", "--json", "--skip-git-repo-check", "--ephemeral", "--ignore-rules",
									"--sandbox", "read-only", "--color", "never",
									"-c", "model_reasoning_effort=\(quick ? "low" : "medium")",
									"-C", env.workingDirectory.path]
						if mcpOn.isEmpty || quick {
							args.insert("--ignore-user-config", at: 1)
						} else {
							// The user's config loads with its MCP servers: those switched on in SuperMail may run
							// their tools without a prompt (there is none in exec), the rest are turned off.
							for name in allServers {
								let key = LocalMCP.tomlKey(name)
								args += ["-c", mcpOn.contains(name) ? "mcp_servers.\(key).default_tools_approval_mode=\"approve\"" : "mcp_servers.\(key).enabled=false"]
							}
						}
						let chosen = (model.isEmpty || model == "default") ? env.codexConfiguredModel : model
						if let chosen { args += ["-m", chosen] }
						var imageFiles: [URL] = []
						defer { for file in imageFiles { try? FileManager.default.removeItem(at: file) } }
						for image in rendered.images {
							let ext = image.mediaType.split(separator: "/").last.map(String.init) ?? "png"
							let file = FileManager.default.temporaryDirectory.appendingPathComponent("mailflare-\(UUID().uuidString).\(ext)")
							try image.data.write(to: file)
							imageFiles.append(file)
							args.append("--image=\(file.path)")
						}
						args.append("-")
						let prompt = "<instructions>\n\(rendered.system)\n</instructions>\n\n\(rendered.prompt)"
						var failure: String?
						let exit = try await runner.run(executable: executable, arguments: args, stdin: Data(prompt.utf8), path: env.path, cwd: env.workingDirectory) { line in
							guard let data = line.data(using: .utf8),
								  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
							switch object["type"] as? String {
							case "item.completed":
								if let item = object["item"] as? [String: Any], item["type"] as? String == "agent_message",
								   let text = item["text"] as? String {
									answer += (answer.isEmpty ? "" : "\n\n") + text
									emit(final: false)
								}
							case "turn.failed":
								failure = ((object["error"] as? [String: Any])?["message"] as? String) ?? "the turn failed."
							case "error":
								failure = (object["message"] as? String) ?? "an error occurred."
							default: break
							}
						}
						if let failure, answer.isEmpty { throw AIError(message: "Codex: \(failure)") }
						if answer.isEmpty { try exit.check(cli.title) }
					}

					try Task.checkCancellation()
					let parsed = LocalCLIPrompt.parse(answer)
					emit(final: true)
					if !parsed.calls.isEmpty { continuation.yield(.toolCalls(parsed.calls)) }
					if answer.isEmpty, parsed.calls.isEmpty { throw AIError(message: "\(cli.title) returned an empty answer.") }
					continuation.finish()
				} catch is CancellationError {
					continuation.finish()
				} catch {
					continuation.finish(throwing: error)
				}
			}
			continuation.onTermination = { _ in
				task.cancel()
				runner.terminate()
			}
		}
	}
}

/// One CLI process: feeds it stdin, hands back stdout line by line, and reports a failed exit.
final class LocalCLIRun: @unchecked Sendable {
	private let lock = NSLock()
	private var process: Process?
	private var cancelled = false

	func terminate() {
		lock.lock(); cancelled = true; let process = self.process; lock.unlock()
		if let process, process.isRunning { process.terminate() }
	}

	/// Keeps the process so it can be stopped; false when the run was already cancelled.
	private func adopt(_ process: Process) -> Bool {
		lock.lock(); defer { lock.unlock() }
		if cancelled { return false }
		self.process = process
		return true
	}

	private var wasCancelled: Bool {
		lock.lock(); defer { lock.unlock() }
		return cancelled
	}

	/// Returns the exit status and the last line the CLI wrote to stderr.
	func run(executable: URL, arguments: [String], stdin: Data, path: String, cwd: URL, onLine: @escaping (String) -> Void) async throws -> LocalCLIExit {
		let process = Process()
		process.executableURL = executable
		process.arguments = arguments
		process.currentDirectoryURL = cwd
		var environment = ProcessInfo.processInfo.environment
		environment["PATH"] = path
		environment["NO_COLOR"] = "1"
		// Never let a key from the app's environment switch the CLI from the user's login to an API.
		environment["ANTHROPIC_API_KEY"] = nil
		environment["OPENAI_API_KEY"] = nil
		process.environment = environment

		let input = Pipe(), output = Pipe(), errors = Pipe()
		process.standardInput = input
		process.standardOutput = output
		process.standardError = errors

		guard adopt(process) else { throw CancellationError() }

		let (lines, lineSink) = AsyncStream<String>.makeStream()
		let splitter = LineSplitter()
		output.fileHandleForReading.readabilityHandler = { handle in
			let chunk = handle.availableData
			if chunk.isEmpty {
				handle.readabilityHandler = nil
				if let last = splitter.flush() { lineSink.yield(last) }
				lineSink.finish()
				return
			}
			for line in splitter.feed(chunk) { lineSink.yield(line) }
		}
		let errorTail = LockedText()
		errors.fileHandleForReading.readabilityHandler = { handle in
			let chunk = handle.availableData
			if chunk.isEmpty { handle.readabilityHandler = nil; return }
			errorTail.append(String(decoding: chunk, as: UTF8.self))
		}

		try process.run()
		input.fileHandleForWriting.write(stdin)
		try? input.fileHandleForWriting.close()

		for await line in lines where !line.isEmpty { onLine(line) }
		while process.isRunning { try? await Task.sleep(for: .milliseconds(20)) }

		if wasCancelled || Task.isCancelled { throw CancellationError() }
		let detail = errorTail.text.split(separator: "\n").last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
		return LocalCLIExit(status: process.terminationStatus, detail: detail.map(String.init))
	}
}

struct LocalCLIExit {
	var status: Int32
	var detail: String?

	func check(_ title: String) throws {
		guard status != 0 else { return }
		throw AIError(message: "\(title) stopped with an error\(detail.map { ": \($0)" } ?? " (exit \(status)).") Check that it is signed in by running it once in Terminal.")
	}
}

/// Collects stdout chunks and hands back complete lines. Only the pipe's handler touches it.
private final class LineSplitter: @unchecked Sendable {
	private var pending = Data()

	func feed(_ chunk: Data) -> [String] {
		pending.append(chunk)
		var lines: [String] = []
		while let newline = pending.firstIndex(of: 0x0A) {
			lines.append(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
			pending.removeSubrange(pending.startIndex...newline)
		}
		return lines
	}

	func flush() -> String? {
		defer { pending.removeAll() }
		return pending.isEmpty ? nil : String(decoding: pending, as: UTF8.self)
	}
}

private final class LockedText: @unchecked Sendable {
	private let lock = NSLock()
	private var value = ""
	func append(_ s: String) { lock.lock(); value += s; if value.count > 8_000 { value = String(value.suffix(4_000)) }; lock.unlock() }
	var text: String { lock.lock(); defer { lock.unlock() }; return value }
}
