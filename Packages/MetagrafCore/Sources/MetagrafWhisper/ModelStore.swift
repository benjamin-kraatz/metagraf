import Foundation
import MetagrafCore
import OSLog
import WhisperKit

/// Tracks which downloadable models are on disk, and fetches the ones that
/// aren't.
@MainActor
@Observable
public final class ModelStore {
    public enum State: Equatable, Sendable {
        case notInstalled
        case downloading(fraction: Double)
        case installed
        case failed(String)

        public var isInstalled: Bool { self == .installed }

        public var isDownloading: Bool {
            if case .downloading = self { return true }
            return false
        }
    }

    private let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "Models")
    private let root: URL
    private var downloads: [String: Task<Void, Never>] = [:]

    public private(set) var states: [String: State] = [:]

    public init(root: URL = Metagraf.modelsDirectory) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        refresh()
    }

    public func state(of model: ModelDescriptor) -> State {
        // Models that ship with the system are always ready.
        guard model.requiresDownload else { return .installed }
        return states[model.id] ?? .notInstalled
    }

    /// Where WhisperKit should look for a model's weights, if present.
    public func folder(for model: ModelDescriptor) -> URL? {
        let url = location(of: model)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Re-reads the disk. Cheap, and called whenever the models UI appears so
    /// files removed by hand are noticed.
    public func refresh() {
        for model in ModelCatalog.all where model.requiresDownload {
            // Never override an in-flight download with a disk check.
            if states[model.id]?.isDownloading == true { continue }
            states[model.id] = folder(for: model) == nil ? .notInstalled : .installed
        }
    }

    public func download(_ model: ModelDescriptor) {
        guard model.requiresDownload, downloads[model.id] == nil else { return }
        states[model.id] = .downloading(fraction: 0)

        // WhisperKit's progress callback is not `Sendable` and fires on whatever
        // thread the download is running on, so it only forwards a plain number
        // through a stream that the main actor drains.
        let (progressUpdates, progressSink) = AsyncStream<Double>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let root = root

        downloads[model.id] = Task { [weak self] in
            let reporter = Task { @MainActor [weak self] in
                for await fraction in progressUpdates {
                    guard self?.states[model.id]?.isDownloading == true else { return }
                    self?.states[model.id] = .downloading(fraction: fraction)
                }
            }
            defer { reporter.cancel() }

            guard let self else { return }
            do {
                _ = try await WhisperKit.download(
                    variant: model.id,
                    downloadBase: root,
                    progressCallback: { @Sendable progress in
                        progressSink.yield(progress.fractionCompleted)
                    }
                )
                progressSink.finish()
                guard !Task.isCancelled else { return }
                self.states[model.id] = .installed
                self.logger.info("Installed \(model.id, privacy: .public)")
            } catch {
                progressSink.finish()
                guard !Task.isCancelled else { return }
                self.states[model.id] = .failed(error.localizedDescription)
                self.logger.error(
                    "Download of \(model.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
            }
            self.downloads[model.id] = nil
        }
    }

    public func cancelDownload(of model: ModelDescriptor) {
        downloads[model.id]?.cancel()
        downloads[model.id] = nil
        states[model.id] = .notInstalled
        // A cancelled download leaves a partial folder behind.
        try? FileManager.default.removeItem(at: location(of: model))
    }

    public func delete(_ model: ModelDescriptor) {
        guard model.requiresDownload else { return }
        cancelDownload(of: model)
        try? FileManager.default.removeItem(at: location(of: model))
        states[model.id] = .notInstalled
    }

    /// Total bytes the downloaded models occupy.
    public func diskUsage() -> Int64 {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
            )
        else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true, let size = values?.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    /// WhisperKit lays models out under the repository path it downloaded from.
    private func location(of model: ModelDescriptor) -> URL {
        root
            .appending(path: "models", directoryHint: .isDirectory)
            .appending(path: "argmaxinc", directoryHint: .isDirectory)
            .appending(path: "whisperkit-coreml", directoryHint: .isDirectory)
            .appending(path: "openai_whisper-\(model.id)", directoryHint: .isDirectory)
    }
}
