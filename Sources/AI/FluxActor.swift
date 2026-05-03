import Foundation

enum FluxError: Error, LocalizedError {
    case scriptNotFound
    case processNotRunning
    case malformedOutput
    case timeout
    case generationFailed(String)
    case modelLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptNotFound:
            return "FLUX Python script not found. Expected at: \( FluxActor.scriptPath)"
        case .processNotRunning:
            return "FLUX process is not running. Call restart() first."
        case .malformedOutput:
            return "FLUX returned malformed JSON. The model output could not be parsed."
        case .timeout:
            return "FLUX illustration generation timed out after 300 seconds."
        case .generationFailed(let message):
            return "Illustration generation failed: \(message)"
        case .modelLoadFailed(let message):
            return "Failed to load FLUX model: \(message)"
        }
    }
}

struct FluxGenerationResult: Codable {
    var illustrationPath: String
    var seed: Int
    var timingSeconds: Double

    enum CodingKeys: String, CodingKey {
        case illustrationPath = "illustration_path"
        case seed
        case timingSeconds = "timing_seconds"
    }
}

actor FluxActor {
    static let shared = FluxActor()
    static var scriptPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let naturista = appSupport.appendingPathComponent("Naturista", isDirectory: true)
        let pythonDir = naturista.appendingPathComponent("Python", isDirectory: true)
        return pythonDir.appendingPathComponent("flux_service.py").path
    }

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var isRunning = false

    private init() {}

    func generate(photoPath: String, identification: IdentificationResult, entryId: UUID) async throws -> String {
        if process == nil || !isRunning {
            try await restart()
        }

        guard let inputPipe = inputPipe, let outputPipe = outputPipe, isRunning else {
            throw FluxError.processNotRunning
        }

        let identificationJsonPath = AppPaths.applicationSupport
            .appendingPathComponent("temp_identification_\(entryId.uuidString).json")
        let identificationJsonData = try JSONEncoder().encode(identification)
        try identificationJsonData.write(to: identificationJsonPath)

        defer {
            try? FileManager.default.removeItem(at: identificationJsonPath)
        }

        let illustrationFilename = "\(entryId.uuidString)_illustration.png"
        let outputPath = AppPaths.illustrations.appendingPathComponent(illustrationFilename).path
        print("[flux] requesting output_path=\(outputPath)")
        if FileManager.default.fileExists(atPath: outputPath) {
            let preAttrs = try? FileManager.default.attributesOfItem(atPath: outputPath)
            let preSize = (preAttrs?[.size] as? Int) ?? -1
            let preMtime = (preAttrs?[.modificationDate] as? Date)?.description ?? "<unknown>"
            print("[flux] pre-existing file size=\(preSize) mtime=\(preMtime)")
        }

        let request: [String: Any] = [
            "action": "generate",
            "identification_json_path": identificationJsonPath.path,
            "photo_path": photoPath,
            "output_path": outputPath
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: request, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw FluxError.generationFailed("Failed to encode request JSON")
        }

        inputPipe.writePipe.write(jsonString.appending("\n").data(using: .utf8)!)

        var responseData = Data()
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 310_000_000_000)
            throw FluxError.timeout
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
            throw FluxError.malformedOutput
        }

        guard let data = result.data(using: .utf8) else {
            throw FluxError.malformedOutput
        }

        do {
            let decoder = JSONDecoder()
            let generationResult = try decoder.decode(FluxGenerationResult.self, from: data)
            print("[flux] response illustration_path=\(generationResult.illustrationPath) seed=\(generationResult.seed) timing=\(generationResult.timingSeconds)s")
            return generationResult.illustrationPath
        } catch let error as FluxError {
            throw error
        } catch {
            if result.contains("\"error\"") {
                if let errorData = result.data(using: .utf8),
                   let errorJson = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                   let errorMessage = errorJson["error"] as? String {
                    throw FluxError.generationFailed(errorMessage)
                }
            }
            throw FluxError.malformedOutput
        }
    }

    func restart() async throws {
        await shutdown()

        let scriptPath = FluxActor.scriptPath
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw FluxError.scriptNotFound
        }

        let pythonProcess = Process()
        pythonProcess.executableURL = URL(fileURLWithPath: NSString(string: ModelConfig.pythonPath).expandingTildeInPath)
        pythonProcess.arguments = [scriptPath]

        let input = Pipe()
        let output = Pipe()
        pythonProcess.standardOutput = output
        pythonProcess.standardInput = input
        let stderrLogPath = "/tmp/naturista_flux.log"
        FileManager.default.createFile(atPath: stderrLogPath, contents: nil)
        pythonProcess.standardError = FileHandle(forWritingAtPath: stderrLogPath) ?? FileHandle.nullDevice

        pythonProcess.environment = [
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
            throw FluxError.modelLoadFailed("Python process exited early with code \(exitCode)")
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