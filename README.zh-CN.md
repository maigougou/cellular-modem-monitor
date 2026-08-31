# Cellular Modem Monitor for macOS

[English](README.md) | 简体中文

**Cellular Modem Monitor** 是一款原生 macOS 菜单栏应用，用于查看
受支持 USB 蜂窝 modem 的实时无线状态。当前版本支持 **VOS 5G**，以后可以
继续加入其他 modem 后端。

应用通过 SSH 调用 VOS 内的 Qualcomm QRTR/QMI 服务读取 modem。常规状态轮询
只读；只有用户主动展开 **Network & radio controls**、确认操作后，应用才会修改
运营商注册、临时无线接入偏好或临时 LTE/NR 频段掩码。

<p align="center">
  <img src="assets/cellular-modem-monitor-sa-n78.png" width="340" alt="Cellular Modem Monitor 显示 5G SA n78 连接">
  <img src="assets/cellular-modem-monitor-nsa-n78-b2.png" width="340" alt="Cellular Modem Monitor 显示 5G NSA n78 与 LTE B2 连接">
  <br>
  <sub>5G SA n78 与 NSA n78+B2 示例；图中使用虚构 Cell ID。</sub>
</p>

## 功能

- 在菜单栏实时显示主要 5G NR 与 LTE 频段
- 通过 Qualcomm DSD 明确识别 SA/NSA，不根据频段组合猜测
- 显示 modem 实际返回的 RSRP、RSRQ、RSSI 与 SNR
- 显示更直观的下行频率和信道带宽，原始 ARFCN 保留在诊断信息中
- 显示 NR/LTE 服务小区的真实 Global Cell ID；详细显示 LTE
  PCell/SCell，并仅在 QMI 能精确关联时显示该载波的信号数据
- Cell ID 可点击：LTE 会打开已填好数值的 CellMapper ID 计算器；NR 会复制
  完整 NCI，并打开对应 MCC-MNC 的 NR 地图，可直接粘贴到 **Cell Search**
- 根据当前 PLMN 补查运营商名称，并显示 PLMN、USB 接口及固件版本
- 支持详细、紧凑和仅图标三种菜单栏样式
- 提供英文和简体中文界面；macOS 系统语言为中文时默认使用简体中文，
  其他系统语言默认使用英文，也可在设置中即时切换
- 支持手动刷新、1/5/10/15/30/60 秒刷新间隔及登录时启动
- USB modem 拔出再插入后会自动恢复连接；设备离线期间使用更快的重试周期
- 单卡槽带电换卡会在下一轮刷新时识别：清除旧运营商和旧无线数据，并使用更快
  的恢复周期等待新 SIM 注册
- 可复制诊断信息，便于排查问题
- 扫描网络并显示运营商名称、MCC-MNC、可用状态和扫描报告的 LTE/NR 接入能力
- 手动选择 PLMN（不强制制式）、恢复自动选网，并通过 `AT+COPS?` 读回验证
- Auto SA/NSA、SA only、NSA only、LTE only，精确读回 Qualcomm mode/掩码；
  失败自动回滚，并可一键恢复
- 临时锁定 NR/LTE 频段：按原始允许掩码校验、精确读回，并可恢复
- 读取 Qualcomm NAS 当前报告的 LTE 邻区测量

<p align="center">
  <img src="assets/cellular-modem-monitor-settings-zh.png" width="360" alt="Cellular Modem Monitor 简体中文设置界面与语言选择器">
  <br>
  <sub>设置中的运行时语言切换（图中选择简体中文）。</sub>
</p>

## 菜单栏显示规则

应用只显示经过 modem 确认的信息：

| 显示 | 含义 |
| --- | --- |
| `SA n78` | DSD 明确报告 5G SA |
| `NSA n78+B2` | DSD 明确报告 5G NSA，NR 为 n78、LTE 为 B2 |
| `NR n78+B2` | 频段已知，但 DSD 没有给出唯一可靠的组网模式 |
| `LTE B2` | 当前使用 LTE B2 |
| `n78+B2` | 菜单栏紧凑样式 |
| `Cellular …` / `Cellular —` | 正在连接 / 设备不可用 |

如果无法确认组网模式，应用会使用中性的 `NR` 标识，而不会根据 NR 与 LTE
频段的组合自行判断 SA 或 NSA。

## 支持的设备

当前版本仅支持 VOS 5G。

| 项目 | 已测试值 |
| --- | --- |
| 管理地址 | `192.168.225.1` |
| VOS 固件 | `326.73_0R19` |
| 内部 modem 固件 | `RXMG1.20.00.326_0R05` |
| 默认 SSH 登录 | `root` / `oelinux123` |

这套 SSH 登录信息是 VOS 设备公开、共用的原厂凭据。请勿将 VOS SSH 暴露到
不可信的局域网或互联网。

## 安装

预编译版本需要 macOS 13 Ventura 或更新版本，以及 Apple Silicon Mac。

1. 从 [最新 Release](https://github.com/maigougou/cellular-modem-monitor/releases/latest)
   下载 `Cellular-Modem-Monitor-macOS.zip`。
2. 解压并将 **Cellular Modem Monitor.app** 移到 `/Applications`。
3. 将 VOS 5G 直接连接到 Mac，然后启动应用。
4. 如果 macOS 询问本地网络访问权限，请选择**允许**。
5. 如有需要，从 **Settings…** 修改地址或 SSH 登录信息。

默认每 30 秒刷新一次，也可在设置中选择 1、5、10、15 或 60 秒。Release ZIP
内的应用使用 ad-hoc 签名，没有 Apple
Developer ID 公证。若 macOS 首次阻止启动，请在核对源码后按住 Control 点击
应用并选择**打开**。

如果曾拒绝本地网络权限，请前往**系统设置 → 隐私与安全性 → 本地网络**重新
开启权限，然后退出并重新打开应用。

## VOS 5G 后端如何工作

常规每次刷新建立一个 SSH 会话，并仅执行只读查询。若新的服务 PLMN 没有返回
名称，应用会额外建立一次只读 QMI 会话补查并缓存该名称：

```text
Cellular Modem Monitor
  → macOS /usr/bin/ssh
  → 通过 stdin 临时执行 Perl 探针
  → VOS qrtr-lookup
  → Qualcomm AF_QIPCRTR
  → NAS 与 DSD QMI 服务
```

NAS 返回活动 NR/LTE 频段、信道、带宽、可用的射频信号指标、注册网络、服务
Cell ID、LTE 邻区测量，以及详细的 LTE PCell/SCell 信息。若 serving-system
响应中的运营商名为空，后端会用 NAS Get PLMN Name 根据当前 PLMN 补查名称；
DSD 通过明确的 service-option 位返回 SA/NSA。
QRTR 节点和端口会在每次查询时动态发现，不使用写死的数值。`AT+GMR` 与 VOS
版本文件分别提供 modem 和设备固件版本。

探针只从 SSH stdin 执行，不会安装到 VOS。常规轮询不会修改频段、USB
composition、carrier policy、APN、注册模式或任何持久配置。

## 网络与无线控制

仅在需要改变注册状态时展开 **Network & radio controls**：

<p align="center">
  <img src="assets/cellular-modem-monitor-radio-controls.png" width="360" alt="Cellular Modem Monitor 网络与无线控制界面，NR 与 LTE 锁频输入已对齐">
  <br>
  <sub>运营商、无线接入模式与临时锁频控制；示例使用虚构 Cell ID。</sub>
</p>

- **Scan Networks** 执行 `AT+COPS=?`。完整扫描可能持续两分钟，并可能暂时中断
  数据连接。结果区分当前、可用、禁止和未知 PLMN。LTE/NR 标签仅表示本次扫描
  报告的接入技术，不是运营商全部频段清单。
- **Select** 执行 `AT+COPS=1,2,"MCCMNC"`，有意不传可选制式参数；
  **Automatic Selection** 执行 `AT+COPS=0`。操作后应用都会重新读取
  `AT+COPS?` 验证。由于 0R05 上的 COPS 操作也可能改变 Qualcomm mode，应用
  会在扫描/选网前保存当前 QMI mode 和掩码，并在操作后精确恢复。
- **Auto SA/NSA**、**SA only**、**NSA only**、**LTE only** 通过 Qualcomm NAS 设置系统选择
  偏好，生效范围固定为“到下次断电”。首次切换前，应用会在内存中保存原始 mode
  和两份 64 字节 SA/NSA 掩码。每次写入后精确读回这三项；验证失败时尝试恢复
  原始值。LTE only 会关闭 NR，并保留、验证当前扩展 LTE 频段掩码；切回 NR
  模式时会恢复已捕获的 SA/NSA 掩码，并重新应用仍处于活动状态的 NR 锁频。
- **Restore automatic defaults** 会恢复上述原始 SA/NSA 值、扩展 LTE 掩码，
  并恢复自动选网。
  基线会绑定到当前 VOS USB serial 的哈希；即使另一台设备使用同一 IP，热插拔
  后也会丢弃旧基线，原始 serial 不会返回或保存。原始掩码也不会跨应用启动永久
  保存。若在临时覆盖后退出了应用，让 VOS 断电再上电即可恢复 Qualcomm 的
  断电默认值。
- **Lock NR** 与 **Lock LTE** 接受逗号分隔的频段号。应用会与捕获的原始允许
  掩码取交集，写入持续到断电的 Qualcomm 偏好，精确读回并在失败时回滚。
- **Neighbor measurements** 刷新 QMI 当前报告的 LTE 邻区；这不是主动射频扫描。
  当前固件没有标准的 NR 邻区列表接口。

这些控制不会修改 `carrier_policy.xml`、OEM 文件、硬件频段过滤、USB
composition 或 APN。

物理换卡不会擅自重置手动选网、SA/NSA/LTE 偏好或锁频。如果这些临时 modem
设置排除了新 SIM 可用的网络，请明确点击 **Automatic Selection** 或
**Restore automatic defaults**。

## 连接与安全说明

- 不同 VOS 可能共用 `192.168.225.1`，但使用不同的 SSH host key。针对物理
  直连的本地 USB 网络，VOS 后端有意关闭 SSH host-key 验证，也不会修改
  `~/.ssh/known_hosts`，因此不会验证 SSH 服务器身份。请只让应用连接可信、
  本机直连的 VOS。
- 使用默认管理地址并检测到 `192.168.225.x` USB 接口时，SSH 会绑定该源地址。
- SSH 密码通过应用内置的 `SSH_ASKPASS` 小助手传给 OpenSSH，不会出现在
  命令行参数或诊断信息中。
- 地址、用户名和密码目前保存在当前 macOS 用户的应用偏好设置中，不存入
  Keychain。
- 点击 LTE Cell ID 会将该 ID 放入 CellMapper 浏览器 URL，并可能留在浏览器
  历史中；点击 NR Cell ID 只会先复制 NCI，只有将其粘贴到 **Cell Search** 后
  才会发送给 CellMapper。

## 从源码构建

安装 Apple Command Line Tools，然后执行：

```sh
make test    # 仅运行测试
make build   # 运行测试、构建并打包应用
```

生成的应用压缩包位于：

```text
dist/Cellular-Modem-Monitor-macOS.zip
```

源码构建会使用执行构建的 Mac 架构。离线测试覆盖 LTE/NR 频段、DSD SA/NSA、
信号指标、Cell ID、PLMN 名称补查、LTE/NR 掩码、LTE CA 与畸形 QMI
报文。只读 SSH/QMI 链路已于 2026-08-31 在 VOS 实机上完成端到端验证。

## 当前限制

- 当前版本仅支持 VOS 5G。
- 预编译版本仅支持 Apple Silicon（`arm64`）。
- 当 modem 或网络没有返回某项信息时，对应字段可能为空。
- 标准 LTE CA QMI 会给出 SCell 的载波标识、信道、频段和带宽，但不会给出每个
  SCell 的 Global Cell ID 或完整四项信号；缺失值显示 `—`，不会复制服务小区
  数据冒充。
- 当前界面显示一个主要 NR 频段以及详细的 LTE PCell/SCell；此后端采用的公开
  QMI 路径暂不能枚举多个 NR 组成载波。
- 本应用不会解锁频段，也不会编辑持久 modem policy 文件；选网和无线接入控制
  只影响注册状态及持续到断电的无线偏好。

## 致谢

设备研究与社区资料：
[eko.one.pl VOS 5G 讨论帖](https://eko.one.pl/forum/viewtopic.php?id=25031)。

## 许可证

[MIT](LICENSE)
