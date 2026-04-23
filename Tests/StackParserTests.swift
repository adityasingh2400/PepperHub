import XCTest
@testable import Peptide

final class StackParserTests: XCTestCase {

    // MARK: - End-to-end parse

    func test_classic_notes_paste_two_lines() {
        let input = """
        BPC-157 250mcg daily
        TB-500 5mg twice a week
        """
        let detected = StackParser.parse(input)
        XCTAssertEqual(detected.count, 2)
        let bpc = detected.first(where: { $0.compoundName == "BPC-157" })!
        XCTAssertEqual(bpc.doseMcg ?? 0, 250, accuracy: 0.01)
        XCTAssertEqual(bpc.frequency, "daily")
        let tb = detected.first(where: { $0.compoundName == "TB-500" })!
        XCTAssertEqual(tb.doseMcg ?? 0, 5_000, accuracy: 0.01)   // 5mg → 5000mcg
        XCTAssertEqual(tb.frequency, "2x_weekly")
    }

    func test_aliases_with_brand_names() {
        // "Mounjaro" → Tirzepatide, "Sema" → Semaglutide
        let input = "Mounjaro 5mg weekly. Sema 0.5 mg / wk."
        let detected = StackParser.parse(input)
        let names = Set(detected.map(\.compoundName))
        XCTAssertTrue(names.contains("Tirzepatide"))
        XCTAssertTrue(names.contains("Semaglutide"))
    }

    func test_bullet_separated_inventory_style() {
        let input = """
        • BPC-157 — 250 mcg, AM
        • Ipamorelin 200mcg, every other day
        • CJC-1295 100 mcg M/W/F
        """
        let detected = StackParser.parse(input)
        XCTAssertEqual(detected.count, 3)
        let ipa = detected.first(where: { $0.compoundName == "Ipamorelin" })!
        XCTAssertEqual(ipa.frequency, "eod")
        let cjc = detected.first(where: { $0.compoundName == "CJC-1295" })!
        XCTAssertEqual(cjc.frequency, "mwf")
    }

    func test_multiple_compounds_on_one_line_split_by_and() {
        let input = "BPC 250mcg daily and TB 5mg weekly"
        let detected = StackParser.parse(input)
        XCTAssertEqual(detected.count, 2)
    }

    func test_just_a_compound_name_with_no_dose() {
        // Should still surface the compound; defaults will fill in dose.
        let input = "I'm running BPC-157 right now"
        let detected = StackParser.parse(input)
        XCTAssertEqual(detected.count, 1)
        XCTAssertEqual(detected[0].compoundName, "BPC-157")
        XCTAssertNil(detected[0].doseMcg)
        XCTAssertLessThan(detected[0].confidence, 1)
    }

    // MARK: - Dose extraction

    func test_dose_mg_to_mcg_conversion() {
        XCTAssertEqual(StackParser.extractDoseMcg(in: "5 mg")!, 5_000, accuracy: 0.01)
        XCTAssertEqual(StackParser.extractDoseMcg(in: "0.5mg")!, 500, accuracy: 0.01)
    }

    func test_dose_decimal_and_european_comma() {
        XCTAssertEqual(StackParser.extractDoseMcg(in: "0.25 mg")!, 250, accuracy: 0.01)
        XCTAssertEqual(StackParser.extractDoseMcg(in: "0,25 mg")!, 250, accuracy: 0.01)
    }

    func test_dose_no_unit_returns_nil() {
        XCTAssertNil(StackParser.extractDoseMcg(in: "BPC 250 daily"))
    }

    // MARK: - Frequency extraction

    func test_frequency_variants() {
        XCTAssertEqual(StackParser.extractFrequency(in: "daily"),                 "daily")
        XCTAssertEqual(StackParser.extractFrequency(in: "every day"),             "daily")
        XCTAssertEqual(StackParser.extractFrequency(in: "every other day"),       "eod")
        XCTAssertEqual(StackParser.extractFrequency(in: "EOD"),                   "eod")
        XCTAssertEqual(StackParser.extractFrequency(in: "3x/week"),               "3x_weekly")
        XCTAssertEqual(StackParser.extractFrequency(in: "twice a week"),          "2x_weekly")
        XCTAssertEqual(StackParser.extractFrequency(in: "weekly"),                "weekly")
        XCTAssertEqual(StackParser.extractFrequency(in: "/ wk"),                  "weekly")
        XCTAssertEqual(StackParser.extractFrequency(in: "M/W/F"),                 "mwf")
        XCTAssertEqual(StackParser.extractFrequency(in: "Monday, Wednesday, Friday"), "mwf")
        XCTAssertEqual(StackParser.extractFrequency(in: "5 on / 2 off"),          "5on_2off")
    }

    func test_frequency_unknown_returns_nil() {
        XCTAssertNil(StackParser.extractFrequency(in: "I just like peptides"))
    }

    // MARK: - Voice transcript style

    func test_voice_style_with_numerals() {
        // Most speech-to-text engines (including Apple's) emit numerals like
        // "250" rather than spelled-out "two hundred fifty" when the
        // surrounding context is unit-like. We test the realistic case here.
        let input = "i have bpc 157 250 mcg daily and tirzepatide 5 mg weekly"
        let detected = StackParser.parse(input)
        let names = Set(detected.map(\.compoundName))
        XCTAssertTrue(names.contains("BPC-157"))
        XCTAssertTrue(names.contains("Tirzepatide"))
        let bpc = detected.first(where: { $0.compoundName == "BPC-157" })!
        XCTAssertEqual(bpc.doseMcg ?? 0, 250, accuracy: 0.01)
        XCTAssertEqual(bpc.frequency, "daily")
    }

    // MARK: - Run-together + STT mishearing recovery

    /// Real-world transcript that the user tested: "MOTS-c, GHK-Cu, and
    /// CJC/Ipamorelin blend with no DAC". Apple's STT mangled MOTS-c to
    /// "Mazi" and ran GHK-Cu together as "GHKCU". Both must still be picked
    /// up via fuzzy + alias matching.
    func test_run_together_aliases() {
        // GHKCU should match GHK-Cu via collapsed alias
        let names = CompoundCatalog.match(in: "I run GHKCU twice a week")
        XCTAssertTrue(names.contains("GHK-Cu"), "should match collapsed GHKCU → GHK-Cu")
    }

    func test_mots_c_added_to_catalog() {
        let names = CompoundCatalog.match(in: "I run mots-c daily")
        XCTAssertTrue(names.contains("MOTS-c"))
    }

    func test_mots_c_via_stt_mishearing() {
        // "Mazi" is what Apple STT heard for "MOTS-c" — fuzzy matcher should
        // recover it.
        let names = CompoundCatalog.match(in: "number one is mazi")
        XCTAssertTrue(names.contains("MOTS-c"), "fuzzy should recover mazi → MOTS-c")
    }

    func test_ipa_merlin_recovers_to_ipamorelin() {
        // STT heard "ipa Merlin" for "Ipamorelin". Already worked via "ipa"
        // alias but lock it into the test suite so we don't regress.
        let names = CompoundCatalog.match(in: "blend of cjc and ipa merlin")
        XCTAssertTrue(names.contains("Ipamorelin"))
        XCTAssertTrue(names.contains("CJC-1295"))
    }

    func test_full_real_world_voice_transcript() {
        // The exact transcript from the user's test session.
        let input = """
        I want I currently do three peptides number one Mazi number two is \
        GHKCU and number three is a blend of cjc an ipa Merlin with no DAC
        """
        let names = Set(CompoundCatalog.match(in: input))
        XCTAssertTrue(names.contains("MOTS-c"),     "should recover MOTS-c from 'Mazi'")
        XCTAssertTrue(names.contains("GHK-Cu"),     "should recover GHK-Cu from 'GHKCU'")
        XCTAssertTrue(names.contains("CJC-1295"))
        XCTAssertTrue(names.contains("Ipamorelin"), "should recover Ipamorelin from 'ipa Merlin'")
    }

    // MARK: - False-positive guards

    func test_common_english_does_not_match_compounds() {
        // "I am pretty" sounds remotely like "Ipamorelin" — must NOT match.
        let names = CompoundCatalog.match(in: "I am pretty sure I want a workout")
        XCTAssertFalse(names.contains("Ipamorelin"))
    }

    func test_short_words_dont_false_positive() {
        // "tea" should not become TB-500.
        let names = CompoundCatalog.match(in: "I had some tea this morning")
        XCTAssertTrue(names.isEmpty, "should not pick up anything; got \(names)")
    }
}
