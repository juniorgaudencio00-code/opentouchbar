import Carbon.HIToolbox
import Foundation

// Triggers de hotkey global — RegisterEventHotKey (Carbon).
// Parse do TOML: "cmd+shift+o", "ctrl+alt+1", "cmd+space"…

final class HotkeyEngine {
    private var hotkeyRefs: [EventHotKeyRef?] = []
    private var triggers: [TriggerConfig] = []
    private var handler: EventHandlerRef?
    private unowned var engine: ActionEngine?

    func install(triggers: [TriggerConfig], engine: ActionEngine) {
        uninstall()
        self.triggers = triggers
        self.engine = engine
        guard !triggers.isEmpty else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event = event, let userData = userData else { return noErr }
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hkID
                )
                let me = Unmanaged<HotkeyEngine>.fromOpaque(userData).takeUnretainedValue()
                me.fire(index: Int(hkID.id))
                return noErr
            },
            1, &eventType, selfPtr, &handler
        )
        guard status == noErr else {
            NSLog("OpentouchBar: InstallEventHandler falhou (\(status))")
            return
        }

        for (i, trigger) in triggers.enumerated() {
            guard let (mods, key) = Self.parse(trigger.hotkey) else {
                NSLog("OpentouchBar: hotkey inválida no TOML: \(trigger.hotkey)")
                continue
            }
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: OSType(0x4F544200), id: UInt32(i))  // "OTB"
            let reg = RegisterEventHotKey(key, mods, hkID, GetApplicationEventTarget(), 0, &ref)
            if reg == noErr {
                hotkeyRefs.append(ref)
            } else {
                NSLog("OpentouchBar: RegisterEventHotKey falhou para \(trigger.hotkey) (\(reg))")
            }
        }
    }

    func uninstall() {
        for ref in hotkeyRefs where ref != nil { UnregisterEventHotKey(ref!) }
        hotkeyRefs = []
        if let h = handler { RemoveEventHandler(h) }
        handler = nil
        triggers = []
    }

    private func fire(index: Int) {
        guard index < triggers.count, let engine = engine else { return }
        let trigger = triggers[index]
        Task { await engine.run(trigger.action, source: "trigger:\(trigger.hotkey)") }
    }

    // MARK: - parse

    static func parse(_ spec: String) -> (UInt32, UInt32)? {
        var mods: UInt32 = 0
        var keyName = ""
        for part in spec.lowercased().split(separator: "+").map(String.init) {
            switch part {
            case "cmd", "command": mods |= UInt32(cmdKey)
            case "shift": mods |= UInt32(shiftKey)
            case "alt", "opt", "option": mods |= UInt32(optionKey)
            case "ctrl", "control": mods |= UInt32(controlKey)
            default: keyName = part
            }
        }
        guard let key = keyCodes[keyName] else { return nil }
        return (mods, key)
    }

    private static let keyCodes: [String: UInt32] = {
        var map: [String: UInt32] = [:]
        let letters: [(String, Int)] = [
            ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D),
            ("e", kVK_ANSI_E), ("f", kVK_ANSI_F), ("g", kVK_ANSI_G), ("h", kVK_ANSI_H),
            ("i", kVK_ANSI_I), ("j", kVK_ANSI_J), ("k", kVK_ANSI_K), ("l", kVK_ANSI_L),
            ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O), ("p", kVK_ANSI_P),
            ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R), ("s", kVK_ANSI_S), ("t", kVK_ANSI_T),
            ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X),
            ("y", kVK_ANSI_Y), ("z", kVK_ANSI_Z),
        ]
        let digits: [(String, Int)] = [
            ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3),
            ("4", kVK_ANSI_4), ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7),
            ("8", kVK_ANSI_8), ("9", kVK_ANSI_9),
        ]
        let specials: [(String, Int)] = [
            ("space", kVK_Space), ("return", kVK_Return), ("enter", kVK_Return),
            ("delete", kVK_Delete), ("esc", kVK_Escape), ("escape", kVK_Escape),
            ("tab", kVK_Tab), ("left", kVK_LeftArrow), ("right", kVK_RightArrow),
            ("up", kVK_UpArrow), ("down", kVK_DownArrow),
            ("f1", kVK_F1), ("f2", kVK_F2), ("f3", kVK_F3), ("f4", kVK_F4),
            ("f5", kVK_F5), ("f6", kVK_F6), ("f7", kVK_F7), ("f8", kVK_F8),
            ("f9", kVK_F9), ("f10", kVK_F10), ("f11", kVK_F11), ("f12", kVK_F12),
        ]
        for (name, code) in letters + digits + specials { map[name] = UInt32(code) }
        return map
    }()
}
