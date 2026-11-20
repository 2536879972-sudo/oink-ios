import Foundation
import Speech
import AVFoundation

/// 语音识别（中文），说完自动结束
@MainActor
final class SpeechInput: ObservableObject {
    @Published var isRecording = false

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private var onResult: ((String) -> Void)?

    func start(onResult: @escaping (String) -> Void) {
        self.onResult = onResult

        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    self.onResult?("")
                    self.onResult = nil
                }
                return
            }
            SFSpeechRecognizer.requestAuthorization { _ in }
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                guard granted else { return }
                DispatchQueue.main.async {
                    do { try self.begin() }
                    catch { print("[speech] start error:", error) }
                }
            }
        }
    }

    private func begin() throws {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        guard let recognizer, recognizer.isAvailable else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request else { return }
        request.shouldReportPartialResults = true

        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buf, _ in
            request.append(buf)
        }
        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] res, err in
            guard let self else { return }
            if let res, res.isFinal {
                let text = res.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.onResult?(text)
                    self.onResult = nil
                    self.stop()
                }
            }
            if err != nil {
                DispatchQueue.main.async {
                    self.stop()
                }
            }
        }
        isRecording = true
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
