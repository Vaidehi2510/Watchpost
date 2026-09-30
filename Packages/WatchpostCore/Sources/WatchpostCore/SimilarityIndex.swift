import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

public enum VectorMath {
    /// Cosine similarity in [-1, 1]. Returns 0 for empty, mismatched, or zero-length vectors.
    public static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        #if canImport(Accelerate)
        let dot = vDSP.dot(a, b)
        let normA = vDSP.sumOfSquares(a).squareRoot()
        let normB = vDSP.sumOfSquares(b).squareRoot()
        #else
        var dot = 0.0
        var sumA = 0.0
        var sumB = 0.0
        for i in a.indices {
            dot += a[i] * b[i]
            sumA += a[i] * a[i]
            sumB += b[i] * b[i]
        }
        let normA = sumA.squareRoot()
        let normB = sumB.squareRoot()
        #endif
        guard normA > 0, normB > 0 else { return 0 }
        return min(1, max(-1, dot / (normA * normB)))
    }
}

public struct SimilarityMatch: Hashable, Sendable {
    public let id: UUID
    public let score: Double

    public init(id: UUID, score: Double) {
        self.id = id
        self.score = score
    }
}

/// In-memory vector index with exact (brute-force) cosine search.
///
/// Exact search is the right call at personal-device scale (hundreds to low thousands of
/// incidents): it is simple, has no index-build step, and never returns approximate results.
public struct SimilarityIndex: Sendable {
    public private(set) var vectors: [UUID: [Double]] = [:]

    public init() {}

    public var count: Int { vectors.count }

    public func contains(_ id: UUID) -> Bool { vectors[id] != nil }

    public mutating func upsert(_ id: UUID, vector: [Double]) {
        vectors[id] = vector
    }

    public mutating func remove(_ id: UUID) {
        vectors[id] = nil
    }

    public mutating func removeAll() {
        vectors.removeAll()
    }

    /// Top-`k` most similar vectors, best first. Ties break on ID so results are stable.
    public func nearest(
        to query: [Double],
        k: Int = 3,
        excluding excluded: Set<UUID> = [],
        minimumScore: Double = 0
    ) -> [SimilarityMatch] {
        guard k > 0, !query.isEmpty else { return [] }
        var matches: [SimilarityMatch] = []
        matches.reserveCapacity(vectors.count)
        for (id, vector) in vectors where !excluded.contains(id) {
            let score = VectorMath.cosineSimilarity(query, vector)
            if score >= minimumScore {
                matches.append(SimilarityMatch(id: id, score: score))
            }
        }
        matches.sort { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.id.uuidString < rhs.id.uuidString
        }
        return Array(matches.prefix(k))
    }
}
