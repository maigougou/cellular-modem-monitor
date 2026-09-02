import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    static func systemDefault(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard let primaryLanguage = preferredLanguages.first?.lowercased() else { return .english }
        return primaryLanguage.hasPrefix("zh") ? .simplifiedChinese : .english
    }

    static func resolved(
        storedValue: String?,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        storedValue.flatMap(AppLanguage.init(rawValue:))
            ?? systemDefault(preferredLanguages: preferredLanguages)
    }
}

private struct AppLanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppLanguage.english
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageEnvironmentKey.self] }
        set { self[AppLanguageEnvironmentKey.self] = newValue }
    }
}

enum L10n {
    static func text(_ english: String, language: AppLanguage) -> String {
        guard language == .simplifiedChinese else { return english }
        return simplifiedChinese[english] ?? english
    }

    static func format(
        _ english: String,
        language: AppLanguage,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: text(english, language: language),
            locale: language.locale,
            arguments: arguments
        )
    }

    // English strings are the stable lookup keys. Unlisted technical strings
    // intentionally remain in English instead of showing a broken key.
    private static let simplifiedChinese: [String: String] = [
        // App chrome and connection status
        "Cellular Modem Monitor": "蜂窝调制解调器监控",
        "Modem status": "调制解调器状态",
        "Refresh now": "立即刷新",
        "Application menu": "应用菜单",
        "CURRENT CONNECTION": "当前连接",
        "now": "刚刚",
        "Waiting for current radio information": "正在等待当前无线网络信息",
        "Local modem": "本地调制解调器",
        "Expanded": "已展开",
        "Collapsed": "已折叠",
        "Expand section": "展开此部分",
        "Collapse section": "折叠此部分",
        "Cellular": "蜂窝网络",
        "Cellular —": "蜂窝网络 —",
        "Cellular …": "蜂窝网络 …",
        "Connecting": "正在连接",
        "Online": "在线",
        "Stale": "数据已过期",
        "Disconnected": "未连接",
        "SSH login failed": "SSH 登录失败",
        "Authentication failed": "身份验证失败",
        "QMI unavailable": "QMI 不可用",

        // Device details
        "Device details": "设备详情",
        "USB network": "USB 网络",
        "Interface": "网络接口",
        "Connection path": "连接路径",
        "Direct USB": "USB 直连",
        "Direct Ethernet": "以太网直连",
        "Routed": "经路由器",
        "Direct link (USB or Ethernet)": "直接链路（USB 或以太网）",
        "Device": "设备",
        "Management": "管理地址",
        "Source": "数据来源",
        "Modem firmware": "调制解调器固件",
        "VOS firmware": "VOS 固件",
        "Device firmware": "设备固件",
        "Web UBus (read-only)": "Web UBus（只读）",
        "Authenticated Web UBus": "已认证 Web UBus",
        "Not detected": "未检测到",

        // Interface-bound speed test
        "Speed test": "测速",
        "Bound interface": "绑定接口",
        "macOS networkQuality": "macOS networkQuality",
        "Ookla Speedtest CLI": "Ookla Speedtest CLI",
        "Download": "下载",
        "Upload": "上传",
        "Testing through %@ · %.0f s": "正通过 %@ 测速 · %.0f 秒",
        "Idle latency": "空闲延迟",
        "Jitter": "抖动",
        "Packet loss": "丢包率",
        "Server": "服务器",
        "View result": "查看结果",
        "Responsiveness": "响应能力",
        "Run macOS test": "运行 macOS 测速",
        "Run Ookla test": "运行 Ookla 测速",
        "Start speed test": "开始测速",
        "Test again": "再次测速",
        "Uses the separately installed official Ookla CLI.": "使用另行安装的官方 Ookla CLI。",
        "Ookla terms": "Ookla 条款",
        "Install official CLI": "安装官方 CLI",
        "Running both tests can use a substantial amount of cellular data.": "运行两种测速可能会消耗大量蜂窝数据流量。",
        "Speed tests can use a substantial amount of cellular data.": "测速可能会消耗较多蜂窝数据流量。",
        "No active modem is available for a speed test.": "没有可用于测速的活动调制解调器。",
        "The selected modem is not bound to a verified local network interface.": "所选调制解调器尚未绑定到已验证的本地网络接口。",
        "The selected modem reported an invalid local interface name.": "所选调制解调器报告了无效的本地接口名称。",
        "The bound interface %@ is no longer available.": "绑定的接口 %@ 已不再可用。",
        "The bound interface %@ is not active.": "绑定的接口 %@ 当前未活动。",
        "The bound interface changed identity (expected index %d, found %d).": "绑定接口的身份已改变（预期索引 %d，实际为 %d）。",
        "The bound source address %@ is no longer assigned to the modem interface.": "绑定的源地址 %@ 已不再属于该调制解调器接口。",
        "The bound gateway changed (expected %@, found %@).": "绑定的网关已改变（预期为 %@，实际为 %@）。",
        "No default Internet route is available for the Ookla test.": "Ookla 测速没有可用的默认互联网路由。",
        "Ookla would use the default route through %@, not the modem interface %@.": "Ookla 将通过默认路由 %@，而不是调制解调器接口 %@。",
        "The macOS networkQuality tool is unavailable.": "macOS networkQuality 工具不可用。",
        "The official Ookla Speedtest CLI is not installed.": "尚未安装官方 Ookla Speedtest CLI。",
        "The installed speedtest command is not the official Ookla CLI.": "已安装的 speedtest 命令不是官方 Ookla CLI。",
        "The speed test could not be started: %@": "无法启动测速：%@",
        "The speed test timed out.": "测速超时。",
        "The speed test failed (exit %d).": "测速失败（退出码 %d）。",
        "The speed test returned an unreadable result.": "测速返回了无法读取的结果。",
        "The speed test did not report which interface carried its traffic.": "测速未报告实际使用的网络接口。",
        "The speed test used %@, not the modem-bound interface %@.": "测速使用了 %@，而不是调制解调器绑定的接口 %@。",
        "The speed test reported source address %@, not the modem-bound address %@.": "测速报告的源地址为 %@，而不是调制解调器绑定的地址 %@。",
        "Each test is pinned to the shown Mac interface and its final result must identify that same interface. Live rates may include other traffic on it. Beyond the router, WAN, VPN and multi-WAN selection remain controlled by the router.": "每种测速都固定到所示 Mac 接口，最终结果也必须识别为同一接口；实时速度可能包含该接口上的其他流量。经过路由器后，WAN、VPN 和多 WAN 选择仍由路由器控制。",
        "Each test is pinned to the shown modem interface and its final result must identify that same interface. Live rates use interface counters and may include other traffic; final rates come from the named test tool.": "每种测速都固定到所示调制解调器接口，最终结果也必须识别为同一接口。实时速度来自接口计数器，可能包含其他流量；最终速度来自对应的测速工具。",
        "Traffic is pinned to the shown Mac interface and the final result must report that same interface. Live rates may include other traffic on it. Beyond the router, WAN, VPN and multi-WAN selection remain controlled by the router.": "流量已固定到所示 Mac 接口，最终结果也必须报告同一接口；实时速度可能包含该接口上的其他流量。经过路由器后，WAN、VPN 和多 WAN 选择仍由路由器控制。",
        "Traffic is pinned to the shown modem interface and the final result must report that same interface. Live rates use interface counters and may include other traffic; final rates come from macOS networkQuality.": "流量已固定到所示调制解调器接口，最终结果也必须报告同一接口。实时速度来自接口计数器，可能包含其他流量；最终速度来自 macOS networkQuality。",

        // Network and radio controls
        "Network & radio controls": "网络与无线控制",
        "Operator selection": "运营商选择",
        "Selected operator": "当前运营商",
        "Radio preference": "无线模式偏好",
        "Reading…": "正在读取…",
        "Not registered": "未注册",
        "Scan Networks": "扫描网络",
        "Automatic Selection": "自动选择",
        "Scanned networks": "扫描到的网络",
        "Reported access is the modem's scan result, not a complete list of every band offered by the operator.": "显示的接入制式来自调制解调器扫描结果，并非运营商所提供全部频段的完整列表。",
        "Radio access preference": "无线接入模式偏好",
        "These radio preferences last until the modem loses power. Automatic restores the captured SA/NSA masks; LTE only disables NR while preserving the current LTE band mask.": "这些无线模式偏好会持续到调制解调器断电。自动模式会恢复已记录的 SA/NSA 掩码；仅 LTE 模式会关闭 NR，同时保留当前 LTE 频段掩码。",
        "These radio preferences persist across restarts until they are changed or restored. Each change is read back and a failed change is rolled back.": "这些无线模式偏好会跨重启保留，直到再次更改或恢复。每次更改都会读回验证，失败时会自动回滚。",
        "Each radio preference change is read back and a failed change is rolled back. The modem did not report whether the setting persists across restarts.": "每次无线模式偏好更改都会读回验证，失败时会自动回滚。调制解调器未报告该设置是否会跨重启保留。",
        "Automatic defaults were not available to capture. Reconnect or power-cycle the modem, then close and reopen this panel before changing radio access mode.": "未能记录自动模式默认值。请重新连接调制解调器或让其断电重启，然后关闭并重新打开此面板，再切换无线接入模式。",
        "Restore automatic defaults": "恢复自动默认设置",
        "Band locking": "频段锁定",
        "Enter comma-separated band numbers. Locks last until the modem loses power; Restore automatic defaults restores the captured masks.": "请输入以逗号分隔的频段编号。锁定会持续到调制解调器断电；“恢复自动默认设置”会还原已记录的掩码。",
        "Enter comma-separated band numbers. Locks persist across restarts until changed or restored; Restore automatic defaults restores the modem's vendor defaults.": "请输入以逗号分隔的频段编号。锁定会跨重启保留，直到再次更改或恢复；“恢复自动默认设置”会还原调制解调器的厂商默认值。",
        "Enter comma-separated band numbers. Locks are read back after each change; the modem did not report whether they persist across restarts.": "请输入以逗号分隔的频段编号。每次更改后都会读回锁定值；调制解调器未报告锁定是否会跨重启保留。",
        "Lock NR": "锁定 NR",
        "Lock LTE": "锁定 LTE",
        "Neighbor measurements": "邻区测量",
        "Refresh": "刷新",
        "No LTE neighbors were reported.": "未报告 LTE 邻区。",

        // Operator and architecture values
        "Automatic": "自动",
        "Manual": "手动",
        "Deregistered": "已注销",
        "Format only": "仅设置格式",
        "Manual, then automatic": "先手动，后自动",
        "Unknown": "未知",
        "Available": "可用",
        "Current": "当前",
        "Forbidden": "禁止接入",
        "Auto SA/NSA": "自动 SA/NSA",
        "SA only": "仅 SA",
        "NSA only": "仅 NSA",
        "LTE only": "仅 LTE",
        "Unavailable": "不可用",
        "Active": "活动",
        "Configured": "已配置",
        "Deconfigured": "已取消配置",
        "Detailed": "详细",
        "Compact": "紧凑",
        "Icon only": "仅图标",

        // In-progress operations and result notices
        "Reading network settings…": "正在读取网络设置…",
        "Scanning networks…": "正在扫描网络…",
        "Selecting %@…": "正在选择 %@…",
        "Restoring automatic network selection…": "正在恢复自动网络选择…",
        "Applying %@…": "正在应用 %@…",
        "Applying NR band lock…": "正在应用 NR 频段锁定…",
        "Applying LTE band lock…": "正在应用 LTE 频段锁定…",
        "Restoring automatic defaults…": "正在恢复自动默认设置…",
        "Network scan completed.": "网络扫描完成。",
        "Manual selection verified for %@.": "已验证手动选择：%@。",
        "Automatic network selection was verified.": "已验证自动网络选择。",
        "%@ was applied and verified. %@": "已应用并验证 %@。%@",
        "NR bands %@ were applied and verified. %@": "已应用并验证 NR 频段 %@。%@",
        "LTE bands %@ were applied and verified. %@": "已应用并验证 LTE 频段 %@。%@",
        "Automatic selection and the MC7530CA band/cell defaults were restored and verified.": "已恢复并验证自动运营商选择以及 MC7530CA 的频段/小区锁定默认值。",
        "Automatic operator selection and the original LTE/NR masks were restored and verified.": "已恢复并验证自动运营商选择以及原始 LTE/NR 掩码。",
        "This setting lasts until the modem loses power.": "此设置会持续到调制解调器断电。",
        "This setting persists until it is changed or restored.": "此设置会一直保留，直到再次更改或恢复。",
        "The modem did not report this setting's persistence.": "调制解调器未报告此设置的持久性。",

        // Confirmations
        "Scan cellular networks?": "扫描蜂窝网络？",
        "Select this network manually?": "手动选择此网络？",
        "Use automatic network selection?": "使用自动网络选择？",
        "Apply %@?": "应用 %@？",
        "Lock NR bands?": "锁定 NR 频段？",
        "Lock LTE bands?": "锁定 LTE 频段？",
        "Restore automatic defaults?": "恢复自动默认设置？",
        "A full operator scan can take several minutes and may temporarily interrupt cellular data.": "完整的运营商扫描可能需要数分钟，并可能暂时中断蜂窝数据。",
        "On VOS 5G, the app first switches to verified LTE-only mode, performs the scan, and then restores the exact previous LTE/SA/NSA preference. Data will be interrupted during this process.": "在 VOS 5G 上，应用会先切换到经过验证的仅 LTE 模式，执行扫描，然后精确恢复之前的 LTE/SA/NSA 偏好。此过程中数据连接会中断。",
        "The modem will try %@ (%@) using this exact scan result. Registration and data may be interrupted.": "调制解调器将使用这条扫描结果的精确参数尝试连接 %@（%@）。注册和数据连接可能中断。",
        "The modem will return to automatic operator selection. The resulting selection mode will be read back and verified.": "调制解调器将恢复自动运营商选择，并读回验证最终选择模式。",
        "This changes the modem's radio access mode. Exact values are read back; a failed change triggers an automatic rollback. Selected operator settings are not changed. %@": "此操作会更改调制解调器的无线接入模式。应用会读回精确值进行验证；更改失败时会自动回滚。已选运营商设置不会改变。%@",
        "The NR band list is invalid.": "NR 频段列表无效。",
        "The LTE band list is invalid.": "LTE 频段列表无效。",
        "Allow only NR bands %@. The exact values will be read back and a failed change will be rolled back. %@": "仅允许 NR 频段 %@。应用会读回精确值，失败时自动回滚。%@",
        "Allow only LTE bands %@. The exact values will be read back and a failed change will be rolled back. %@": "仅允许 LTE 频段 %@。应用会读回精确值，失败时自动回滚。%@",
        "The setting lasts until the modem loses power.": "此设置会持续到调制解调器断电。",
        "The setting persists across restarts until it is changed or restored.": "此设置会跨重启保留，直到再次更改或恢复。",
        "The modem did not report whether the setting persists across restarts.": "调制解调器未报告此设置是否会跨重启保留。",
        "This clears configured LTE, SA and NSA band locks and LTE/NR cell locks, restores the modem's vendor band defaults, and returns operator selection to automatic. The result will be read back and verified.": "此操作会清除已配置的 LTE、SA 和 NSA 频段锁定以及 LTE/NR 小区锁定，恢复调制解调器的厂商频段默认值，并将运营商选择恢复为自动。最终结果会被读回验证。",
        "This restores the original LTE, SA and NSA masks captured in this app session and returns operator selection to automatic. Both results will be read back and verified.": "此操作会恢复本次应用会话记录的原始 LTE、SA 和 NSA 掩码，并将运营商选择恢复为自动。两项结果都会被读回验证。",
        "The original automatic radio preference was not captured.": "未能记录原始自动无线模式偏好。",
        "Radio access preference control is unavailable.": "无线接入模式控制不可用。",
        "The modem reported an empty LTE band mask; LTE-only mode was not applied.": "调制解调器报告的 LTE 频段掩码为空；未应用仅 LTE 模式。",
        "The current SA/NSA preference is unavailable; no NR band lock was applied.": "当前 SA/NSA 偏好不可用；未应用 NR 频段锁定。",
        "Cancel": "取消",
        "Scan": "扫描",
        "Select": "选择",
        "Use Automatic": "使用自动模式",
        "Apply": "应用",
        "Restore": "恢复",

        // Settings and footer
        "Connection": "连接",
        "Modem": "调制解调器",
        "Address": "地址",
        "SSH user": "SSH 用户名",
        "SSH password": "SSH 密码",
        "Web admin password": "Web 管理员密码",
        "Required for status": "读取状态所必需",
        "Passwords are stored unencrypted in a private local file readable only by your macOS account. They are never stored in diagnostics or management URLs.": "密码以未加密形式保存在仅当前 macOS 账户可读的本地私有文件中；不会写入诊断信息或管理 URL。",
        "Refresh interval": "刷新间隔",
        "Language": "语言",
        "Menu bar": "菜单栏",
        "1 second": "1 秒",
        "5 seconds": "5 秒",
        "10 seconds": "10 秒",
        "15 seconds": "15 秒",
        "30 seconds": "30 秒",
        "1 minute": "1 分钟",
        "Open at Login": "登录时打开",
        "Factory VOS SSH: root / oelinux123": "VOS 原厂 SSH：root / oelinux123",
        "Save": "保存",
        "Copy": "复制",
        "Hide Settings": "隐藏设置",
        "Settings…": "设置…",
        "Open Device Web UI": "打开设备 Web 界面",
        "About Cellular Modem Monitor": "关于“蜂窝调制解调器监控”",
        "Quit Cellular Modem Monitor": "退出“蜂窝调制解调器监控”",

        // Radio cards, aggregation and accessibility
        "Carrier details unavailable": "载波详情不可用",
        "Channel unavailable": "信道不可用",
        "Cell ID —": "小区 ID —",
        "Cell ID %@": "小区 ID %@",
        "Open this Cell ID in CellMapper's LTE calculator": "在 CellMapper 的 LTE 计算器中打开此小区 ID",
        "Copy this Cell ID and open the matching operator's NR map in CellMapper": "复制此小区 ID，并在 CellMapper 中打开对应运营商的 NR 地图",
        "No active SCell": "无活动 SCell",
        "%@ only": "仅 %@",
        "Signal %@ dBm": "信号 %@ dBm",
        "Signal unavailable": "信号不可用",

        // About panel
        "Author: Maigougou": "作者：Maigougou",
        "Author: Maigougou\n\n": "作者：Maigougou\n\n",
        "Made in Canada": "加拿大制造",
        "Made in Canada\n\n": "加拿大制造\n\n",
        "Version %@": "版本 %@",

        // Common connection and validation errors
        "Enter a private or local device address.": "请输入专用或本地设备地址。",
        "The cellular modem is not reachable over SSH.": "无法通过 SSH 连接蜂窝调制解调器。",
        "The modem SSH username or password was rejected.": "调制解调器拒绝了 SSH 用户名或密码。",
        "The ZTE administrator password was rejected.": "ZTE 管理员密码不正确。",
        "Enter the ZTE Web administrator password in Settings.": "请在设置中输入 ZTE Web 管理员密码。",
        "Enter the VOS SSH username and password in Settings.": "请在设置中输入 VOS SSH 用户名和密码。",
        "macOS OpenSSH is not available.": "macOS OpenSSH 不可用。",
        "The app's SSH password helper is missing. Reinstall the app.": "缺少应用的 SSH 密码辅助程序。请重新安装应用。",
        "The modem operation timed out.": "调制解调器操作超时。",
        "The selected network does not contain a valid five- or six-digit PLMN.": "所选网络不包含有效的五位或六位 PLMN。",
        "The modem SSH/QMI probe returned an unreadable response.": "调制解调器 SSH/QMI 探测返回了无法读取的响应。",
        "The VOS QMI probe returned invalid hexadecimal data.": "VOS QMI 探测返回了无效的十六进制数据。",
        "The VOS QMI response was truncated.": "VOS QMI 响应不完整。",
        "The VOS QMI response did not match the request.": "VOS QMI 响应与请求不匹配。",
        "The Qualcomm QMI request failed (%@).": "Qualcomm QMI 请求失败（%@）。",
        "The VOS QMI response contains an invalid TLV.": "VOS QMI 响应包含无效的 TLV。",
        "Qualcomm NAS did not report an active radio band.": "Qualcomm NAS 未报告活动无线频段。",
        "Qualcomm NAS did not report separate SA and NSA preferences.": "Qualcomm NAS 未分别报告 SA 和 NSA 偏好。",
        "Enter one or more valid NR bands, for example 77,78.": "请输入一个或多个有效 NR 频段，例如 77,78。",
        "Enter one or more valid LTE bands, for example 2,4,25,66.": "请输入一个或多个有效 LTE 频段，例如 2,4,25,66。",
        "The original band masks were not captured. Power-cycle VOS, then reopen Network & radio controls.": "未记录原始频段掩码。请让 VOS 断电重启，然后重新打开“网络与无线控制”。",
        "The original automatic radio masks were not captured. Power-cycle VOS, then open Network & radio controls before changing the mode.": "未记录原始自动无线频段掩码。请让 VOS 断电重启，然后打开“网络与无线控制”再切换模式。",
        "Qualcomm NAS did not report an extended LTE band mask to preserve.": "Qualcomm NAS 未报告可保留的扩展 LTE 频段掩码。",
        "No automatic radio baseline is available for this physical VOS. Power-cycle it, then reopen this panel to capture its defaults.": "此 VOS 实机没有可用的自动无线设置基准。请让设备断电重启，然后重新打开此面板以记录默认值。",
        "No physical VOS identity is bound to this control operation.": "此控制操作尚未绑定 VOS 实机身份。",
        "The attached VOS changed during the operation. No saved radio tuple was written to the new device.": "操作期间连接的 VOS 已发生变化。已保存的无线参数没有写入新设备。"
    ]
}

extension ConnectionState {
    func localizedLabel(language: AppLanguage) -> String {
        L10n.text(label, language: language)
    }
}

extension MenuBarStyle {
    func localizedLabel(language: AppLanguage) -> String {
        L10n.text(label, language: language)
    }
}

extension OperatorSelectionMode {
    func localizedLabel(language: AppLanguage) -> String {
        L10n.text(label, language: language)
    }
}

extension NetworkAvailability {
    func localizedLabel(language: AppLanguage) -> String {
        L10n.text(label, language: language)
    }
}

extension CellularAccessTechnology {
    func localizedLabel(language: AppLanguage) -> String {
        L10n.text(label, language: language)
    }
}

extension NRArchitectureMode {
    func localizedLabel(language: AppLanguage) -> String {
        L10n.text(label, language: language)
    }
}

extension NetworkControlOperation {
    func localizedLabel(language: AppLanguage) -> String {
        switch self {
        case .loading:
            return L10n.text("Reading network settings…", language: language)
        case .scanning:
            return L10n.text("Scanning networks…", language: language)
        case let .selecting(plmn):
            return L10n.format("Selecting %@…", language: language, plmn)
        case .automaticSelection:
            return L10n.text("Restoring automatic network selection…", language: language)
        case let .changingArchitecture(mode):
            return L10n.format("Applying %@…", language: language, mode.localizedLabel(language: language))
        case .lockingNRBands:
            return L10n.text("Applying NR band lock…", language: language)
        case .lockingLTEBands:
            return L10n.text("Applying LTE band lock…", language: language)
        case .restoring:
            return L10n.text("Restoring automatic defaults…", language: language)
        }
    }
}

extension LTECarrierRole {
    func localizedLabel(language: AppLanguage) -> String {
        // PCell/SCell are standardized radio terms and intentionally remain unchanged.
        label
    }
}

extension LTECarrierState {
    func localizedLabel(language: AppLanguage) -> String {
        L10n.text(label, language: language)
    }
}
