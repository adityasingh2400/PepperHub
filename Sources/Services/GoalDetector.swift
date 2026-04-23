import Foundation

/// Extracts `GoalCategoryCatalog` IDs from free-form natural-language text.
///
/// Companion to `StackParser` — where StackParser asks "what compounds are in
/// this text?", GoalDetector asks "what is this person trying to *do*?". Used
/// by the voice-import flow so saying *"I want to recover from a knee injury
/// and lose some fat"* maps to `["recovery", "fat_loss"]`, which then flows
/// into `StackRecommender` to pick compounds.
///
/// Why no LLM:
///   The vocabulary of peptide goals is narrow and well-trodden — recovery,
///   fat loss, libido, sleep, etc. A keyword-driven regex matcher hits the
///   common phrasing reliably and runs offline in microseconds. We keep the
///   LLM lever (PepperService) for actually-fuzzy questions.
enum GoalDetector {

    /// Returns the union of goal IDs we can confidently infer from the text.
    /// If nothing matches, returns an empty set — callers should treat that
    /// as "nothing detected" rather than "empty selection".
    static func detect(in raw: String) -> Set<String> {
        let lower = raw.lowercased()
        guard !lower.isEmpty else { return [] }
        var hits: Set<String> = []
        for (goalId, patterns) in patternsByGoal {
            for pattern in patterns {
                // Word-boundary match so "rest" doesn't fire on "restore".
                let regex = "\\b(?:\(pattern))\\b"
                if lower.range(of: regex, options: .regularExpression) != nil {
                    hits.insert(goalId)
                    break
                }
            }
        }
        return hits
    }

    /// Goal ID → list of regex *alternation* fragments. Each fragment is a
    /// piece of natural-language phrasing we want to hit. Order doesn't
    /// matter; we OR them together at match time.
    ///
    /// Goal IDs match `GoalCategoryCatalog`:
    ///   recovery, growth, fat_loss, longevity, cognitive,
    ///   libido, skin_hair, immune, sleep
    private static let patternsByGoal: [String: [String]] = [
        "recovery": [
            "recover(?:ing|y)?",
            "heal(?:ing)?",
            "injur(?:y|ies|ed)",
            "tendon(?:s|itis)?",
            "ligament(?:s)?",
            "joint(?:s)?",
            "knee(?:s)?",
            "shoulder(?:s)?",
            "back pain",
            "gut",
            "stomach",
            "leaky gut",
            "ibs",
            "repair",
            "rehab(?:bing)?",
            "post[ -]?(?:workout|surgery|injury)"
        ],
        "growth": [
            "muscle(?:s)?",
            "mass",
            "bigger",
            "build(?:ing)? muscle",
            "gain(?:s)?",
            "size",
            "lean mass",
            "hypertrophy",
            "stronger",
            "strength",
            "gh ?pulse",
            "growth hormone",
            "igf",
            "bulk(?:ing)?",
            "anabolic"
        ],
        "fat_loss": [
            "fat ?loss",
            // `lose 30 pounds`, `lose some fat`, `lose weight` — allow up to 3
            // intervening words (numbers, "some", "a few"…) before the noun.
            "lose(?:\\s+\\w+){0,3}\\s+(?:weight|fat|pounds|lbs|kg)",
            "losing(?:\\s+\\w+){0,3}\\s+(?:weight|fat|pounds|lbs|kg)",
            "weight ?loss",
            "slim(?:mer|ming)? down",
            "slim(?:mer)?",
            "lean(?:er)?",
            "cut(?:ting)?",
            "appetite",
            "hunger",
            "glp[ -]?1?",
            "ozempic",
            "semaglutide",
            "tirzepatide",
            "mounjaro",
            "zepbound"
        ],
        "longevity": [
            "longevity",
            "anti[ -]?ag(?:e|ing)",
            "live longer",
            "telomere(?:s)?",
            "cellular",
            "mitochondria(?:l)?",
            "epigenetic",
            "biological age",
            "healthspan",
            "lifespan"
        ],
        "cognitive": [
            "focus(?:ed)?",
            "memory",
            "mood",
            "brain",
            "cognitive",
            "cognition",
            "think(?:ing)? clearly",
            "mental clarity",
            "anxiety",
            "anxious",
            "depression",
            "depressed",
            "neuro(?:protection|protective)?",
            "nootropic"
        ],
        "libido": [
            "libido",
            "sex(?:ual)? (?:drive|function|performance)",
            "ed",          // erectile dysfunction
            "erection(?:s)?",
            "horny",
            "arousal"
        ],
        "skin_hair": [
            "skin",
            "complexion",
            "wrinkle(?:s)?",
            "fine lines",
            "collagen",
            "hair",
            "hairline",
            "hair loss",
            "hair growth",
            "thinning hair",
            "regrow"
        ],
        "immune": [
            "immune",
            "immunity",
            "antimicrobial",
            "infection(?:s)?",
            "sick (?:often|all the time)",
            "auto[ -]?immune"
        ],
        "sleep": [
            "sleep(?:ing)?",
            "rest(?:ful)?",
            "insomnia",
            "deep sleep",
            "rem sleep",
            "tired all the time",
            "fatigue(?:d)?",
            "exhaust(?:ed|ion)"
        ],
    ]
}
