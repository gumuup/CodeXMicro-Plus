# vRemoter integration

Upstream: https://github.com/VincentKingHsu/vRemoter
Source revision: `15076345d955fcc81dae659150d1702b50b8010a` (downloaded 2026-09-15).
The complete clone is available locally in `.build/vendor/vRemoter`.

Adapted files in `Sources/CodeXMicroApp/Hardware`:

- `ChromecastRemoteHIDBridge.swift`, `X6HIDBridge.swift`: HID collection takeover, report decoding, X6 gesture transition and mouse/keyboard passthrough.
- `RemoteProfiles.swift`: device signatures, button tables and standard output events.
- `ATVVProtocol.swift`, `ADPCMDecoder.swift`, `BridgeError.swift`: upstream ATVV/ADPCM implementation, retaining original attribution.
- `RemoteVoiceBridge.swift`: a new transport based on upstream BLE discovery, handshake and stream flow; callbacks replace provider-specific behavior.

CodeXMicro's `RadialMenuAction`, `RadialMenuItemEditor`, local shortcut recorder and action executor provide custom mappings. Configuration uses `hardware.remotes.v1`, included in existing data backup and integrity checks. Remote settings default to disabled.

Upstream telemetry, commerce, update service, Doubao integration and audio recording persistence are not included. The upstream patched BlackHole driver is not redistributed. Remote audio can use an already installed `vRemoteDr 2ch` or `BlackHole 2ch` loopback device, selected as the input in the user's speech application. Mac microphone operation needs no loopback device.

MIT notices are copied into the built app. See `LICENSE` and `THIRD_PARTY_NOTICES.md`.
