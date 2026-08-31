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
        "Cellular": "蜂窝网络",
        "Cellular —": "蜂窝网络 —",
        "Cellular …": "蜂窝网络 …",
        "Connecting": "正在连接",
        "Online": "在线",
        "Stale": "数据已过期",
        "Disconnected": "未连接",
        "SSH login failed": "SSH 登录失败",
        "QMI unavailable": "QMI 不可用",

        // Device details
        "Device details": "设备详情",
        "USB network": "USB 网络",
        "Device": "设备",
        "Management": "管理地址",
        "Source": "数据来源",
        "Modem firmware": "调制解调器固件",
        "VOS firmware": "VOS 固件",
        "Not detected": "未检测到",

        // Network and radio controls
        "Network & radio controls": "网络与无线控制",
        "Operator selection": "运营商选择",
        "Selected operator": "当前运营商",
        "5G preference": "5G 模式偏好",
        "Reading…": "正在读取…",
        "Not registered": "未注册",
        "Scan Networks": "扫描网络",
        "Automatic Selection": "自动选择",
        "Scanned networks": "扫描到的网络",
        "Reported access is the modem's scan result, not a complete list of every band offered by the operator.": "显示的接入制式来自调制解调器扫描结果，并非运营商所提供全部频段的完整列表。",
        "5G architecture preference": "5G 组网模式偏好",
        "These Qualcomm preferences last until VOS loses power. Auto restores the SA and NSA masks captured before the first switch in this app session.": "这些 Qualcomm 设置会持续到 VOS 断电。自动模式会恢复本次应用会话首次切换前记录的 SA 和 NSA 掩码。",
        "Automatic defaults were not available to capture. Power-cycle VOS, then close and reopen this panel before changing SA/NSA mode.": "未能记录自动模式默认值。请让 VOS 断电重启，然后关闭并重新打开此面板，再切换 SA/NSA 模式。",
        "Restore automatic defaults": "恢复自动默认设置",
        "Band locking": "频段锁定",
        "Enter comma-separated band numbers. Locks are temporary until VOS loses power; Restore automatic defaults restores the captured masks.": "请输入以逗号分隔的频段编号。锁定仅持续到 VOS 断电；“恢复自动默认设置”会还原已记录的掩码。",
        "Lock NR": "锁定 NR",
        "Lock LTE": "锁定 LTE",
        "Neighbor measurements": "邻区测量",
        "Refresh": "刷新",
        "No LTE neighbors were reported. Standard QMI on this firmware does not provide an NR-neighbor list.": "未报告 LTE 邻区。此固件的标准 QMI 不提供 NR 邻区列表。",

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
        "Manual selection verified for %@ (%@).": "已验证手动选择：%@（%@）。",
        "Automatic network selection was verified.": "已验证自动网络选择。",
        "%@ was applied and verified. The preference resets when VOS loses power.": "已应用并验证 %@。VOS 断电后此偏好会重置。",
        "NR bands %@ were applied and verified until VOS loses power.": "已应用并验证 NR 频段 %@，设置持续到 VOS 断电。",
        "LTE bands %@ were applied and verified until VOS loses power.": "已应用并验证 LTE 频段 %@，设置持续到 VOS 断电。",
        "Original LTE/NR masks and automatic operator selection were restored and verified.": "已恢复并验证原始 LTE/NR 掩码和自动运营商选择。",

        // Confirmations
        "Scan cellular networks?": "扫描蜂窝网络？",
        "Select this network manually?": "手动选择此网络？",
        "Use automatic network selection?": "使用自动网络选择？",
        "Apply %@?": "应用 %@？",
        "Lock NR bands?": "锁定 NR 频段？",
        "Lock LTE bands?": "锁定 LTE 频段？",
        "Restore automatic defaults?": "恢复自动默认设置？",
        "A full operator scan can take up to two minutes and may temporarily interrupt cellular data.": "完整的运营商扫描最长可能需要两分钟，并可能暂时中断蜂窝数据。",
        "VOS will try %@ (%@) without forcing LTE or NR. Registration and data may be interrupted.": "VOS 将尝试连接 %@（%@），但不强制使用 LTE 或 NR。注册和数据连接可能中断。",
        "VOS will return to automatic operator selection and the result will be verified with AT+COPS?.": "VOS 将恢复自动运营商选择，并使用 AT+COPS? 验证结果。",
        "This temporarily changes the Qualcomm SA/NSA mode and band masks. The exact values will be read back; a failed change triggers an automatic rollback. Selected operator settings are not changed.": "此操作会临时更改 Qualcomm SA/NSA 模式和频段掩码。应用会读回精确值进行验证；更改失败时会自动回滚。已选运营商设置不会改变。",
        "The NR band list is invalid.": "NR 频段列表无效。",
        "The LTE band list is invalid.": "LTE 频段列表无效。",
        "Allow only NR bands %@. The exact masks will be read back and a failed change will be rolled back.": "仅允许 NR 频段 %@。应用会读回精确掩码，失败时自动回滚。",
        "Allow only LTE bands %@. The exact mask will be read back and a failed change will be rolled back.": "仅允许 LTE 频段 %@。应用会读回精确掩码，失败时自动回滚。",
        "This restores the original LTE, SA and NSA masks captured in this app session and returns operator selection to automatic. Both results will be verified.": "此操作会恢复本次应用会话记录的原始 LTE、SA 和 NSA 掩码，并将运营商选择恢复为自动。两项结果都会经过验证。",
        "Cancel": "取消",
        "Scan": "扫描",
        "Select": "选择",
        "Use Automatic": "使用自动模式",
        "Apply": "应用",
        "Restore": "恢复",

        // Settings and footer
        "Connection": "连接",
        "Address": "地址",
        "SSH user": "SSH 用户名",
        "SSH password": "SSH 密码",
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
        "Qualcomm NAS did not report an extended LTE band mask to preserve.": "Qualcomm NAS 未报告可保留的扩展 LTE 频段掩码。",
        "No automatic SA/NSA baseline is available for this physical VOS. Power-cycle it, then reopen this panel to capture its defaults.": "此 VOS 实机没有可用的自动 SA/NSA 基准。请让设备断电重启，然后重新打开此面板以记录默认值。",
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
