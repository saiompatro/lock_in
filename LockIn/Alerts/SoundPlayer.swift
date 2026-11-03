import AppKit

/// Plays the alert sound (a system sound from /System/Library/Sounds), optionally looping
/// until `stop()`. The notification itself is always delivered silently so the sound never doubles.
@MainActor
final class SoundPlayer {
    private var current: NSSound?
    private(set) var isLooping = false

    /// Start the sound. If a looping sound is already playing, this is a no-op for looping requests.
    func play(name: String, volume: Double, loop: Bool) {
        if isLooping, loop, current?.isPlaying == true { return }
        stop()

        let sound = Self.makeSound(named: name)
        sound?.volume = Float(min(1, max(0, volume)))
        sound?.loops = loop
        if let sound, sound.play() {
            current = sound
            isLooping = loop
        } else if sound == nil {
            NSSound.beep()
        }
    }

    func stop() {
        current?.loops = false
        current?.stop()
        current = nil
        isLooping = false
    }

    private static func makeSound(named name: String) -> NSSound? {
        // `NSSound(named:)` returns a shared cached instance; copy so overlapping plays and
        // per-play volume/loop settings never interfere.
        let base = NSSound(named: NSSound.Name(name)) ?? NSSound(named: NSSound.Name("Glass"))
        return (base?.copy() as? NSSound) ?? base
    }
}
