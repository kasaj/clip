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
    // Priority: premium (macOS 13+ Siri-HD) → enhanced → default for the UI language.
    // Falls back to Czech, then English.

    private func bestVoice() -> AVSpeechSynthesisVoice? {
        let langCode = Locale.current.language.languageCode?.identifier ?? "cs"
        let all = AVSpeechSynthesisVoice.speechVoices()

        // rawValue 3 = .premium (macOS 13+), 2 = .enhanced, 1 = .default
        for minQuality in [3, 2, 1] {
            if let v = all.first(where: {
                $0.language.hasPrefix(langCode) && $0.quality.rawValue >= minQuality
            }) { return v }
        }
        // Czech fallback (if UI language isn't Czech)
        for minQuality in [3, 2, 1] {
            if let v = all.first(where: {
                $0.language.hasPrefix("cs") && $0.quality.rawValue >= minQuality
            }) { return v }
        }
        // Last resort
        return AVSpeechSynthesisVoice(language: "en-US")
    }
}
