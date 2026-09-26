# DJI Mic native adapter references

Source repositories downloaded for inspection to `.build/vendor/`:

- https://github.com/Johnixr/dji-mic-dictation — commit `1ca33901983d6b9edbf48f8111fe875f827aeac9`, MIT.
- https://github.com/caezium/dji-mic-wispr-flow — commit `7ae1eb3ba23caee2986feb3dc3a8576da1ad6048`. No license file was present; no code from this repository is redistributed.
- https://github.com/ShadowBitBasher/DJI-Mic-Control — commit `9ba76880807a71d4eaba74c785dbee186a98f43b`, Unlicense. Protocol inspected only, no USB settings commands or Rust code integrated.

The MIT project's device-filtered Consumer HID mapping is adapted to native
Swift/IOKit using CodeXMicro++'s existing action and preset store. Device IDs
and the E9/EA usage facts are independently corroborated by the other references.
The gesture recognizer is implemented locally; Karabiner, Typeless, installers,
database polling and firmware modification are not included.

Neither E9/EA nor receiver connection proves separate TX identity, power-button
events, physical hold duration, or transmitter online status. Power gestures are
stored as pending presets only. USB Consumer collection seizure requires real
device verification and must not affect the audio interface.
