import Foundation

/// One selectable speech model.
public struct ModelDescriptor: Identifiable, Hashable, Sendable {
    public enum Tier: Int, Comparable, Sendable {
        case low
        case medium
        case high
        case highest

        public static func < (lhs: Tier, rhs: Tier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        public var label: String {
            switch self {
            case .low: "Basic"
            case .medium: "Good"
            case .high: "Great"
            case .highest: "Best"
            }
        }
    }

    public let id: String
    public let engine: EngineID
    public let displayName: String
    public let summary: String

    /// Approximate on-disk size. Zero for models that need no download.
    public let downloadBytes: Int64

    /// Rough guidance so the picker can warn before a model is chosen on a
    /// machine that will struggle with it.
    public let recommendedMemoryGB: Int

    public let speed: Tier
    public let accuracy: Tier

    /// `false` for English-only variants.
    public let isMultilingual: Bool

    /// Whether choosing this model costs a download.
    public var requiresDownload: Bool { downloadBytes > 0 }

    public init(
        id: String,
        engine: EngineID,
        displayName: String,
        summary: String,
        downloadBytes: Int64,
        recommendedMemoryGB: Int,
        speed: Tier,
        accuracy: Tier,
        isMultilingual: Bool
    ) {
        self.id = id
        self.engine = engine
        self.displayName = displayName
        self.summary = summary
        self.downloadBytes = downloadBytes
        self.recommendedMemoryGB = recommendedMemoryGB
        self.speed = speed
        self.accuracy = accuracy
        self.isMultilingual = isMultilingual
    }
}

/// The predefined set of models Metagraf offers.
///
/// Deliberately curated rather than exposing every Whisper variant: a long list
/// of near-identical checkpoints is a worse experience than a few known-good
/// choices with honest trade-offs stated.
public enum ModelCatalog {
    /// Apple's system transcriber. No download, lowest latency, live text.
    public static let appleSpeech = ModelDescriptor(
        id: "apple.speech",
        engine: .appleSpeech,
        displayName: "Apple Speech",
        summary: "Built into macOS. Shows words as you speak and needs no download.",
        downloadBytes: 0,
        recommendedMemoryGB: 0,
        speed: .highest,
        accuracy: .high,
        isMultilingual: true
    )

    public static let whisperModels: [ModelDescriptor] = [
        ModelDescriptor(
            id: "tiny",
            engine: .whisperKit,
            displayName: "Whisper Tiny",
            summary: "Fastest and smallest. Fine for short, clear dictation.",
            downloadBytes: 78_000_000,
            recommendedMemoryGB: 4,
            speed: .highest,
            accuracy: .low,
            isMultilingual: true
        ),
        ModelDescriptor(
            id: "base",
            engine: .whisperKit,
            displayName: "Whisper Base",
            summary: "A noticeable step up from Tiny at a modest cost.",
            downloadBytes: 145_000_000,
            recommendedMemoryGB: 4,
            speed: .high,
            accuracy: .medium,
            isMultilingual: true
        ),
        ModelDescriptor(
            id: "small",
            engine: .whisperKit,
            displayName: "Whisper Small",
            summary: "A good balance of accuracy and speed for everyday use.",
            downloadBytes: 483_000_000,
            recommendedMemoryGB: 8,
            speed: .medium,
            accuracy: .high,
            isMultilingual: true
        ),
        ModelDescriptor(
            id: "small.en",
            engine: .whisperKit,
            displayName: "Whisper Small (English)",
            summary: "English only, and more accurate than Small for it.",
            downloadBytes: 483_000_000,
            recommendedMemoryGB: 8,
            speed: .medium,
            accuracy: .high,
            isMultilingual: false
        ),
        ModelDescriptor(
            id: "large-v3_turbo",
            engine: .whisperKit,
            displayName: "Whisper Large v3 Turbo",
            summary: "The most accurate option, and quick on Apple silicon.",
            downloadBytes: 632_000_000,
            recommendedMemoryGB: 16,
            speed: .medium,
            accuracy: .highest,
            isMultilingual: true
        ),
    ]

    public static var all: [ModelDescriptor] {
        [appleSpeech] + whisperModels
    }

    public static func model(withID id: String) -> ModelDescriptor? {
        all.first { $0.id == id }
    }

    /// What to use before the user has chosen anything.
    public static var `default`: ModelDescriptor { appleSpeech }
}
