import XCTest
@testable import Peptide

final class GoalDetectorTests: XCTestCase {

    func test_recovery_phrases() {
        let cases = [
            "I want to recover from a knee injury",
            "I'm trying to heal my tendons",
            "Need help with joint pain",
            "rehabbing after surgery",
        ]
        for c in cases {
            XCTAssertTrue(GoalDetector.detect(in: c).contains("recovery"),
                          "should detect recovery in: \(c)")
        }
    }

    func test_fat_loss_phrases() {
        let cases = [
            "I want to lose 30 pounds",
            "trying to lose weight",
            "running tirzepatide for fat loss",
            "I want to slim down for summer",
        ]
        for c in cases {
            XCTAssertTrue(GoalDetector.detect(in: c).contains("fat_loss"),
                          "should detect fat_loss in: \(c)")
        }
    }

    func test_growth_phrases() {
        let cases = [
            "I want to gain muscle",
            "trying to get stronger",
            "build mass",
            "bulking right now",
        ]
        for c in cases {
            XCTAssertTrue(GoalDetector.detect(in: c).contains("growth"),
                          "should detect growth in: \(c)")
        }
    }

    func test_cognitive_phrases() {
        let cases = [
            "I want better focus and memory",
            "struggling with anxiety",
            "improve mental clarity",
        ]
        for c in cases {
            XCTAssertTrue(GoalDetector.detect(in: c).contains("cognitive"),
                          "should detect cognitive in: \(c)")
        }
    }

    func test_sleep_and_libido() {
        XCTAssertTrue(GoalDetector.detect(in: "my sleep is awful, also low libido").isSuperset(of: ["sleep", "libido"]))
    }

    func test_combined_goals() {
        let text = "I want to recover from a torn ACL and lose some fat"
        let hits = GoalDetector.detect(in: text)
        XCTAssertTrue(hits.contains("recovery"))
        XCTAssertTrue(hits.contains("fat_loss"))
    }

    func test_no_match_returns_empty() {
        XCTAssertEqual(GoalDetector.detect(in: "hello world"), [])
        XCTAssertEqual(GoalDetector.detect(in: ""), [])
    }

    func test_word_boundary_avoids_false_positives() {
        // "rest" alone fires for sleep, but should NOT fire on "restore"
        XCTAssertFalse(GoalDetector.detect(in: "I want to restore my faith").contains("sleep"))
    }

    // MARK: - Recommender integration

    func test_recommender_returns_relevant_compounds_for_recovery() {
        let recs = StackRecommender.recommend(goals: ["recovery"])
        XCTAssertFalse(recs.isEmpty)
        // BPC-157 is the canonical recovery peptide; should be in the top picks.
        XCTAssertTrue(recs.contains(where: { $0.compoundName == "BPC-157" }))
    }

    func test_recommender_caps_to_complexity() {
        let simple = StackRecommender.recommend(goals: ["recovery", "growth", "longevity"], complexity: .simple)
        XCTAssertLessThanOrEqual(simple.count, 2)
        let advanced = StackRecommender.recommend(goals: ["recovery", "growth", "longevity"], complexity: .advanced)
        XCTAssertLessThanOrEqual(advanced.count, 5)
    }

    func test_recommender_returns_empty_for_empty_goals() {
        XCTAssertTrue(StackRecommender.recommend(goals: []).isEmpty)
    }
}
