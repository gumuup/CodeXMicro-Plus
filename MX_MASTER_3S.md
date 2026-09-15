# MX Master 3S 硬件适配

## 代码与来源

下载位置：`.build/vendor/Mouser`，Git revision `e780641d3e709f914d6273985da9ac2ab85a7322`。
来源：https://github.com/TomBadash/Mouser ，MIT 许可证随应用分发。

- `MXMasterProtocol.swift`：移植 HID++ 帧、控制列表及电池状态解码。
- `MXMasterHIDBridge.swift`：原生 IOKit 通信、动态功能查询、可编程按键接管、释放、连接重试与电池轮询。
- `MXStandardMouseBridge.swift`：普通鼠标按键和滚轮事件；必须匹配到同一型号鼠标的 HID 物理事件，才执行自定义操作。
- 编辑与执行复用 `RemoteButtonEditor`、`RadialMenuItemEditor`、`RemoteMappingStore`，配置仍纳入硬件数据备份。

## 使用

1. 在硬件页选择 MX Master 3S，启用映射。未设置的按键保留原有行为。
2. 点击按键行自由设置快捷键、文本、应用、网址或快捷指令，以及松开动作。
3. 「监听设备」提供 60 秒学习窗口，按实体按键后定位编辑器；学习不会执行配置的动作。
4. 普通左右键学习时，请将指针移出本应用窗口；设置窗口保留正常点击，以免无法修改配置。
5. 关闭映射或退出应用时尝试恢复接管的 HID++ 按键。其他映射软件可能争用协议接口；不要让多个程序同时配置这些按键。

包含左右键、中键、前后侧键、拇指手势键、顶部模式键、主滚轮和拇指滚轮双方向。底部 Easy-Switch／电源开关由设备固件控制，不作为可映射事件。

蓝牙 PID 0xB034 / 0xB043；Logi Bolt 接收器 PID 0xC548 按槽位查询实际设备名称，只有明确识别为 MX Master 3S 才接管。
普通输入采用设备事件关联，无法确定来源时保留原始输入；部分接收器不会公开独立鼠标身份，此时普通按键／滚轮映射需要蓝牙连接，HID++ 可编程按键仍可使用。

## 电量

硬件列表和设备图下方显示真实百分比与充电状态。
MX 使用 HID++ Unified Battery (0x1004)，回退 Battery Status (0x1000)；约 30 秒刷新，并响应通知。
两款遥控器读取系统 HID BatteryPercent，语音蓝牙连接同时支持标准 Battery Service (0x180F / 0x2A19)。
设备不提供电池数据时显示「电量未知」；断开时不显示缓存百分比。

## 验证

- 本机 MX Master 3S 蓝牙连接及真实电量 50% 已验证。
- 协议帧、畸形数据、按键集合、可接管标记、电池边界、普通输入来源关联测试已加入。
- Logi Bolt 的设备槽位适配需要独立实机验证；本次当前鼠标走蓝牙。
