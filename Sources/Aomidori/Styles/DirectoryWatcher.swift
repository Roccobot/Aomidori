import CoreServices
import Foundation

/// Watches a folder tree with FSEvents and reports changes on the main thread, coalesced.
/// File-level events catch in-place edits as well as the atomic saves most editors make.
///
/// `@unchecked Sendable`: the stream is created in `init`, released in `deinit`, and its callback
/// only reads the immutable `onChange` on the main queue.
final class DirectoryWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let onChange: @MainActor () -> Void

    init?(url: URL, latency: TimeInterval = 0.2, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            // The stream is scheduled on the main queue.
            MainActor.assumeIsolated { watcher.onChange() }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        ) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
