/// Wait for both key release and routed audio, then emit once per physical session.
/// Firmware stream restarts must not trigger the input method again.
struct X6VoiceInputSession {
    private var pending = false
    private var hasAudio = false
    private var released = false
    mutating func begin() { pending = true; hasAudio = false; released = false }
    mutating func end() { pending = false }
    mutating func keyReleased() -> Bool { released = true; return consumeIfReady() }
    mutating func audioArrived(sampleCount: Int) -> Bool {
        if sampleCount > 0 { hasAudio = true }
        return consumeIfReady()
    }
    private mutating func consumeIfReady() -> Bool {
        guard pending, hasAudio, released else { return false }
        pending = false
        return true
    }
}
