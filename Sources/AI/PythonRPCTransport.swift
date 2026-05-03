import Foundation

// Long-lived Python subprocess speaking JSON-line RPC over stdin/stdout.
// Replaces the duplicated process-lifecycle / IPC machinery that lived in
// FluxActor and GemmaActor. Per-model wrappers shrink to typed Codable
// adapters that only declare their request/response shapes.

enum PythonRPCError: Error, LocalizedError {
    case scriptNotFound(String)
    case modelLoadFailed(String)
    case processNotRunning
    case timeout(seconds: TimeInterval)
    case malformedOutput(String)
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .scriptNotFound(let path):
            return "Python script not found at \(path)."
        case .modelLoadFailed(let m):
            return "Failed to load Python model process: \(m)"
        case .processNotRunning:
            return "Python process is not running."
        case .timeout(let s):
            return "Python RPC timed out after \(Int(s)) seconds."
        case .malformedOutput(let m):
            return "Python returned malformed output: \(m)"
        case .remote(let m):
            return m
        }
    }
}

// Subprocess seam — a stand-in is injected from tests so the transport's
// state machine is exercisable without spawning real Python.
protocol RPCSubprocess: AnyObject {
    var isRunning: Bool { get }
    func send(_ line: String) throws
    func readLine(timeoutSeconds: TimeInterval) async throws -> String?
    func terminate()
}

struct ProcessFactory: @unchecked Sendable {
    var make: (_ executable: URL,
               _ arguments: [String],
               _ environment: [String: String],
               _ stderrLogURL: URL) throws -> any RPCSubprocess

    static let live = ProcessFactory { executable, args, env, stderrURL in
        try LivePythonSubprocess(
            executable: executable,
            arguments: args,
            environment: env,
            stderrLogURL: stderrURL
        )
    }
}

// MARK: - Transport

protocol PythonRPCTransport: Actor {
    func call<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ request: Request,
        responseType: Response.Type
    ) async throws -> Response

    func shutdown() async
}

actor PythonProcessTransport: PythonRPCTransport {
    struct Config: Sendable {
        let scriptPath: String
        // Closure so each subprocess restart picks up the freshly-computed env
        // (e.g. GEMMA_MODEL_PATH after the user changes the selected model).
        let environment: @Sendable () -> [String: String]
        let timeoutSeconds: TimeInterval
        let warmupSeconds: TimeInterval
        let stderrLogURL: URL
    }

    private let config: Config
    private let factory: ProcessFactory
    private var subprocess: (any RPCSubprocess)?

    init(config: Config, factory: ProcessFactory = .live) {
        self.config = config
        self.factory = factory
    }

    func call<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ request: Request,
        responseType: Response.Type
    ) async throws -> Response {
        if subprocess == nil || subprocess?.isRunning != true {
            try await restart()
        }
        guard let sub = subprocess else { throw PythonRPCError.processNotRunning }

        let body: String
        do {
            let data = try JSONEncoder().encode(request)
            guard let s = String(data: data, encoding: .utf8) else {
                throw PythonRPCError.malformedOutput("Could not encode request.")
            }
            body = s
        } catch let e as PythonRPCError {
            throw e
        } catch {
            throw PythonRPCError.malformedOutput(error.localizedDescription)
        }

        do {
            try sub.send(body)
        } catch {
            await teardown()
            throw error
        }

        let line: String?
        do {
            line = try await sub.readLine(timeoutSeconds: config.timeoutSeconds)
        } catch {
            await teardown()
            throw error
        }

        guard let line, let lineData = line.data(using: .utf8) else {
            await teardown()
            throw PythonRPCError.timeout(seconds: config.timeoutSeconds)
        }

        // Try the typed decode. If that fails, see whether the payload is a
        // {"error": "..."} envelope so we surface the real cause instead of a
        // malformed-output message.
        do {
            return try JSONDecoder().decode(Response.self, from: lineData)
        } catch let typedError {
            if let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
               let errMessage = object["error"] as? String {
                await teardown()
                throw PythonRPCError.remote(errMessage)
            }
            await teardown()
            throw PythonRPCError.malformedOutput(typedError.localizedDescription)
        }
    }

    func shutdown() async {
        await teardown()
    }

    private func teardown() async {
        subprocess?.terminate()
        subprocess = nil
    }

    private func restart() async throws {
        await teardown()

        guard FileManager.default.fileExists(atPath: config.scriptPath) else {
            throw PythonRPCError.scriptNotFound(config.scriptPath)
        }

        let executableURL = URL(fileURLWithPath: NSString(string: ModelConfig.pythonPath).expandingTildeInPath)

        var env = config.environment()
        env["PYTHONUNBUFFERED"] = "1"

        let sub: any RPCSubprocess
        do {
            sub = try factory.make(executableURL, [config.scriptPath], env, config.stderrLogURL)
        } catch {
            throw PythonRPCError.modelLoadFailed(error.localizedDescription)
        }

        // Warmup gate — give the model a moment to load weights, then check the
        // process is still alive before declaring it ready.
        try await Task.sleep(nanoseconds: UInt64(config.warmupSeconds * 1_000_000_000))

        guard sub.isRunning else {
            throw PythonRPCError.modelLoadFailed("Python process exited during warmup.")
        }

        subprocess = sub
    }
}

// MARK: - Live subprocess (production)

private final class LivePythonSubprocess: RPCSubprocess, @unchecked Sendable {
    private let process: Process
    private let inputPipe: Pipe
    private let outputPipe: Pipe

    init(executable: URL, arguments: [String], environment: [String: String], stderrLogURL: URL) throws {
        process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment

        inputPipe = Pipe()
        outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe

        FileManager.default.createFile(atPath: stderrLogURL.path, contents: nil)
        process.standardError = FileHandle(forWritingAtPath: stderrLogURL.path) ?? FileHandle.nullDevice

        try process.run()
    }

    var isRunning: Bool { process.isRunning }

    func send(_ line: String) throws {
        guard let data = (line + "\n").data(using: .utf8) else {
            throw PythonRPCError.malformedOutput("Could not encode request line.")
        }
        try inputPipe.fileHandleForWriting.write(contentsOf: data)
    }

    // 100ms poll on `availableData`, accumulate into a buffer, return the
    // first non-empty line ending in `\n` or nil on timeout. Mirrors the
    // original Flux/Gemma read loop.
    func readLine(timeoutSeconds: TimeInterval) async throws -> String? {
        var buffer = Data()
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !Task.isCancelled {
            try Task.checkCancellation()
            let available = outputPipe.fileHandleForReading.availableData
            if !available.isEmpty {
                buffer.append(available)
                if let s = String(data: buffer, encoding: .utf8),
                   let nl = s.firstIndex(of: "\n") {
                    let line = String(s[..<nl])
                    if !line.isEmpty { return line }
                    // Skip a leading blank line and keep reading.
                    let after = s.index(after: nl)
                    buffer = Data(String(s[after...]).utf8)
                }
            }
            if Date() >= deadline { return nil }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        return nil
    }

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }
}

// Single home for the Pipe extensions previously duplicated across
// FluxActor and GemmaActor. Only LivePythonSubprocess uses them now.
extension Pipe {
    var readPipe: FileHandle { fileHandleForReading }
    var writePipe: FileHandle { fileHandleForWriting }
}
