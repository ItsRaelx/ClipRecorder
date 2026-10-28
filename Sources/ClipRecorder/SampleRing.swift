import CoreMedia
import Foundation

/// Rolling buffer of one track's samples. Short buffers live in RAM; long ones
/// are spilled to ~10 s chunk files on disk so a 10-minute buffer doesn't eat GBs of memory.
final class SampleRing {
    /// A buffered sample that can be turned back into a `CMSampleBuffer` (possibly from disk).
    struct Item {
        let pts: CMTime
        let isKeyframe: Bool
        fileprivate let stored: Stored

        func load() -> CMSampleBuffer? {
            switch stored {
            case .memory(let sample): return sample
            case .disk(let chunk, let offset, let length, let meta): return meta.restore(chunk.read(offset: offset, length: length), pts: pts, isKeyframe: isKeyframe)
            case .released: return nil
            }
        }

        /// Same item without its payload (for trimmed slots that haven't been compacted yet).
        fileprivate var released: Item { Item(pts: pts, isKeyframe: isKeyframe, stored: .released) }

        var formatDescription: CMFormatDescription? {
            switch stored {
            case .memory(let sample): return sample.formatDescription
            case .disk(_, _, _, let meta): return meta.format
            case .released: return nil
            }
        }
    }

    fileprivate enum Stored {
        case memory(CMSampleBuffer)
        case disk(Chunk, offset: UInt64, length: Int, meta: Meta)
        case released
    }

    fileprivate struct Meta {
        let format: CMFormatDescription
        let duration: CMTime
        let sampleCount: Int
        let isAudio: Bool

        func restore(_ data: Data?, pts: CMTime, isKeyframe: Bool) -> CMSampleBuffer? {
            guard let data, !data.isEmpty else { return nil }
            var block: CMBlockBuffer?
            guard CMBlockBufferCreateWithMemoryBlock(
                allocator: nil, memoryBlock: nil, blockLength: data.count, blockAllocator: nil,
                customBlockSource: nil, offsetToData: 0, dataLength: data.count,
                flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr, let block else { return nil }
            data.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count) }

            var sample: CMSampleBuffer?
            if isAudio {
                CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                    allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: sampleCount,
                    presentationTimeStamp: pts, packetDescriptions: nil, sampleBufferOut: &sample)
            } else {
                var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: pts, decodeTimeStamp: pts)
                var size = data.count
                CMSampleBufferCreateReady(
                    allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
                    sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                    sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
                if let sample, !isKeyframe,
                   let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
                   CFArrayGetCount(attachments) > 0 {
                    let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
                    CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                                         Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
                }
            }
            return sample
        }
    }

    /// One file on disk. Deleted automatically once nothing references it anymore
    /// (neither the ring nor a clip that is still being written from it).
    /// Only the chunk being filled keeps a file open: a 10-minute buffer has ~180
    /// chunks and apps get just 256 file descriptors.
    fileprivate final class Chunk {
        let url: URL
        let startPTS: CMTime
        private var writeHandle: FileHandle?
        private let lock = NSLock()
        private(set) var size: UInt64 = 0

        init?(directory: URL, startPTS: CMTime) {
            url = directory.appendingPathComponent(UUID().uuidString)
            self.startPTS = startPTS
            guard FileManager.default.createFile(atPath: url.path, contents: nil),
                  let handle = try? FileHandle(forWritingTo: url) else { return nil }
            writeHandle = handle
        }

        func write(_ data: Data) -> UInt64? {
            lock.lock(); defer { lock.unlock() }
            guard let writeHandle else { return nil }
            let offset = size
            do { try writeHandle.write(contentsOf: data) } catch { return nil }
            size += UInt64(data.count)
            return offset
        }

        /// Called when the ring moves on to the next chunk.
        func closeForWriting() {
            lock.lock(); defer { lock.unlock() }
            try? writeHandle?.close()
            writeHandle = nil
        }

        func read(offset: UInt64, length: Int) -> Data? {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            try? handle.seek(toOffset: offset)
            return try? handle.read(upToCount: length)
        }

        deinit {
            try? writeHandle?.close()
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Live samples are `storage[head...]`; trimming just moves `head` (and compacts
    /// now and then) instead of shifting megabytes ~90 times a second.
    private var storage: [Item] = []
    private var head = 0
    var items: ArraySlice<Item> { storage[head...] }
    private let diskDirectory: URL?
    private var currentChunk: Chunk?
    private let chunkSeconds = 10.0

    /// - Parameter diskDirectory: `nil` keeps everything in memory.
    init(diskDirectory: URL?) {
        self.diskDirectory = diskDirectory
        if let diskDirectory {
            try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
        }
    }

    var first: Item? { items.first }
    var isEmpty: Bool { head >= storage.count }

    var span: Double {
        guard let a = items.first, let b = items.last else { return 0 }
        return (b.pts - a.pts).seconds
    }

    func append(_ sample: CMSampleBuffer, isKeyframe: Bool = true) {
        let pts = sample.presentationTimeStamp
        guard let diskDirectory else {
            storage.append(Item(pts: pts, isKeyframe: isKeyframe, stored: .memory(sample)))
            return
        }
        guard let format = sample.formatDescription,
              let block = sample.dataBuffer,
              let bytes = Self.bytes(of: block) else { return }
        if currentChunk == nil || (pts - currentChunk!.startPTS).seconds >= chunkSeconds {
            currentChunk?.closeForWriting()
            currentChunk = Chunk(directory: diskDirectory, startPTS: pts)
        }
        guard let chunk = currentChunk, let offset = chunk.write(bytes) else { return }
        let meta = Meta(format: format, duration: sample.duration,
                        sampleCount: CMSampleBufferGetNumSamples(sample),
                        isAudio: CMFormatDescriptionGetMediaType(format) == kCMMediaType_Audio)
        storage.append(Item(pts: pts, isKeyframe: isKeyframe, stored: .disk(chunk, offset: offset, length: bytes.count, meta: meta)))
    }

    /// Drops samples older than `cutoff`. With `keyframeAligned` the buffer still
    /// starts on a keyframe (the newest keyframe not newer than the cutoff).
    func trim(olderThan cutoff: Double, keyframeAligned: Bool) {
        var dropUntil = head
        if keyframeAligned {
            for i in head..<storage.count {
                if storage[i].pts.seconds > cutoff { break }
                if storage[i].isKeyframe { dropUntil = i }
            }
        } else {
            dropUntil = storage[head...].firstIndex(where: { $0.pts.seconds >= cutoff }) ?? storage.count
        }
        guard dropUntil > head else { return }
        // Release dropped items right away (memory samples / chunk files).
        for i in head..<dropUntil { storage[i] = storage[i].released }
        head = dropUntil
        if head > 2048 && head > storage.count / 2 {
            storage.removeFirst(head)
            head = 0
        }
    }

    func removeAll() {
        storage.removeAll()
        head = 0
        currentChunk?.closeForWriting()
        currentChunk = nil
    }

    private static func bytes(of block: CMBlockBuffer) -> Data? {
        let length = CMBlockBufferGetDataLength(block)
        var data = Data(count: length)
        let status = data.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
        }
        return status == noErr ? data : nil
    }
}
