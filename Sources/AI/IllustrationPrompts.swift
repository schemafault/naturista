import Foundation

// User-editable Flux illustration prompts. Swift owns the defaults and the
// {scientific_name}/{common_name}/{subject} substitution; Python receives
// the fully-rendered prompt via the existing `prompt` RPC field. Edits are
// stored in UserDefaults under `flux.kingdomTemplates` as a {kingdom: string}
// JSON dictionary; missing keys fall back to the built-in default.

enum IllustrationPrompts {
    static let allowedPlaceholders: Set<String> = ["scientific_name", "common_name", "subject"]

    static let defaults: [Kingdom: String] = [
        .plant: """
            A hand-coloured botanical illustration of {scientific_name}, {common_name}, \
            in the style of Ferdinand Bauer and Pierre-Joseph Redouté — 19th century natural history plates \
            with delicate watercolour washes, fine ink linework, and accurate botanical detail. \
            {subject}. \
            On plain neutral paper background. No text, no labels, no border.
            """,
        .animal: """
            A hand-coloured zoological plate of {scientific_name}, {common_name}, \
            in the style of John James Audubon's Birds of America and John Gould's monographs — \
            19th century natural history with rich watercolour pigments, careful anatomical detail, \
            and a poised lifelike pose. Full colour, never grayscale or sepia. \
            {subject}. \
            On plain neutral paper background. No text, no labels, no border.
            """,
        .fungus: """
            A hand-coloured mycological plate of {scientific_name}, {common_name}, \
            in the style of Anna Maria Hussey and the Victorian fungal monographs — \
            soft watercolour with careful attention to gill colour and cap texture, \
            showing the whole specimen alongside a cross-section view. \
            {subject}. \
            On plain neutral paper background. No text, no labels, no border.
            """,
        .other: """
            A hand-painted Dutch Golden Age still-life study of {common_name}, \
            in the style of Pieter Claesz and Willem Kalf — chiaroscuro oil painting \
            with warm side lighting, deep shadows, and rich saturated colour. \
            {subject}. \
            On a dark muted background. No text, no labels, no border.
            """,
    ]

    // Frozen — not user-editable. Used when visible_evidence is too sparse to
    // make a meaningful subject string (matches Python's previous behaviour).
    private static let fallbackSubjects: [Kingdom: String] = [
        .plant: "with characteristic leaves, stem, and flowering parts",
        .animal: "in a natural posture showing distinctive markings",
        .fungus: "with cap, stem, and gills clearly visible",
        .other: "rendered in careful realistic detail",
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

    // Renders a template against an IdentificationResult. Mirrors Python's
    // previous build_prompt logic — falls back to "the subject" / kingdom
    // fallback subject when fields are missing or visibleEvidence is too thin.
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

        return template
            .replacingOccurrences(of: "{scientific_name}", with: scientific)
            .replacingOccurrences(of: "{common_name}", with: common)
            .replacingOccurrences(of: "{subject}", with: subject)
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
