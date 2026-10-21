import AVFoundation

/// Listens to the microphone non-stop and cuts the audio into utterances:
/// it starts collecting when someone begins speaking and hands over the samples
/// after a short pause. No buttons needed.
final class UtteranceRecorder {
    /// Called on a background queue with one utterance: 16 kHz mono Float samples.
    var onUtterance: (([Float]) -> Void)?
    /// Called with the input level in dB (about -80 … 0).
    var onLevel: ((Float) -> Void)?
    /// Called when speech starts (true) and when the utterance ends (false).
    var onSpeaking: ((Bool) -> Void)?

    /// While paused (the phone is speaking a translation out loud) audio is ignored.
    var isPaused: Bool {
        get { queue.sync { paused } }
        set { queue.async { self.paused = newValue; if newValue { self.reset() } } }
    }
    var pauseSeconds: Double = 0.6

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "tafsiri.recorder")
    private let sampleRate = 16_000.0
    private lazy var target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                            channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?

    // Segmenting state — only touched on `queue`.
    private var paused = false
    private var inSpeech = false
    private var segment: [Float] = []
    private var preroll: [Float] = []
    private var silent = 0
    private var voiced = 0
    private var noiseFloor: Float = -55

    private let prerollSeconds = 0.4
    private let minSpeechSeconds = 0.4
    private let maxSeconds = 28.0   // Whisper works on windows of up to 30 s

    var isRunning: Bool { engine.isRunning }

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: format, to: target)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let chunk = self.convert(buffer) else { return }
            self.queue.async { self.process(chunk) }
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        queue.async { self.reset() }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * sampleRate / buffer.format.sampleRate + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let ch = out.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
    }

    private func process(_ chunk: [Float]) {
        guard !chunk.isEmpty else { return }
        var sum: Float = 0
        for s in chunk { sum += s * s }
        let db = max(20 * log10(max((sum / Float(chunk.count)).squareRoot(), 1e-7)), -80)
        onLevel?(db)
        guard !paused else { return }

        if !inSpeech {
            // Learn the background noise level so it works in a quiet office or a busy street.
            noiseFloor = min(max(noiseFloor * 0.95 + db * 0.05, -70), -28)
            preroll.append(contentsOf: chunk)
            let keep = Int(prerollSeconds * sampleRate)
            if preroll.count > keep { preroll.removeFirst(preroll.count - keep) }
            if db > noiseFloor + 12 && db > -50 {
                inSpeech = true
                segment = preroll
                voiced = chunk.count
                silent = 0
                onSpeaking?(true)
            }
            return
        }

        segment.append(contentsOf: chunk)
        if db > noiseFloor + 8 { voiced += chunk.count; silent = 0 } else { silent += chunk.count }

        let ended = Double(silent) >= pauseSeconds * sampleRate
        let tooLong = Double(segment.count) >= maxSeconds * sampleRate
        if ended || tooLong {
            if Double(voiced) >= minSpeechSeconds * sampleRate { onUtterance?(segment) }
            reset()
        }
    }

    private func reset() {
        if inSpeech { onSpeaking?(false) }
        inSpeech = false
        segment.removeAll(keepingCapacity: true)
        preroll.removeAll(keepingCapacity: true)
        silent = 0
        voiced = 0
    }
}
