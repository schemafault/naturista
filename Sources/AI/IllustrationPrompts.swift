import Foundation

// User-editable Flux illustration prompts. Swift owns the defaults and
// the placeholder substitution; FluxActor calls render() with the
// fully-formed IdentificationResult and feeds the resulting string
// straight to Flux2Pipeline. Edits are stored in UserDefaults under
// `flux.kingdomTemplates` as a {kingdom: string} JSON dictionary;
// missing keys fall back to the built-in default.

enum IllustrationPrompts {
    static let allowedPlaceholders: Set<String> = [
        "scientific_name", "common_name", "subject",
        "pose", "colors", "setting",
    ]

    // Layout: identity → specimen-only hints (pose / colors) → style
    // references → fallback subject summary → strong blank-paper anchor.
    // The {setting} placeholder is intentionally gone — every default
    // template now anchors hard on "specimen alone on paper" so FLUX
    // doesn't paint a habitat into the background.
    static let defaults: [Kingdom: String] = [
        .plant: """
            A hand-coloured botanical illustration of {scientific_name}, {common_name}, \
            shown {pose}, with {colors}. \
            In the style of Ferdinand Bauer and Pierre-Joseph Redouté — 19th century natural history plates \
            with delicate watercolour washes, fine ink linework, and accurate botanical detail. \
            {subject}. \
            The specimen sits alone on the paper. The paper is entirely blank — no environment, no scenery, no foliage, no shadow beyond the specimen itself, unmarked margins. Cream paper, smooth uninterrupted surface.
            """,
        .animal: """
            A hand-coloured zoological plate of {scientific_name}, {common_name}, \
            shown {pose}, with {colors}. \
            In the style of John James Audubon's Birds of America and John Gould's monographs — \
            19th century natural history with rich watercolour pigments, careful anatomical detail, \
            and a poised lifelike pose. Full colour, never grayscale or sepia. \
            {subject}. \
            The specimen sits alone on the paper. The paper is entirely blank — no environment, no scenery, no foliage, no shadow beyond the specimen itself, unmarked margins. Cream paper, smooth uninterrupted surface.
            """,
        .fungus: """
            A hand-coloured mycological plate of {scientific_name}, {common_name}, \
            shown {pose}, with {colors}. \
            In the style of Anna Maria Hussey and the Victorian fungal monographs — \
            soft watercolour with careful attention to gill colour and cap texture, \
            showing the whole specimen alongside a cross-section view. \
            {subject}. \
            The specimen sits alone on the paper. The paper is entirely blank — no environment, no scenery, no foliage, no shadow beyond the specimen itself, unmarked margins. Cream paper, smooth uninterrupted surface.
            """,
        .other: """
            A hand-painted Dutch Golden Age still-life study of {common_name}, \
            arranged {pose}, with {colors}. \
            In the style of Pieter Claesz and Willem Kalf — chiaroscuro oil painting \
            with warm side lighting, deep shadows, and rich saturated colour. \
            {subject}. \
            Against a smooth dark muted backdrop, unmarked surface.
            """,
    ]

    // Frozen — not user-editable. Used when visible_evidence is too sparse to
    // make a meaningful subject string (matches the prior Python behaviour).
    private static let fallbackSubjects: [Kingdom: String] = [
        .plant: "with characteristic leaves, stem, and flowering parts",
        .animal: "in a natural posture showing distinctive markings",
        .fungus: "with cap, stem, and gills clearly visible",
        .other: "rendered in careful realistic detail",
    ]

    // Per-kingdom phrases substituted in when Gemma left a hint field
    // empty (older entries, or photos too cropped to describe). Keep
    // these grammatically compatible with the surrounding template
    // sentence: "shown {pose}, with {colors}."
    private static let fallbackPoses: [Kingdom: String] = [
        .plant: "in characteristic posture",
        .animal: "in a relaxed natural pose",
        .fungus: "with the whole specimen visible",
        .other: "in a clear focused arrangement",
    ]

    private static let fallbackColors: [Kingdom: String] = [
        .plant: "naturalistic colouration",
        .animal: "lifelike natural colours",
        .fungus: "characteristic colouration",
        .other: "realistic colour",
    ]

    static func defaultTemplate(for kingdom: Kingdom) -> String {
        defaults[kingdom] ?? defaults[.plant]!
    }

    static func fallbackSubject(for kingdom: Kingdom) -> String {
        fallbackSubjects[kingdom] ?? fallbackSubjects[.plant]!
    }

    // Returns the unknown placeholder names found in the template (empty set
    // means the template is safe to render). Allows missing required tokens —
    // a user may intentionally drop {subject} from a stylistic prompt.
    static func unknownPlaceholders(in template: String) -> Set<String> {
        let pattern = #"\{([A-Za-z_][A-Za-z0-9_]*)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(template.startIndex..., in: template)
        var found = Set<String>()
        regex.enumerateMatches(in: template, range: range) { match, _, _ in
            guard let match, match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: template) else { return }
            let name = String(template[r])
            if !allowedPlaceholders.contains(name) {
                found.insert(name)
            }
        }
        return found
    }

    // Renders a template against an IdentificationResult. Falls back to
    // "the subject" / kingdom-specific phrases when fields are missing or
    // visibleEvidence is too thin. Pose / colors come from Gemma's photo
    // description. {setting} substitution is kept for backward compat with
    // user-customised templates that still reference it — it now resolves
    // to the empty string and any leftover "Setting suggests ." stub is
    // stripped by the post-render cleanup below.
    static func render(template: String, identification: IdentificationResult) -> String {
        let kingdom = Kingdom.parse(identification.kingdom)
        let common = identification.topCandidate.commonName.isEmpty
            ? "the subject"
            : identification.topCandidate.commonName
        let scientific = identification.topCandidate.scientificName.isEmpty
            ? common
            : identification.topCandidate.scientificName

        var subject = identification.visibleEvidence.joined(separator: "; ")
        if subject.count < 20 {
            subject = fallbackSubject(for: kingdom)
        }

        let pose = identification.poseDescription.isEmpty
            ? (fallbackPoses[kingdom] ?? fallbackPoses[.plant]!)
            : identification.poseDescription
        let colors = identification.colorPalette.isEmpty
            ? (fallbackColors[kingdom] ?? fallbackColors[.plant]!)
            : identification.colorPalette

        let substituted = template
            .replacingOccurrences(of: "{scientific_name}", with: scientific)
            .replacingOccurrences(of: "{common_name}", with: common)
            .replacingOccurrences(of: "{subject}", with: subject)
            .replacingOccurrences(of: "{pose}", with: pose)
            .replacingOccurrences(of: "{colors}", with: colors)
            .replacingOccurrences(of: "{setting}", with: "")

        return cleanupLegacySettingClause(substituted)
    }

    // Strips the "Setting suggests ." stub left by an empty {setting}
    // substitution in user-customised templates carried over from before
    // the setting field was retired. Tolerates surrounding whitespace and
    // collapses the resulting double space.
    private static func cleanupLegacySettingClause(_ text: String) -> String {
        let pattern = #"\s*Setting suggests\s*\.\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        let cleaned = regex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
        return cleaned
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// Persists per-kingdom overrides in UserDefaults. Reads return nil when the
// user hasn't customised a kingdom — callers fall through to the default.
final class IllustrationPromptStore {
    static let shared = IllustrationPromptStore()

    private let defaultsKey = "flux.kingdomTemplates"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // Returns the user's override for a kingdom, or the built-in default if
    // none. This is what FluxActor calls on every generate.
    func template(for kingdom: Kingdom) -> String {
        overrides()[kingdom.rawValue] ?? IllustrationPrompts.defaultTemplate(for: kingdom)
    }

    func override(for kingdom: Kingdom) -> String? {
        overrides()[kingdom.rawValue]
    }

    func setOverrides(_ next: [Kingdom: String]) {
        // Only persist values that actually differ from the default — this
        // keeps the stored dict tidy and means a future change to a default
        // automatically flows through to users who hadn't customised it.
        var filtered: [String: String] = [:]
        for (kingdom, value) in next {
            if value != IllustrationPrompts.defaultTemplate(for: kingdom) {
                filtered[kingdom.rawValue] = value
            }
        }
        userDefaults.set(filtered, forKey: defaultsKey)
    }

    func clearAll() {
        userDefaults.removeObject(forKey: defaultsKey)
    }

    private func overrides() -> [String: String] {
        (userDefaults.dictionary(forKey: defaultsKey) as? [String: String]) ?? [:]
    }
}
