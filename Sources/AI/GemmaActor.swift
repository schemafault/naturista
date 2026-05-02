import Foundation

enum GemmaError: Error, LocalizedError {
    case scriptNotFound
    case processNotRunning
    case malformedOutput
    case timeout
    case identificationFailed(String)
    case modelLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptNotFound:
            return " Gemma Python script not found. Expected at: \( GemmaActor.scriptPath)"
        case .processNotRunning:
            return "Gemma process is not running. Call restart() first."
        case .malformedOutput:
            return "Gemma returned malformed JSON. The model output could not be parsed."
        case .timeout:
            return "Gemma identification timed out after 300 seconds."
        case .identificationFailed(let message):
            return "Identification failed: \(message)"
        case .modelLoadFailed(let message):
            return "Failed to load Gemma model: \(message)"
        }
    }
}

struct IdentificationResult: Codable {
    var modelConfidence: String
    var topCandidate: TopCandidate
    var alternatives: [Alternative]
    var visibleEvidence: [String]
    var missingEvidence: [String]
    var safetyNote: String
    var error: String?

    enum CodingKeys: String, CodingKey {
        case modelConfidence = "model_confidence"
        case topCandidate = "top_candidate"
        case alternatives
        case visibleEvidence = "visible_evidence"
        case missingEvidence = "missing_evidence"
        case safetyNote = "safety_note"
        case error
    }
}

struct TopCandidate: Codable {
    var commonName: String
    var scientificName: String
    var family: String

    enum CodingKeys: String, CodingKey {
        case commonName = "common_name"
        case scientificName = "scientific_name"
        case family
    }
}

struct Alternative: Codable {
    var commonName: String
    var scientificName: String
    var reason: String

    enum CodingKeys: String, CodingKey {
        case commonName = "common_name"
        case scientificName = "scientific_name"
        case reason
    }
}

actor GemmaActor {
    static let shared = GemmaActor()
    static var scriptPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let naturista = appSupport.appendingPathComponent("Naturista", isDirectory: true)
        let pythonDir = naturista.appendingPathComponent("Python", isDirectory: true)
        return pythonDir.appendingPathComponent("gemma_service.py").path
    }

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var isRunning = false

    private init() {}

    func identify(photoPath: String) async throws -> IdentificationResult {
        if process == nil || !isRunning {
            try await restart()
        }

        guard let inputPipe = inputPipe, let outputPipe = outputPipe, isRunning else {
            throw GemmaError.processNotRunning
        }

        let request: [String: Any] = [
            "action": "identify",
            "photo_path": photoPath,
            "model_path": NSString(string: ModelConfig.gemmaPath).expandingTildeInPath
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: request, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw GemmaError.identificationFailed("Failed to encode request JSON")
        }

        inputPipe.writePipe.write(jsonString.appending("\n").data(using: .utf8)!)

        var responseData = Data()
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 310_000_000_000)
            throw GemmaError.timeout
        }

        let readTask = Task {
            while true {
                try await Task.sleep(nanoseconds: 100_000_000)
                let available = outputPipe.readPipe.availableData
                if !available.isEmpty {
                    responseData.append(available)
                    if let responseString = String(data: responseData, encoding: .utf8),
                       responseString.contains("\n") {
                        let lines = responseString.components(separatedBy: "\n")
                        if let firstLine = lines.first(where: { !$0.isEmpty }) {
                            return firstLine
                        }
                    }
                }
            }
        }

        var resultString: String?
        do {
            resultString = try await readTask.value
            timeoutTask.cancel()
        } catch {
            readTask.cancel()
            timeoutTask.cancel()
            try? await restart()
            throw error
        }

        guard let result = resultString else {
            throw GemmaError.malformedOutput
        }

        guard let data = result.data(using: .utf8) else {
            throw GemmaError.malformedOutput
        }

        do {
            let decoder = JSONDecoder()
            var identification = try decoder.decode(IdentificationResult.self, from: data)

            if let errorMessage = identification.error, !errorMessage.isEmpty {
                throw GemmaError.identificationFailed(errorMessage)
            }

            return identification
        } catch let error as GemmaError {
            throw error
        } catch {
            if result.contains("\"error\"") {
                if let errorData = result.data(using: .utf8),
                   let errorJson = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                   let errorMessage = errorJson["error"] as? String {
                    throw GemmaError.identificationFailed(errorMessage)
                }
            }
            throw GemmaError.malformedOutput
        }
    }

    func restart() async throws {
        await shutdown()

        let scriptPath = GemmaActor.scriptPath
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw GemmaError.scriptNotFound
        }

        let pythonProcess = Process()
        pythonProcess.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        pythonProcess.arguments = [scriptPath]

        let input = Pipe()
        let output = Pipe()
        pythonProcess.standardOutput = output
        pythonProcess.standardInput = input
        pythonProcess.standardError = FileHandle.nullDevice

        let errorPipe = Pipe()
        pythonProcess.environment = [
            "PYNO_SHOW_ASSET_WARNING": "1",
            "PYTHONUNBUFFERED": "1"
        ]

        var processExitedEarly = false
        pythonProcess.terminationHandler = { proc in
            if proc.terminationStatus != 0 {
                processExitedEarly = true
            }
        }

        try pythonProcess.run()

        inputPipe = input
        outputPipe = output
        process = pythonProcess

        try await Task.sleep(nanoseconds: 2_000_000_000)

        if processExitedEarly || !pythonProcess.isRunning {
            let exitCode = pythonProcess.terminationStatus
            throw GemmaError.modelLoadFailed("Python process exited early with code \(exitCode)")
        }

        isRunning = true
    }

    func shutdown() {
        guard let proc = process, proc.isRunning else {
            process = nil
            inputPipe = nil
            outputPipe = nil
            isRunning = false
            return
        }

        proc.terminate()
        proc.waitUntilExit()

        process = nil
        inputPipe = nil
        outputPipe = nil
        isRunning = false
    }
}

extension Pipe {
    var readPipe: FileHandle { fileHandleForReading }
    var writePipe: FileHandle { fileHandleForWriting }
}
