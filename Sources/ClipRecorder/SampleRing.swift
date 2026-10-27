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
            }
        }

        var formatDescription: CMFormatDescription? {
            switch stored {
            case .memory(let sample): return sample.formatDescription
            case .disk(_, _, _, let meta): return meta.format
            }
        }
    }

    fileprivate enum Stored {
        case memory(CMSampleBuffer)
        case disk(Chunk, offset: UInt64, length: Int, meta: Meta)
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
    fileprivate final class Chunk {
        let url: URL
        let startPTS: CMTime
        private var writeHandle: FileHandle?
        private var readHandle: FileHandle?
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

        func read(offset: UInt64, length: Int) -> Data? {
            lock.lock(); defer { lock.unlock() }
            if readHandle == nil { readHandle = try? FileHandle(forReadingFrom: url) }
            guard let readHandle else { return nil }
            try? readHandle.seek(toOffset: offset)
            return try? readHandle.read(upToCount: length)
        }

        deinit {
            try? writeHandle?.close()
            try? readHandle?.close()
            try? FileManager.default.removeItem(at: url)
        }
    }

    private(set) var items: [Item] = []
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
    var isEmpty: Bool { items.isEmpty }

    var span: Double {
        guard let a = items.first, let b = items.last else { return 0 }
        return (b.pts - a.pts).seconds
    }

    func append(_ sample: CMSampleBuffer, isKeyframe: Bool = true) {
        let pts = sample.presentationTimeStamp
        guard let diskDirectory else {
            items.append(Item(pts: pts, isKeyframe: isKeyframe, stored: .memory(sample)))
            return
        }
        guard let format = sample.formatDescription,
              let block = sample.dataBuffer,
              let bytes = Self.bytes(of: block) else { return }
        if currentChunk == nil || (pts - currentChunk!.startPTS).seconds >= chunkSeconds {
            currentChunk = Chunk(directory: diskDirectory, startPTS: pts)
        }
        guard let chunk = currentChunk, let offset = chunk.write(bytes) else { return }
        let meta = Meta(format: format, duration: sample.duration,
                        sampleCount: CMSampleBufferGetNumSamples(sample),
                        isAudio: CMFormatDescriptionGetMediaType(format) == kCMMediaType_Audio)
        items.append(Item(pts: pts, isKeyframe: isKeyframe, stored: .disk(chunk, offset: offset, length: bytes.count, meta: meta)))
    }

    /// Drops samples older than `cutoff`. With `keyframeAligned` the buffer still
    /// starts on a keyframe (the newest keyframe not newer than the cutoff).
    func trim(olderThan cutoff: Double, keyframeAligned: Bool) {
        var dropUntil = 0
        if keyframeAligned {
            for (i, item) in items.enumerated() {
                if item.pts.seconds > cutoff { break }
                if item.isKeyframe { dropUntil = i }
            }
        } else {
            dropUntil = items.firstIndex(where: { $0.pts.seconds >= cutoff }) ?? items.count
        }
        if dropUntil > 0 { items.removeFirst(dropUntil) }
    }

    func removeAll() {
        items.removeAll()
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
