import AVFoundation
import Foundation

@MainActor
final class SpeechPlayer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechPlayer()
    private let synthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        // Prefer current locale; fall back to Czech
        let langCode = Locale.current.language.languageCode?.identifier ?? "cs"
        utterance.voice = AVSpeechSynthesisVoice(language: langCode)
            ?? AVSpeechSynthesisVoice(language: "cs-CZ")
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.50
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in isSpeaking = false }
    }
}
