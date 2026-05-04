import Foundation
import MLX
import MLXLMCommon
import MLXVLM

// In-process Gemma 3/4 identification via mlx-swift-lm. Mirrors the
// behavior the Python `gemma_service.py` had before the native port:
// same system + user prompt, max_tokens 2048, greedy sampling, single-
// image input. Output is post-processed (strip code fences, extract
// outermost `{...}`, normalize "fungi" → "fungus") before decoding.
//
// The container is loaded lazily on the first identify call and held
// for the actor's lifetime — `ModelLease` calls `shutdown()` to release
// it before FLUX takes the GPU. A model swap is honored on the next
// call: if the selected model differs, the container is rebuilt.
actor GemmaActor {
    static let shared = GemmaActor()

    enum GemmaError: Error, LocalizedError {
        case modelDirectoryMissing(URL)
        case parseFailure(String, raw: String)

        var errorDescription: String? {
            switch self {
            case .modelDirectoryMissing(let url):
                return "Model weights not found at \(url.path). Re-download from the model picker."
            case .parseFailure(let why, let raw):
                let preview = raw.prefix(200)
                return "Identifier returned non-JSON output: \(why). Raw: \(preview)…"
            }
        }
    }

    private var container: ModelContainer?
    private var loadedModel: GemmaModel?

    private init() {}

    func identify(photoPath: String) async throws -> IdentificationResult {
        // The ChatSession (and its KV cache) is owned by `runOnce` and
        // goes out of scope when that helper returns or throws. Only
        // then can `clearCache` drain the per-call buffers — if we
        // owned the session here, Swift's ARC could keep it alive past
        // the defer block, leaving the KV cache outside the pool. This
        // structure guarantees the deallocation ordering.
        defer { MLX.Memory.clearCache() }
        let raw = try await runOnce(
            photoPath: photoPath,
            systemPrompt: Self.systemPrompt,
            userPrompt: Self.userPrompt
        )
        return try Self.parseAndValidate(raw)
    }

    // User-corrected re-identification. Treats the user-supplied common /
    // scientific name as authoritative, re-derives family / evidence /
    // confusion-set against the corrected species, and re-emits the
    // photo-derived pose / colors fields from this image.
    func reidentify(
        photoPath: String,
        userCommonName: String?,
        userScientificName: String?
    ) async throws -> IdentificationResult {
        defer { MLX.Memory.clearCache() }
        let raw = try await runOnce(
            photoPath: photoPath,
            systemPrompt: Self.correctionSystemPrompt,
            userPrompt: Self.correctionUserPrompt(
                commonName: userCommonName,
                scientificName: userScientificName
            )
        )
        return try Self.parseAndValidate(raw)
    }

    // Pre-identification hint. Unlike `reidentify`, the user is *guessing* —
    // Gemma should treat the hint as a leading hypothesis but is free to
    // override when the photo clearly shows otherwise, and must set
    // model_confidence honestly rather than forcing "high".
    func identifyWithHint(
        photoPath: String,
        hintCommon: String?,
        hintScientific: String?
    ) async throws -> IdentificationResult {
        defer { MLX.Memory.clearCache() }
        let raw = try await runOnce(
            photoPath: photoPath,
            systemPrompt: Self.hintSystemPrompt,
            userPrompt: Self.hintUserPrompt(
                commonName: hintCommon,
                scientificName: hintScientific
            )
        )
        return try Self.parseAndValidate(raw)
    }

    // Best-effort: warm the container so the first identify call doesn't
    // pay the full VLMModelFactory build (which dominates first-call
    // latency for the larger Gemma SKUs). Caller is responsible for
    // taking the identification lease so FLUX, if resident, gets evicted
    // first. No-op if no model is installed yet — preload doesn't trigger
    // a download, that's `GemmaModelDownloader`'s job.
    func preload() async {
        let model = GemmaModelStore.shared.selected
        guard model.isInstalled else { return }
        _ = try? await ensureContainer(for: model)
    }

    func shutdown() async {
        // Drop the strong reference first so ARC frees the model's
        // MLXArrays. The metal allocator keeps a buffer cache for
        // reuse — that's the right tradeoff while warm, but on
        // shutdown (called by ModelLease before FLUX loads) we want
        // those bytes back. clearCache() runs after deallocation, so
        // the order matters.
        container = nil
        loadedModel = nil
        MLX.Memory.clearCache()
    }

    private func runOnce(
        photoPath: String,
        systemPrompt: String,
        userPrompt: String
    ) async throws -> String {
        let model = GemmaModelStore.shared.selected
        let container = try await ensureContainer(for: model)
        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: GenerateParameters(maxTokens: 2048, temperature: 0),
            // Disable ChatSession's default 512×512 pre-resize so the
            // model's own preprocessor sets the resolution (matching
            // the prior mlx-vlm Python behavior).
            processing: UserInput.Processing()
        )
        return try await session.respond(
            to: userPrompt,
            image: .url(URL(fileURLWithPath: photoPath))
        )
    }

    private func ensureContainer(for model: GemmaModel) async throws -> ModelContainer {
        if let container, loadedModel == model { return container }

        // Different model selected — drop the cached one before loading
        // the new weights. ARC frees the previous container's MLX arrays
        // when no other reference holds it.
        if container != nil { container = nil; loadedModel = nil }

        guard model.isInstalled else {
            throw GemmaError.modelDirectoryMissing(URL(fileURLWithPath: model.localCachePath))
        }

        let directory = URL(fileURLWithPath: model.localCachePath)
        let next = try await VLMModelFactory.shared.loadContainer(
            from: directory,
            using: LocalTokenizerLoader()
        )
        self.container = next
        self.loadedModel = model
        return next
    }

    // MARK: - Prompts

    private static let systemPrompt = """
        You are a natural-history identification assistant. Analyze the provided image and identify the subject.

        Output ONLY valid JSON in this exact format, with no additional text:
        {
          "kingdom": "plant | animal | fungus | other",
          "model_confidence": "high | medium | low",
          "top_candidate": {
            "common_name": "string",
            "scientific_name": "string",
            "family": "string"
          },
          "alternatives": [
            {
              "common_name": "string",
              "scientific_name": "string",
              "reason": "string"
            }
          ],
          "visible_evidence": ["string"],
          "missing_evidence": ["string"],
          "safety_note": "string",
          "pose_description": "string",
          "color_palette": "string"
        }

        Rules for "kingdom":
        - "plant" for any vascular or non-vascular plant.
        - "animal" for any animal — mammal, bird, reptile, amphibian, fish, insect, mollusc, etc.
        - "fungus" for mushrooms, brackets, lichens, and other fungi.
        - "other" if the subject is not a living organism (a manufactured object, food, scenery without a clear subject). For "other" subjects, fill top_candidate.common_name with a brief description (e.g. "ham sandwich"); leave scientific_name and family as empty strings; set alternatives to [].

        Populate visible_evidence with the diagnostic features visible in the image — leaf shape and venation for plants; plumage, pelage, or distinctive markings for animals; cap shape and gill arrangement for fungi; salient details for "other" subjects.

        Tailor safety_note to the kingdom: warn against consumption for plants and fungi; warn against approaching or handling wildlife for animals; for "other" use a brief reference disclaimer.

        The remaining two fields describe the SPECIMEN ITSELF in this photograph, so a downstream illustrator can match its pose and palette. Be concrete and visual; one short clause each. Describe ONLY the specimen — never the surroundings, habitat, lighting, or location. Examples:
        - pose_description: how the specimen itself is posed — limb position, head angle, leaf orientation, cap angle. "head turned to the right, wings folded against the body" / "single bloom viewed from three-quarter angle, stem curving left" / "caps tilted upward in a cluster, gills hidden". Do not describe surroundings, perches, substrates, or habitat.
        - color_palette: the dominant colours and where they appear ON THE SPECIMEN. "rust-brown body with white belly, black eye-stripe, yellow legs" / "deep magenta petals fading to white at the centre, dark green serrated leaves" / "ochre cap with cream gills, pale stem, brown spotting". Do not describe colours of the background.

        These two fields should describe what is actually visible on the specimen in this photograph, not what is typical for the species. If the photo is too cropped or low-quality to populate one of them, leave it as the empty string.
        """

    private static let userPrompt =
        "Identify the subject of this image. Provide your best assessment with supporting visual evidence."

    // Shares the same JSON schema and style rules as `systemPrompt`, but
    // flips the stance: the user has corrected the identification, so the
    // species is given and Gemma re-derives the consistent context. Kept
    // as a static so Gemma's KV cache can hit on repeated corrections in
    // the same session.
    private static let correctionSystemPrompt = systemPrompt + """


        CORRECTION MODE: The user has provided a corrected identification for the subject. Treat their input as authoritative for top_candidate.common_name and top_candidate.scientific_name. If only one of those fields was supplied, infer the other from your taxonomic knowledge.

        Re-derive family, kingdom, visible_evidence, missing_evidence, and safety_note to be CONSISTENT with the user-supplied species — call out features that match it and features that would be missing or unexpected. Populate alternatives[] with species commonly confused with the corrected species (a confusion set), not with rival identifications.

        Set model_confidence to "high" since the species is user-confirmed; reserve "medium" or "low" only if the user-supplied common and scientific names refer to different species — in that case prefer the scientific name and note the conflict in safety_note.

        The pose_description and color_palette fields describe the SPECIMEN ITSELF in this photograph (specimen pose and specimen colours only — never surroundings) and should be re-derived from the image as in normal mode. They do not depend on the species.
        """

    private static func correctionUserPrompt(
        commonName: String?,
        scientificName: String?
    ) -> String {
        let common = commonName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let scientific = scientificName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCommon = !(common?.isEmpty ?? true)
        let hasScientific = !(scientific?.isEmpty ?? true)
        switch (hasCommon, hasScientific) {
        case (true, true):
            return "The user states this is \"\(common!)\" (Latin: \(scientific!)). Re-identify the subject of this image under that correction and produce the JSON response."
        case (true, false):
            return "The user states the common name is \"\(common!)\". Infer the scientific name from your taxonomic knowledge and re-identify the subject of this image under that correction. Produce the JSON response."
        case (false, true):
            return "The user states the scientific name is \"\(scientific!)\". Infer the common name from your taxonomic knowledge and re-identify the subject of this image under that correction. Produce the JSON response."
        case (false, false):
            // Caller should have gated this; fall back to vanilla phrasing.
            return userPrompt
        }
    }

    // Soft pre-identification hint. The user has offered a guess BEFORE
    // Gemma has seen the photo, so the addendum has to do two opposing
    // jobs: lean into the hint when it fits the image (the disambiguation
    // case — "which oak?") AND override the hint when the photo clearly
    // shows otherwise (the wrong-guess case). model_confidence is
    // explicitly NOT pinned to "high" here; it follows what the model
    // actually believes.
    private static let hintSystemPrompt = systemPrompt + """


        HINT MODE: The user has offered a tentative guess about the subject BEFORE you saw the image. Treat their input as a leading hypothesis to consider first — useful for disambiguating between similar species — but you are NOT bound by it. If the visual evidence in the photograph clearly contradicts the user's guess, identify what you actually see and briefly note the discrepancy in safety_note (e.g. "User suggested X, but the image shows Y because …").

        Set model_confidence honestly based on what the photograph supports — do not force it to "high" just because the user offered a hint. If the photograph genuinely supports the user's guess, return their species; if it's ambiguous between their guess and a close alternative, list the alternative in alternatives[] and pick the better-supported one.

        The pose_description and color_palette fields describe the SPECIMEN ITSELF in this photograph (specimen pose and specimen colours only — never surroundings) and should be derived from the image as in normal mode. They do not depend on the hint.
        """

    private static func hintUserPrompt(
        commonName: String?,
        scientificName: String?
    ) -> String {
        let common = commonName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let scientific = scientificName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCommon = !(common?.isEmpty ?? true)
        let hasScientific = !(scientific?.isEmpty ?? true)
        switch (hasCommon, hasScientific) {
        case (true, true):
            return "The user suspects this may be \"\(common!)\" (Latin: \(scientific!)), but is not certain. Identify the subject of this image — use that as a leading hypothesis but override it if the photograph shows otherwise. Produce the JSON response."
        case (true, false):
            return "The user suspects the common name may be \"\(common!)\", but is not certain. Identify the subject of this image — use that as a leading hypothesis but override it if the photograph shows otherwise. Produce the JSON response."
        case (false, true):
            return "The user suspects the scientific name may be \"\(scientific!)\", but is not certain. Identify the subject of this image — use that as a leading hypothesis but override it if the photograph shows otherwise. Produce the JSON response."
        case (false, false):
            return userPrompt
        }
    }

    // MARK: - Parsing

    static func parseAndValidate(_ raw: String) throws -> IdentificationResult {
        let cleaned = stripCodeFences(raw.trimmingCharacters(in: .whitespacesAndNewlines))

        let json: String
        if let direct = decodeAttempt(cleaned) {
            json = direct
        } else if let extracted = extractOutermostObject(cleaned) {
            json = extracted
        } else {
            throw GemmaError.parseFailure("could not locate JSON object in output", raw: raw)
        }

        // Normalize "fungi" → "fungus". Gemma sometimes emits the plural
        // and IdentificationResult's Kingdom.parse would otherwise fall
        // through to .plant.
        let normalized = normalizeKingdom(in: json)

        guard let data = normalized.data(using: .utf8) else {
            throw GemmaError.parseFailure("output not UTF-8", raw: raw)
        }
        do {
            return try JSONDecoder().decode(IdentificationResult.self, from: data)
        } catch {
            throw GemmaError.parseFailure("decode failed: \(error.localizedDescription)", raw: raw)
        }
    }

    private static func decodeAttempt(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil
        else { return nil }
        return text
    }

    private static func stripCodeFences(_ text: String) -> String {
        guard text.hasPrefix("```") else { return text }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var start: Int?
        var end: Int?
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") && start == nil {
                start = i + 1
            } else if trimmed == "```" && start != nil {
                end = i
                break
            }
        }
        guard let s = start, let e = end, s < e else { return text }
        return lines[s..<e].joined(separator: "\n")
    }

    private static func extractOutermostObject(_ text: String) -> String? {
        guard let first = text.firstIndex(of: "{"),
              let last = text.lastIndex(of: "}"),
              first < last
        else { return nil }
        return String(text[first...last])
    }

    private static func normalizeKingdom(in json: String) -> String {
        json.replacingOccurrences(
            of: #""kingdom"\s*:\s*"fungi""#,
            with: #""kingdom": "fungus""#,
            options: .regularExpression
        )
    }
}
