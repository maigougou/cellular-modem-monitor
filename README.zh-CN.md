# Cellular Modem Monitor for macOS

[English](README.md) | 简体中文

**Cellular Modem Monitor** 是一款原生 macOS 菜单栏应用，用于查看
受支持 USB 蜂窝 modem 的实时无线状态。当前版本支持 **VOS 5G**，以后可以
继续加入其他 modem 后端。

应用通过 SSH 和 Qualcomm QMI 直接读取 modem，不依赖 VOS Web UI，也不会
修改 modem 设置。

<p align="center">
  <img src="assets/cellular-modem-monitor-preview.png" width="360" alt="Cellular Modem Monitor 实时显示 NR、LTE 与载波聚合信息">
</p>

## 功能

- 在菜单栏实时显示主要 5G NR 与 LTE 频段
- 通过 Qualcomm DSD 明确识别 SA/NSA，不根据频段组合猜测
- 显示 modem 实际返回的 NR-ARFCN、EARFCN、带宽与 RSRP
- 显示活动 LTE 辅载波频段
- 显示运营商、PLMN、USB 接口及固件版本
- 支持详细、紧凑和仅图标三种菜单栏样式
- 支持手动刷新、1/5/10/15/30/60 秒刷新间隔及登录时启动
- 可复制诊断信息，便于排查问题

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

如果无法确认组网模式，详情面板会明确显示模式不可用，而不会根据 NR 与 LTE
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

VOS Web UI 使用另一套 `admin` / `admin` 登录信息，本应用不使用它。菜单中的
**Open Device Web UI** 只是打开浏览器的快捷入口。

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

每次刷新建立一个 SSH 会话，并仅执行只读查询：

```text
Cellular Modem Monitor
  → macOS /usr/bin/ssh
  → 通过 stdin 临时执行 Perl 探针
  → VOS qrtr-lookup
  → Qualcomm AF_QIPCRTR
  → NAS 与 DSD QMI 服务
```

NAS 返回主要活动 NR/LTE 频段、信道、带宽、RSRP、注册网络，以及活动 LTE
辅载波频段；DSD 通过明确的 service-option 位返回 SA/NSA。QRTR 节点和端口
会在每次查询时动态发现，不使用写死的数值。`AT+GMR` 与 VOS 版本文件分别
提供 modem 和设备固件版本。

探针只从 SSH stdin 执行，不会安装到 VOS。应用不会修改频段、USB
composition、carrier policy、APN、注册模式或任何持久配置；也不会占用
VOS 的单用户 Web 会话，不依赖 VOS 的自签名 HTTPS 证书。

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

源码构建会使用执行构建的 Mac 架构。离线测试覆盖 LTE 与 NR 频段、DSD 明确
SA/NSA、未知模式、带宽、RSRP、PLMN、活动与未激活 LTE CA 数据，以及畸形
QMI 报文。SSH/QMI 链路也已于 2026-08-30 在 VOS 实机上完成手动端到端验证。

## 当前限制

- 当前版本仅支持 VOS 5G。
- 预编译版本仅支持 Apple Silicon（`arm64`）。
- 当 modem 或网络没有返回某项信息时，对应字段可能为空。
- 当前界面显示一个主要 NR 频段、一个主要 LTE 频段及活动 LTE 辅载波频段；
  暂不显示多个 NR 载波。
- 本应用只查看状态，不负责频段解锁或修改 modem 配置。

## 致谢

设备研究与社区资料：
[eko.one.pl VOS 5G 讨论帖](https://eko.one.pl/forum/viewtopic.php?id=25031)。

## 许可证

[MIT](LICENSE)
