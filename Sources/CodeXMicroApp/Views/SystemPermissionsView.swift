import AppKit
import AVFoundation
import CoreBluetooth
import IOKit.hid
import SwiftUI

/// Status is read from macOS, never inferred from an earlier button click.
struct SystemPermissionsView: View {
    @ObservedObject var store: CodexStore
    @State private var accessibility = AXIsProcessTrusted()
    @State private var inputMonitoring = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    @State private var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var bluetooth = CBManager.authorization
    @State private var bluetoothRequest: BluetoothPermissionRequest?
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        permissionRow("辅助功能", detail: "执行自定义按键与应用操作", granted: accessibility, restricted: false) {
            store.requestAccessibility()
        }
        permissionRow("输入监控", detail: "监听已启用的遥控器及物理按键", granted: inputMonitoring == kIOHIDAccessTypeGranted, restricted: false) {
            if inputMonitoring == kIOHIDAccessTypeUnknown { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
            else { openPrivacy("Privacy_ListenEvent") }
        }
        permissionRow("麦克风", detail: "采集所选音频设备并显示电平", granted: microphone == .authorized, restricted: microphone == .restricted) {
            if microphone == .notDetermined {
                Task { _ = await AVCaptureDevice.requestAccess(for: .audio); refresh() }
            } else { openPrivacy("Privacy_Microphone") }
        }
        permissionRow("蓝牙", detail: "连接遥控器语音服务", granted: bluetooth == .allowedAlways, restricted: bluetooth == .restricted) {
            if bluetooth == .notDetermined { bluetoothRequest = BluetoothPermissionRequest() }
            else { openPrivacy("Privacy_Bluetooth") }
        }
        Text("权限状态与 macOS 同步。已授权的项目无需再次开启；仅在使用对应功能时需要相关权限。")
            .font(.caption).foregroundStyle(.secondary)
            .onAppear(perform: refresh)
            .onReceive(timer) { _ in refresh() }
    }
    private func permissionRow(_ title: String, detail: String, granted: Bool, restricted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.shield.fill" : "exclamationmark.shield")
                .foregroundStyle(granted ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted { Text("已授权").font(.caption).foregroundStyle(.green) }
            else if restricted { Text("受系统限制").font(.caption).foregroundStyle(.secondary) }
            else { Button("开启权限", action: action).accessibilityLabel("开启\(title)权限") }
        }
    }
    private func refresh() {
        accessibility = AXIsProcessTrusted()
        inputMonitoring = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        bluetooth = CBManager.authorization
    }
    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
}

@MainActor
private final class BluetoothPermissionRequest: NSObject, @preconcurrency CBCentralManagerDelegate {
    private var central: CBCentralManager!
    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {}
}
