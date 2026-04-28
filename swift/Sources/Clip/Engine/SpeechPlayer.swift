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
    // Always tries Czech first (the app is Czech-first), regardless of the
    // macOS UI language. Within each language: premium (3) → enhanced (2) → default (1).
    // If no Czech voice is installed, falls back to the UI-language voice.

    private func bestVoice() -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices()
        let systemCode = Locale.current.language.languageCode?.identifier ?? "en"

        // Language priority: Czech first, then whatever macOS UI is set to
        for langCode in ["cs", systemCode, "en"] {
            for minQuality in [3, 2, 1] {          // premium → enhanced → default
                if let v = all.first(where: {
                    $0.language.hasPrefix(langCode) && $0.quality.rawValue >= minQuality
                }) { return v }
            }
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }
}
