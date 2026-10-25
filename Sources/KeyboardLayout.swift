import Carbon
import Foundation

/// Shortcuts follow the characters printed on the keys, so ⌃⌥Z means the Z key on AZERTY too.
/// Keys a layout cannot type without modifiers keep their US position.
enum KeyboardLayout {
    static func character(for keyCode: Int) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var dead: UInt32 = 0, length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                        0, &dead, chars.count, &length, &chars)
            // A dead key (` or ^ on French keyboards) prints its accent when followed by a space.
            if status == noErr, length == 0, dead != 0 {
                status = UCKeyTranslate(layout, UInt16(kVK_Space), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                        0, &dead, chars.count, &length, &chars)
            }
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }
    static func keyCode(for character: String) -> Int? {
        let wanted = character.lowercased()
        return (0..<128).first { KeyboardLayout.character(for: $0)?.lowercased() == wanted }
    }
    /// The key code to register for a shortcut written with `character`, falling back to the US position.
    static func resolve(_ character: String?, fallback: Int) -> Int {
        guard let character, !character.isEmpty else { return fallback }
        return keyCode(for: character) ?? fallback
    }
    /// What the key at `keyCode` prints, for labels ("^" for the US "[" position on French keyboards).
    static func label(for keyCode: Int, default value: String) -> String {
        guard let text = character(for: keyCode)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return value }
        return text.uppercased()
    }
}
