# Mouser adaptation

Source: https://github.com/TomBadash/Mouser
Revision: e780641d3e709f914d6273985da9ac2ab85a7322
License: MIT; see LICENSE in this directory.

CodeXMicro++ adapts HID++ request framing, dynamic REPROG_CONTROLS_V4
control discovery, button diversion, device identification and battery decoding
from core/hid_gesture.py and core/logi_device_catalog.py to native Swift/IOKit.
Its macOS event handling is informed by core/mouse_hook_macos.py; actions use
CodeXMicro++'s existing mapping editor and executor. The MX Master 3S image is
copied from images/logitech-mice/mx_master_3s/mouse.png.
