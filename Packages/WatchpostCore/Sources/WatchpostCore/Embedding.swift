import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Turns text into a fixed-length vector. Implementations must be deterministic
/// for a given `identifier`, because vectors are cached on disk keyed by it.
public protocol TextEmbedder: Sendable {
    /// Stable ID for the model + version. When it changes, cached vectors are recomputed.
    var identifier: String { get }
    func embed(_ text: String) -> [Double]?
}

/// Lowercases, splits on anything that is not a letter or digit, and drops stopwords.
public enum Tokenizer {
    static let stopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "has", "have",
        "in", "into", "is", "of", "on", "or", "that", "the", "this", "to", "was", "were", "with"
    ]

    public static func tokens(in text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 2 && !stopwords.contains($0) }
    }
}

/// Dependency-free fallback embedder (signed feature hashing over tokens).
///
/// Used when the NaturalLanguage sentence model is unavailable, and in unit tests,
/// because its output is fully deterministic across runs and platforms.
public struct HashingEmbedder: TextEmbedder {
    public let dimension: Int

    public init(dimension: Int = 256) {
        precondition(dimension > 0, "dimension must be positive")
        self.dimension = dimension
    }

    public var identifier: String { "hashing-\(dimension)" }

    public func embed(_ text: String) -> [Double]? {
        let tokens = Tokenizer.tokens(in: text)
        guard !tokens.isEmpty else { return nil }
        var vector = [Double](repeating: 0, count: dimension)
        for token in tokens {
            let hash = Self.fnv1a(token)
            let bucket = Int(hash % UInt64(dimension))
            let sign: Double = (hash >> 63) == 0 ? 1 : -1
            vector[bucket] += sign
        }
        return vector
    }

    /// 64-bit FNV-1a. Swift's `hashValue` is seeded per process, so it can't be cached.
    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

#if canImport(NaturalLanguage)
/// On-device sentence embeddings from Apple's NaturalLanguage framework. No network calls.
public final class SentenceEmbedder: TextEmbedder, @unchecked Sendable {
    // NLEmbedding is not documented as thread-safe, so access is serialized.
    private let embedding: NLEmbedding
    private let lock = NSLock()
    public let identifier: String

    public init?(language: NLLanguage = .english) {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: language) else { return nil }
        self.embedding = embedding
        self.identifier = "nl-sentence-\(language.rawValue)-r\(embedding.revision)"
    }

    public func embed(_ text: String) -> [Double]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return embedding.vector(for: trimmed)
    }
}
#endif

public enum EmbedderFactory {
    /// The best embedder available on this device: NaturalLanguage if present, else hashing.
    public static func best() -> any TextEmbedder {
        #if canImport(NaturalLanguage)
        if let sentence = SentenceEmbedder() {
            return sentence
        }
        #endif
        return HashingEmbedder()
    }
}
