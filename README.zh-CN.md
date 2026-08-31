# Cellular Modem Monitor for macOS

[English](README.md) | 简体中文

**Cellular Modem Monitor** 是一款原生 macOS 菜单栏应用，用于查看实时蜂窝
无线状态。当前版本同时支持 **VOS 5G** 与 **ZTE G5 MAX / MC7530CA**。

两种设备的常规状态采集都只读。VOS 5G 还提供需要用户主动展开的
**网络与无线控制**面板。当前版本的 ZTE 后端严格只读，也不会显示这些 VOS
控制项。

<p align="center">
  <img src="assets/cellular-modem-monitor-sa-n78.png" width="340" alt="Cellular Modem Monitor 显示 5G SA n78 连接">
  <img src="assets/cellular-modem-monitor-nsa-n78-b2.png" width="340" alt="Cellular Modem Monitor 显示 5G NSA n78 与 LTE B2 连接">
  <br>
  <sub>VOS 5G SA n78 与 NSA n78+B2 示例；图中使用虚构 Cell ID。</sub>
</p>

## 功能

### 两种后端共有的状态功能

- 在每个活动的物理 IPv4 接口上自动发现设备，不假设 modem 管理地址就是默认网关
- 发现阶段按接口区分候选，使不同链路上的相同私网管理地址保持独立
- 在菜单栏实时显示主要 5G NR 与 LTE 频段
- 仅在当前后端明确报告时显示 SA/NSA 模式
- 显示设备实际提供的 RSRP、RSRQ、RSSI 与 SNR
- 显示更直观的下行频率和信道带宽，原始 ARFCN 保留在诊断信息中
- 在设备数据足以安全关联时显示 NR/LTE 服务 Cell ID 及详细 LTE PCell/SCell
- Cell ID 可点击：LTE 会打开已填好数值的 CellMapper ID 计算器；NR 会复制完整
  NCI，并打开对应 MCC-MNC 的 NR 地图，可用于 **Cell Search**
- 显示运营商、PLMN 和所选网络接口
- 支持详细、紧凑和仅图标三种菜单栏样式
- 提供英文和简体中文界面，可即时切换语言
- 支持手动刷新、1/5/10/15/30/60 秒轮询、登录时启动、快速恢复轮询和复制诊断

### 仅 VOS 可用的控制功能

- 扫描网络、手动选择 PLMN 和恢复自动选网
- Auto SA/NSA、SA only、NSA only、LTE only，并精确读回验证
- 临时锁定 NR/LTE 频段，按允许列表校验并支持失败回滚
- 读取 Qualcomm NAS 当前报告的 LTE 邻区测量

这些控制依赖 VOS 的 SSH/QMI 实现，不会作为 ZTE G5 MAX / MC7530CA 的能力显示。

当前设置面板包含自动/VOS/ZTE 选择器、各后端的地址与凭据输入、轮询与显示偏好，
以及运行时语言选择器。密码会保存到 macOS Keychain。

## 菜单栏显示规则

应用只显示当前后端明确确认的信息：

| 显示 | 含义 |
| --- | --- |
| `SA n78` | modem 明确报告 5G SA |
| `NSA n78+B2` | modem 明确报告 5G NSA，NR 为 n78、LTE 为 B2 |
| `NR n78+B2` | 频段已知，但组网模式无法唯一确定 |
| `LTE B2` | 当前使用 LTE B2 |
| `n78+B2` | 菜单栏紧凑样式 |
| `Cellular …` / `Cellular —` | 正在连接 / 设备不可用 |

如果无法确认组网模式，应用会使用中性的 `NR` 标识，而不会根据 NR 与 LTE
频段是否同时出现自行判断 SA 或 NSA。

## 支持的设备

| 设备 | 默认管理地址 | 状态传输 | 设备控制 |
| --- | --- | --- | --- |
| VOS 5G | `192.168.225.1` | 通过 SSH 访问 Qualcomm QRTR/QMI | VOS 网络/无线控制 |
| ZTE G5 MAX / MC7530CA | `192.168.254.1` | 认证后的只读 Web UBus | 只读 |

已测试的 VOS 参考设备报告固件 `326.73_0R19`，内部 modem 固件为
`RXMG1.20.00.326_0R05`。其公开的原厂 SSH 登录为 `root` / `oelinux123`；
如果你的设备不同，请在设置中修改。

ZTE 需要在设置中输入现有 Web 管理员密码，也就是正常管理页面使用的密码。
应用不会内置、推导或显示任何设备专属管理员密码。

两种实机链路均已于 2026-08-31 完成验证。

## 连接方式与自动发现

发现层支持以下连接方式：

```text
Mac ← USB ECM ← modem
Mac ← USB 转 RJ45 网卡 / 以太网 ← modem
Mac ← Wi-Fi 或以太网 ← Slate / 其他路由器 ← modem
```

应用会在每个活动的物理 IPv4 接口上检查已注册后端的 profile，包括 VOS 的
`192.168.225.1` 和 ZTE 的 `192.168.254.1`。发现过程排除 loopback、`utun`、
`awdl`、`llw` 和点对点接口。候选键包含协议、主机、端口和接口索引，因此两块
网卡上的同一个私网 IP 仍会被当作不同设备处理。

候选会综合同子网匹配、与接口所报告 router 相同、上次成功和手工输入提示，按固定
规则排序。ZTE HTTP 始终绑定选中的接口；在同子网直连路径中还会绑定已发现的源
地址，在路由路径中则由 Network.framework 为该接口选择源地址。VOS SSH 使用
选中的源地址，但不会再额外绑定接口索引。

在经过 Slate/路由器的路径中，modem 管理地址**不需要**是 Mac 的默认网关；
但选中接口必须已经存在一条能够到达该地址的有效路由。应用依赖 macOS 的这条
现有路由，不会检查完整路由表，也不会创建或修改系统路由。

## 安装

预编译版本需要 macOS 13 Ventura 或更新版本，以及 Apple Silicon Mac。

1. 从 [最新 Release](https://github.com/maigougou/cellular-modem-monitor/releases/latest)
   下载 `Cellular-Modem-Monitor-macOS.zip`。
2. 解压并将 **Cellular Modem Monitor.app** 移到 `/Applications`。
3. 直接连接受支持 modem、通过以太网适配器连接，或通过已经具有管理地址路由的
   路由器连接。
4. 启动应用；如果 macOS 询问本地网络访问权限，请选择**允许**。
5. 打开**设置…**，选择**自动**、**VOS 5G** 或
   **ZTE G5 MAX / MC7530CA**，然后输入对应凭据。

Release ZIP 内的应用使用 ad-hoc 签名，没有 Apple Developer ID 公证。若 macOS
首次阻止启动，请在核对源码后按住 Control 点击应用并选择**打开**。

如果曾拒绝本地网络权限，请前往**系统设置 → 隐私与安全性 → 本地网络**重新
开启权限，然后退出并重新打开应用。

## 首次设置与日常使用

1. 保持设备选择为**自动**，即可尝试所有已注册后端；也可以选择一种后端来限制
   发现范围。
2. VOS 需要输入 SSH 用户名和密码；ZTE 需要输入 Web 管理员密码。
3. 通常保留各后端的默认管理地址即可。修改地址会把该 HTTP/HTTPS 地址作为手工
   发现提示，同时仍保留内置默认地址。
4. 保存设置。应用会发现设备、验证设备身份，然后开始状态轮询。
5. 使用**刷新**立即读取。默认间隔为 30 秒，设置中还可选择 1、5、10、15 和
   60 秒。

轮询检测到 modem 被拔出后，再插入时会使用更快的恢复周期。带电更换物理 SIM
过程中出现的注册中断或 PLMN 变化会在后续轮询中反映出来；后端报告这种变化时，
应用会清除旧运营商和旧无线数据。应用不读取 SIM 标识，因此无法识别既未改变
PLMN、也未产生可观察注册变化的换卡。

## 后端工作方式

### ZTE G5 MAX / MC7530CA

发现阶段会执行小范围匿名 UBus schema 指纹检查，避免将同一私网地址上的无关
Web 服务误识别为 modem。读取状态时再使用 Web 管理员密码认证，并为对应的
endpoint 与接口复用限定范围的 UBus session。

常规轮询调用只读方法 `zte_nwinfo_api.nwinfo_get_netinfo`。解析器映射设备实际
报告的运营商/PLMN、LTE/NR 频段、信道、带宽、PCI、Cell ID、信号指标和 LTE
载波聚合，不会编造缺失值。ZTE 后端只声明身份、状态和 Web UI 能力；当前版本
不提供任何写入或控制 API。

### VOS 5G

常规每次刷新建立一个 SSH 会话，并仅执行只读查询。若新的服务 PLMN 没有返回
名称，第一次补查该 PLMN 时会额外建立一次只读 QMI 会话并缓存结果：

```text
Cellular Modem Monitor
  → macOS /usr/bin/ssh
  → 通过 stdin 临时执行 Perl 探针
  → VOS qrtr-lookup
  → Qualcomm AF_QIPCRTR
  → NAS 与 DSD QMI 服务
```

NAS 返回活动 NR/LTE 频段、信道、带宽、可用射频指标、注册网络、Cell ID、LTE
邻区测量及详细 LTE PCell/SCell。NAS Get PLMN Name 用于补查空缺的服务网络名称；
DSD 通过明确的 service-option 位返回 SA/NSA。QRTR 节点与端口会在每次查询时
动态发现，不使用写死的数值。`AT+GMR` 与 VOS 版本文件分别提供 modem 和设备
固件版本。

探针只从 SSH stdin 执行，不会安装到 VOS。普通轮询始终只读。

## 网络与无线控制——仅 VOS

只有在 VOS 设备处于活动状态并且确实需要改变注册时，才展开**网络与无线控制**：

当前仅 VOS 面板包含运营商操作、Auto SA/NSA、SA only、NSA only、LTE only、
NR/LTE 锁频输入和 LTE 邻区测量。活动后端为 ZTE 时不会显示此面板。

- **扫描网络**执行 `AT+COPS=?`。完整扫描可能持续两分钟，并可能暂时中断数据；
  结果区分当前、可用、禁止和未知 PLMN。
- **选择**执行 `AT+COPS=1,2,"MCCMNC"`，不会强制接入技术；**自动选择**执行
  `AT+COPS=0`。两种操作都会通过 `AT+COPS?` 验证，应用还会在这些操作前后保存
  并恢复当前 QMI mode 和掩码。
- **Auto SA/NSA**、**SA only**、**NSA only**、**LTE only** 使用持续到断电的
  Qualcomm NAS 偏好。原始 mode 与 SA/NSA 掩码仅保存在内存中；写入后会读回，
  验证失败则恢复。LTE only 会保留当前扩展 LTE 掩码。
- **锁定 NR**和**锁定 LTE**会把请求频段与捕获的原厂允许掩码取交集，写入临时
  偏好，精确读回，并在失败时回滚。
- **恢复自动默认值**会恢复捕获的 SA/NSA 值、扩展 LTE 掩码和自动选网。基线绑定
  到当前 VOS USB serial 的摘要；原始 serial 不会保存或返回，掩码也不会跨应用
  启动持久保存。
- **邻区测量**读取 Qualcomm 当前 LTE 测量，并不是主动射频扫描。此固件没有
  标准的 NR 邻区列表接口。

ZTE 后端不提供这些控制。更换 VOS SIM 不会擅自重置手动选网或临时无线偏好；
需要时请明确选择**自动选择**或**恢复自动默认值**。

## 连接与安全说明

- Modem 密码保存在当前 macOS 账户的 Keychain 中，不会保存到 UserDefaults、
  endpoint 缓存、管理 URL 或诊断信息中。
- 升级时，旧版本曾保存在 UserDefaults 中的 VOS 密码会迁移到 Keychain；迁移成功
  后才删除旧偏好值。如果 Keychain 暂时不可用，旧值只会为之后再次尝试迁移而保留。
- ZTE 发现阶段匿名，但只有用户在设置中提供有效 Web 管理员密码后才会读取状态。
  认证 session 仅保留在进程内存中，并限定到对应 endpoint/接口。
- 不同 VOS 可能共用 `192.168.225.1`，但使用不同 SSH host key。针对这条本地
  modem 链路，VOS 后端会关闭 SSH host-key 验证，也不会修改
  `~/.ssh/known_hosts`；请只连接可信设备和网络。
- VOS SSH 密码通过内置 `SSH_ASKPASS` 小助手传递，不会出现在命令行参数中。
  两种后端的诊断都不会包含凭据或稳定设备标识。
- 点击 LTE Cell ID 会把该 ID 放入 CellMapper 浏览器 URL，可能留在浏览器历史；
  点击 NR Cell ID 会先复制 NCI，只有粘贴到 **Cell Search** 后才会发送。

## 后端架构与添加其他 modem

各传输实现采用共同的 `ModemStatusBackend` 协议。`ModemDiscoveryProfile` 声明
后端的默认管理 endpoint，`ModemBackendRegistry` 将实现、发现 profile、能力和
凭据策略配对。`ModemCoordinator` 只选择已注册后端，并将发现与状态采集分离。

添加新 modem 时，需要实现后端、增加对应的 `ModemKind`、提供发现 profile 并注册
二者。若要让用户在设置中手工选择它，还需增加 `ModemSelection` case、对应凭据字段
和本地化界面。逐接口拓扑、候选排序、探针超时和 registry 驱动的 coordinator 仍与
具体传输无关。新的写入操作必须声明为明确能力，避免意外出现在只读后端上。

## 从源码构建与测试

安装 Apple Command Line Tools，然后执行：

```sh
make test    # 仅运行测试
make build   # 运行测试、构建并打包应用
```

若公开构建需要在升级前后保持稳定的应用身份，请提供 Apple Developer ID
Application 签名证书，并要求构建过程必须使用该证书：

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  REQUIRE_STABLE_SIGNING=1 make build
```

未设置 `SIGNING_IDENTITY` 时，构建脚本会有意生成仅供本地使用的 ad-hoc
签名版本并输出警告。ad-hoc 二进制在重新构建后签名身份可能变化，因此升级后
macOS 可能再次请求 Keychain 访问权限。若 Keychain 读取或写入失败，应用会在
设置中显示错误，并且不会静默替换已经存在的凭据。

生成的应用压缩包位于：

```text
dist/Cellular-Modem-Monitor-macOS.zip
```

离线测试覆盖 VOS QMI 解析与临时控制保护；ZTE UBus 认证/session 与无线 payload
解析；凭据策略与不含秘密的偏好数据；后端 registry/coordinator 选择；畸形响应；
以及 USB ECM、RJ45/以太网、经 Slate 路由、同 IP 多接口隔离、接口排除、优先级、
协议/端口分离、
后端过滤、deadline 和并发结果固定排序等合成发现路径。测试不需要也不会修改
任何实机 modem。

只读 VOS SSH/QMI 与 ZTE Web UBus 状态链路已于 2026-08-31 在实机上完成
端到端验证。

## 当前限制

- 预编译版本仅支持 Apple Silicon（`arm64`）。
- ZTE G5 MAX / MC7530CA 当前仅支持状态读取，不能使用 VOS 的网络/无线控制。
- 通过路由访问 modem 时必须已经存在可达路由；应用不会配置 Mac、Slate 或其他
  路由器。
- 当 modem、固件或网络没有报告某项信息时，对应字段会显示 `—`，不会自行推测。
- 标准 LTE CA 数据可能只提供 SCell 的频段/信道/带宽，而没有每个 SCell 的
  Global Cell ID 或全部信号指标。
- 当前界面显示一个主要 NR 频段和详细 LTE PCell/SCell；两种后端目前都不能枚举
  所有可能的 NR 组成载波。
- VOS 控制变更是临时的，并严格限于文档所述注册及持续到断电的无线偏好。

## 致谢

设备研究与社区资料：
[eko.one.pl VOS 5G 讨论帖](https://eko.one.pl/forum/viewtopic.php?id=25031)。

## 许可证

[MIT](LICENSE)
