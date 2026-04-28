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
        utterance.voice = bestVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
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

    // MARK: - Voice selection
    // Prefers enhanced (Siri-quality) voice for the current UI language,
    // falls back to any voice for that language, then English.

    private func bestVoice() -> AVSpeechSynthesisVoice? {
        let langCode = Locale.current.language.languageCode?.identifier ?? "cs"

        let all = AVSpeechSynthesisVoice.speechVoices()

        // 1. Enhanced quality for current language
        if let v = all.first(where: { $0.language.hasPrefix(langCode) && $0.quality == .enhanced }) {
            return v
        }
        // 2. Any quality for current language
        if let v = all.first(where: { $0.language.hasPrefix(langCode) }) {
            return v
        }
        // 3. Czech fallback
        if let v = all.first(where: { $0.language.hasPrefix("cs") }) { return v }
        // 4. English fallback
        return AVSpeechSynthesisVoice(language: "en-US")
    }
}
