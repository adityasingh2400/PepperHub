import Foundation

struct Compound: Codable, Identifiable {
    let id: UUID
    let name: String
    let slug: String
    let halfLifeHrs: Double?
    let dosingRangeLowMcg: Double?
    let dosingRangeHighMcg: Double?
    let benefits: [String]
    let sideEffects: [String]
    let stackingNotes: String?
    let fdaStatus: FDAStatus
    let summaryMd: String?

    enum FDAStatus: String, Codable {
        case research, grey, approved
    }

    enum CodingKeys: String, CodingKey {
        case id, name, slug
        case halfLifeHrs = "half_life_hrs"
        case dosingRangeLowMcg = "dosing_range_low_mcg"
        case dosingRangeHighMcg = "dosing_range_high_mcg"
        case benefits
        case sideEffects = "side_effects"
        case stackingNotes = "stacking_notes"
        case fdaStatus = "fda_status"
        case summaryMd = "summary_md"
    }
}

// Seed data for the gate submission — no Supabase needed for App Store review
extension Compound {
    static let seedData: [Compound] = [
        Compound(
            id: UUID(),
            name: "Ipamorelin",
            slug: "ipamorelin",
            halfLifeHrs: 2,
            dosingRangeLowMcg: 100,
            dosingRangeHighMcg: 300,
            benefits: ["Growth hormone release", "Improved sleep quality", "Lean muscle support", "Fat loss"],
            sideEffects: ["Mild hunger increase", "Water retention", "Headache (dose-dependent)"],
            stackingNotes: "Commonly stacked with CJC-1295 for amplified GH pulse.",
            fdaStatus: .research,
            summaryMd: "Ipamorelin is a selective growth hormone secretagogue and ghrelin mimetic. It stimulates GH release without significantly affecting cortisol or prolactin, making it one of the cleaner options in the GH peptide class."
        ),
        Compound(
            id: UUID(),
            name: "CJC-1295",
            slug: "cjc-1295",
            halfLifeHrs: 168,
            dosingRangeLowMcg: 100,
            dosingRangeHighMcg: 200,
            benefits: ["Sustained GH elevation", "Improved recovery", "Increased IGF-1"],
            sideEffects: ["Water retention", "Fatigue", "Injection site reaction"],
            stackingNotes: "Paired with Ipamorelin for synergistic GH pulse amplification.",
            fdaStatus: .research,
            summaryMd: "CJC-1295 (with DAC) is a long-acting GHRH analogue. The DAC (Drug Affinity Complex) extends half-life to approximately 7 days, allowing weekly dosing."
        ),
        Compound(
            id: UUID(),
            name: "BPC-157",
            slug: "bpc-157",
            halfLifeHrs: 4,
            dosingRangeLowMcg: 250,
            dosingRangeHighMcg: 500,
            benefits: ["Tendon and ligament repair", "Gut health", "Anti-inflammatory", "Wound healing"],
            sideEffects: ["Generally well tolerated", "Mild nausea (rare)"],
            stackingNotes: "Can be stacked with TB-500 for enhanced tissue repair.",
            fdaStatus: .research,
            summaryMd: "BPC-157 (Body Protection Compound 157) is a synthetic peptide derived from a protein found in gastric juice. Primarily researched for tissue repair, particularly tendons, ligaments, and the GI tract."
        ),
        Compound(
            id: UUID(),
            name: "TB-500",
            slug: "tb-500",
            halfLifeHrs: 96,
            dosingRangeLowMcg: 2000,
            dosingRangeHighMcg: 5000,
            benefits: ["Systemic tissue repair", "Reduced inflammation", "Improved flexibility", "Cardiovascular recovery"],
            sideEffects: ["Fatigue", "Head rush", "Nausea at higher doses"],
            stackingNotes: "Often combined with BPC-157 for comprehensive injury recovery.",
            fdaStatus: .research,
            summaryMd: "TB-500 is a synthetic version of Thymosin Beta-4, a naturally occurring peptide present in nearly all human cells. Research focuses on its role in cell migration, proliferation, and differentiation for tissue repair."
        ),
        Compound(
            id: UUID(),
            name: "Semaglutide",
            slug: "semaglutide",
            halfLifeHrs: 168,
            dosingRangeLowMcg: 250,
            dosingRangeHighMcg: 2400,
            benefits: ["Significant weight loss", "Blood sugar regulation", "Appetite suppression", "Cardiovascular benefit"],
            sideEffects: ["Nausea", "Vomiting", "Diarrhea", "Constipation", "Injection site reaction"],
            stackingNotes: "Not typically stacked. Monitor for hypoglycemia if combining with other glucose-lowering agents.",
            fdaStatus: .approved,
            summaryMd: "Semaglutide is an FDA-approved GLP-1 receptor agonist (Ozempic, Wegovy). Originally developed for type 2 diabetes, it is now approved for chronic weight management. Weekly subcutaneous injection."
        ),
    ]
}
