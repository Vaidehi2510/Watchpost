import XCTest
@testable import WatchpostCore

final class VectorMathTests: XCTestCase {
    func testIdenticalVectorsScoreOne() {
        XCTAssertEqual(VectorMath.cosineSimilarity([1, 2, 3], [1, 2, 3]), 1, accuracy: 1e-9)
    }

    func testOrthogonalVectorsScoreZero() {
        XCTAssertEqual(VectorMath.cosineSimilarity([1, 0], [0, 1]), 0, accuracy: 1e-9)
    }

    func testOppositeVectorsScoreMinusOne() {
        XCTAssertEqual(VectorMath.cosineSimilarity([1, 1], [-1, -1]), -1, accuracy: 1e-9)
    }

    func testMismatchedEmptyAndZeroVectorsScoreZero() {
        XCTAssertEqual(VectorMath.cosineSimilarity([1, 2], [1, 2, 3]), 0)
        XCTAssertEqual(VectorMath.cosineSimilarity([], []), 0)
        XCTAssertEqual(VectorMath.cosineSimilarity([0, 0], [1, 1]), 0)
    }
}

final class HashingEmbedderTests: XCTestCase {
    let embedder = HashingEmbedder(dimension: 256)

    func testIsDeterministic() {
        let text = "VPN tunnel drops after certificate rotation"
        XCTAssertEqual(embedder.embed(text), embedder.embed(text))
        XCTAssertEqual(embedder.embed(text)?.count, 256)
    }

    func testEmptyOrStopwordOnlyTextHasNoVector() {
        XCTAssertNil(embedder.embed(""))
        XCTAssertNil(embedder.embed("the and of"))
    }

    func testRelatedTextScoresHigherThanUnrelatedText() throws {
        let query = try XCTUnwrap(embedder.embed("VPN tunnel drops after certificate rotation"))
        let related = try XCTUnwrap(embedder.embed("VPN tunnel flapping following certificate renewal"))
        let unrelated = try XCTUnwrap(embedder.embed("Payroll spreadsheet shared publicly"))
        XCTAssertGreaterThan(
            VectorMath.cosineSimilarity(query, related),
            VectorMath.cosineSimilarity(query, unrelated)
        )
    }
}

final class SimilarityIndexTests: XCTestCase {
    let a = UUID(), b = UUID(), c = UUID()

    func makeIndex() -> SimilarityIndex {
        var index = SimilarityIndex()
        index.upsert(a, vector: [1, 0, 0])
        index.upsert(b, vector: [0.9, 0.1, 0])
        index.upsert(c, vector: [0, 0, 1])
        return index
    }

    func testReturnsNearestFirst() {
        let results = makeIndex().nearest(to: [1, 0, 0], k: 3)
        XCTAssertEqual(results.map(\.id), [a, b, c])
    }

    func testRespectsKExclusionAndMinimumScore() {
        let index = makeIndex()
        XCTAssertEqual(index.nearest(to: [1, 0, 0], k: 1).map(\.id), [a])
        XCTAssertEqual(index.nearest(to: [1, 0, 0], k: 3, excluding: [a]).first?.id, b)
        XCTAssertEqual(index.nearest(to: [1, 0, 0], k: 3, minimumScore: 0.5).map(\.id), [a, b])
    }

    func testUpsertReplacesAndRemoveDeletes() {
        var index = makeIndex()
        index.upsert(c, vector: [1, 0, 0])
        XCTAssertEqual(index.count, 3)
        index.remove(a)
        XCTAssertFalse(index.contains(a))
        XCTAssertEqual(index.count, 2)
    }

    func testDegenerateQueriesReturnNothing() {
        let index = makeIndex()
        XCTAssertTrue(index.nearest(to: [], k: 3).isEmpty)
        XCTAssertTrue(index.nearest(to: [1, 0, 0], k: 0).isEmpty)
    }
}

/// Run with `swift test --filter PerformanceTests` (or in Xcode) to get the numbers
/// quoted in the README. 512 dimensions matches NLEmbedding's sentence vectors.
final class PerformanceTests: XCTestCase {
    func testExactTopKOver5kVectors() {
        var generator = SplitMix64(seed: 42)
        var index = SimilarityIndex()
        for _ in 0..<5_000 {
            index.upsert(UUID(), vector: (0..<512).map { _ in generator.nextUnit() })
        }
        let query = (0..<512).map { _ in generator.nextUnit() }
        measure {
            _ = index.nearest(to: query, k: 5)
        }
    }
}

/// Small seeded PRNG so benchmark inputs are identical on every run.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [-1, 1).
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53) * 2 - 1
    }
}
