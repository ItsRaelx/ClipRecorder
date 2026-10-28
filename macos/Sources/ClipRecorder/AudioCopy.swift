import CoreMedia

extension CMSampleBuffer {
    /// Copies the PCM data into memory we own. ScreenCaptureKit hands out audio
    /// from a small fixed pool – holding on to its buffers for the replay window
    /// exhausts the pool and audio delivery silently stops.
    func deepCopiedAudio() -> CMSampleBuffer? {
        guard let format = formatDescription else { return nil }
        let frames = CMSampleBufferGetNumSamples(self)
        guard frames > 0 else { return nil }

        var listSize = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            self, bufferListSizeNeededOut: &listSize, bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil)
        guard listSize > 0 else { return nil }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: listSize, alignment: 16)
        defer { memory.deallocate() }
        let list = memory.bindMemory(to: AudioBufferList.self, capacity: 1)
        var source: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            self, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: listSize,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &source) == noErr else { return nil }

        var copy: CMSampleBuffer?
        guard CMAudioSampleBufferCreateWithPacketDescriptions(
            allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: format, sampleCount: frames, presentationTimeStamp: presentationTimeStamp,
            packetDescriptions: nil, sampleBufferOut: &copy) == noErr, let copy else { return nil }
        // Allocates a new block buffer and copies the samples into it.
        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            copy, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0,
            bufferList: list) == noErr else { return nil }
        return copy
    }
}

extension CMSampleBuffer {
    /// RMS level of float PCM audio mapped to 0…1 (−50 dBFS … 0 dBFS).
    var audioLevel: Float {
        guard let block = dataBuffer else { return 0 }
        var length = 0
        var pointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
                                          dataPointerOut: &pointer) == noErr, let pointer, length >= 4 else { return 0 }
        let count = length / 4
        var sum: Float = 0
        pointer.withMemoryRebound(to: Float.self, capacity: count) { samples in
            for i in stride(from: 0, to: count, by: 2) { sum += samples[i] * samples[i] }
        }
        let rms = sqrt(sum / Float(max(count / 2, 1)))
        let db = 20 * log10(max(rms, 0.000_01))
        return min(max((db + 50) / 50, 0), 1)
    }
}
