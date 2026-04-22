import Foundation

// Single source of truth for selectable compounds + voice aliases.
// Aliases let users say "Ozempic" and have us pick "Semaglutide".
struct CompoundCatalog {

    struct Entry: Hashable, Identifiable {
        let canonical: String
        let category: Category
        let aliases: [String]
        var id: String { canonical }
    }

    enum Category: String, CaseIterable {
        case healing = "Healing"
        case ghSecretagogue = "GH / Growth"
        case fatLoss = "Metabolic"
        case other = "Other"
    }

    static let all: [Entry] = [
        // Healing & recovery
        .init(canonical: "BPC-157",          category: .healing, aliases: ["bpc", "b p c", "bpc 157", "bpc157"]),
        .init(canonical: "TB-500",           category: .healing, aliases: ["tb", "tb 500", "tb500", "thymosin beta"]),
        .init(canonical: "GHK-Cu",           category: .healing, aliases: ["ghk", "g h k", "ghk copper", "copper peptide"]),
        .init(canonical: "Thymosin Alpha-1", category: .healing, aliases: ["thymosin alpha", "thymosin", "ta1"]),

        // GH secretagogues
        .init(canonical: "Ipamorelin",       category: .ghSecretagogue, aliases: ["ipa", "ipamorelan"]),
        .init(canonical: "CJC-1295",         category: .ghSecretagogue, aliases: ["cjc", "c j c", "cjc 1295", "cjc1295"]),
        .init(canonical: "Sermorelin",       category: .ghSecretagogue, aliases: ["sermorlin"]),
        .init(canonical: "Tesamorelin",      category: .ghSecretagogue, aliases: ["tesa", "tesamorelan"]),
        .init(canonical: "GHRP-2",           category: .ghSecretagogue, aliases: ["ghrp 2", "ghrp two", "ghrp2"]),
        .init(canonical: "GHRP-6",           category: .ghSecretagogue, aliases: ["ghrp 6", "ghrp six", "ghrp6"]),
        .init(canonical: "Hexarelin",        category: .ghSecretagogue, aliases: ["hex"]),
        .init(canonical: "MK-677",           category: .ghSecretagogue, aliases: ["mk", "m k", "mk 677", "ibutamoren"]),

        // Metabolic / fat loss
        .init(canonical: "Tirzepatide",      category: .fatLoss, aliases: ["tirz", "mounjaro", "zepbound"]),
        .init(canonical: "Semaglutide",      category: .fatLoss, aliases: ["sema", "ozempic", "wegovy", "rybelsus"]),
        .init(canonical: "AOD-9604",         category: .fatLoss, aliases: ["aod", "a o d", "aod9604"]),
        .init(canonical: "Retatrutide",      category: .fatLoss, aliases: ["reta"]),

        // Other / cognitive / sexual
        .init(canonical: "PT-141",           category: .other, aliases: ["pt", "p t", "pt 141", "bremelanotide"]),
        .init(canonical: "Melanotan II",     category: .other, aliases: ["melanotan", "mt2", "mt 2", "tan peptide"]),
        .init(canonical: "Selank",           category: .other, aliases: []),
        .init(canonical: "Semax",            category: .other, aliases: []),
        .init(canonical: "Epithalon",        category: .other, aliases: ["epitalon"]),
        .init(canonical: "DSIP",             category: .other, aliases: ["d s i p"]),
        .init(canonical: "KPV",              category: .other, aliases: ["k p v"]),
        .init(canonical: "LL-37",            category: .other, aliases: ["l l 37"]),
    ]

    // Top picks shown as the default chip grid before "Show all".
    static let popular: [String] = [
        "BPC-157", "Tirzepatide", "Semaglutide", "Ipamorelin",
        "CJC-1295", "TB-500", "MK-677", "PT-141",
    ]

    // Vocabulary fed to SFSpeechRecognizer.contextualStrings to bias
    // recognition toward our weird unusual peptide names.
    static let speechVocabulary: [String] = {
        var v = Set<String>()
        for e in all {
            v.insert(e.canonical)
            v.insert(e.canonical.replacingOccurrences(of: "-", with: " "))
            for alias in e.aliases { v.insert(alias) }
        }
        return Array(v)
    }()

    // Find canonical compound names mentioned anywhere in `text`.
    // Matches canonical name OR any alias, normalized for casing/punctuation.
    static func match(in text: String) -> [String] {
        let haystack = normalize(text)
        guard !haystack.isEmpty else { return [] }
        var hits: [String] = []
        for entry in all {
            let candidates = [entry.canonical] + entry.aliases
            for c in candidates {
                let needle = normalize(c)
                guard !needle.isEmpty else { continue }
                if haystack.range(of: "\\b\(NSRegularExpression.escapedPattern(for: needle))\\b",
                                  options: .regularExpression) != nil {
                    hits.append(entry.canonical)
                    break
                }
            }
        }
        return hits
    }

    // Strip dashes / extra whitespace, lowercase. "BPC-157" → "bpc 157".
    static func normalize(_ s: String) -> String {
        let lower = s.lowercased()
        let scrubbed = lower
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: ",", with: " ")
        return scrubbed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
