# Cellular Modem Monitor for macOS

English | [简体中文](README.zh-CN.md)

**Cellular Modem Monitor** is a native macOS menu-bar app for viewing live
cellular radio information. This release supports both **VOS 5G** and the
**ZTE G5 MAX / MC7530CA**.

Normal status collection is read-only on both devices. VOS 5G also provides an
optional, explicitly opened **Network & radio controls** panel. The ZTE backend
is strictly read-only in this release and never exposes those VOS controls.

<p align="center">
  <img src="assets/cellular-modem-monitor-sa-n78.png" width="340" alt="Cellular Modem Monitor showing a 5G SA n78 connection">
  <img src="assets/cellular-modem-monitor-nsa-n78-b2.png" width="340" alt="Cellular Modem Monitor showing a 5G NSA n78 and LTE B2 connection">
  <br>
  <sub>VOS 5G SA n78 and NSA n78+B2 examples; demo values use synthetic Cell IDs.</sub>
</p>

## Features

### Status features for both backends

- Automatic discovery on every active physical IPv4 interface, without
  assuming that a modem's management address is the default gateway
- Per-interface candidate identity keeps repeated private management addresses
  on different links separate during discovery
- Live primary 5G NR and LTE bands in the menu bar
- SA/NSA mode only when the selected backend reports it unambiguously
- RSRP, RSRQ, RSSI and SNR when each metric is available
- Human-readable downlink frequency and channel bandwidth; raw ARFCN remains
  in diagnostics
- Serving NR/LTE Cell ID and detailed LTE PCell/SCell aggregation when the
  device supplies enough information to map it safely
- Clickable Cell IDs: LTE opens CellMapper's prefilled ID calculator; NR copies
  the full NCI and opens the matching MCC-MNC NR map for **Cell Search**
- Operator, PLMN and selected network interface
- Detailed, compact and icon-only menu-bar styles
- English and Simplified Chinese UI with instant language switching
- Manual refresh, 1/5/10/15/30/60-second polling, launch at login, faster
  recovery polling and copyable diagnostics

### VOS-only control features

- Network scan, manual PLMN selection and automatic operator selection
- Auto SA/NSA, SA only, NSA only and LTE only preferences with exact read-back
- Temporary NR and LTE band locks with allowlist validation and rollback
- Read-only LTE neighbor measurements reported by Qualcomm NAS

These controls depend on the VOS SSH/QMI implementation. They are not shown as
capabilities of the ZTE G5 MAX / MC7530CA.

The current Settings panel contains the Automatic/VOS/ZTE selector, each
backend's address and credential fields, polling and display preferences, and
the runtime language selector. Passwords are saved to macOS Keychain.

## Menu-bar labels

The app displays only information confirmed by the active backend:

| Label | Meaning |
| --- | --- |
| `SA n78` | The modem explicitly reports 5G Standalone |
| `NSA n78+B2` | The modem explicitly reports 5G Non-Standalone with NR n78 and LTE B2 |
| `NR n78+B2` | The bands are known, but the mode is not unambiguous |
| `LTE B2` | LTE B2 is active |
| `n78+B2` | Compact menu-bar style |
| `Cellular …` / `Cellular —` | Connecting / unavailable |

When the mode is unknown, the app uses the neutral `NR` label instead of
inferring SA or NSA from the presence of NR and LTE bands.

## Supported devices

| Device | Default management address | Status transport | Device controls |
| --- | --- | --- | --- |
| VOS 5G | `192.168.225.1` | SSH to Qualcomm QRTR/QMI | VOS network/radio controls |
| ZTE G5 MAX / MC7530CA | `192.168.254.1` | Authenticated read-only Web UBus | Read-only |

The tested VOS reference unit reports firmware `326.73_0R19` and internal modem
firmware `RXMG1.20.00.326_0R05`. Its published factory SSH login is
`root` / `oelinux123`; change or override it in Settings if your unit differs.

For the ZTE, enter the existing Web administrator password—the same password
used by its normal management page—in Settings. The application does not ship
with, derive or display a device-specific administrator password.

Both physical-device paths were validated on 2026-08-31.

## Connection layouts and automatic discovery

The discovery layer supports these layouts:

```text
Mac ← USB ECM ← modem
Mac ← USB-to-RJ45 adapter / Ethernet ← modem
Mac ← Wi-Fi or Ethernet ← Slate / another router ← modem
```

For every active physical IPv4 interface, the app considers the registered
backend profiles, including `192.168.225.1` for VOS and `192.168.254.1` for the
ZTE. It excludes loopback, `utun`, `awdl`, `llw` and peer-to-peer interfaces.
Candidates are keyed by protocol, host, port and interface index, so identical
private IP addresses on two adapters remain separate devices.

Candidates are ranked deterministically using same-subnet and reported-router
matches together with last-successful and manually entered hints. ZTE HTTP
always pins the selected interface. On a direct same-subnet path it also pins
the discovered source address; on a routed path it lets Network.framework
choose the source address for that interface. VOS SSH uses the selected source
address; it does not have an additional interface-index binding.

In the routed Slate/router layout, the modem management address does **not**
need to be the Mac's default gateway. A working route to that address must
already exist through the selected interface. The app relies on that existing
macOS route and does not inspect the full route table or create or change
system routes.

## Install

The prebuilt release requires macOS 13 Ventura or later and an Apple Silicon
Mac.

1. Download `Cellular-Modem-Monitor-macOS.zip` from the
   [latest release](https://github.com/maigougou/cellular-modem-monitor/releases/latest).
2. Unzip it and move **Cellular Modem Monitor.app** to `/Applications`.
3. Connect a supported modem directly, through an Ethernet adapter, or through
   a router that already provides a route to the management address.
4. Start the app and allow **Local Network** access if macOS asks.
5. Open **Settings…**, choose **Automatic**, **VOS 5G**, or
   **ZTE G5 MAX / MC7530CA**, then enter the matching credential.

The application in the release ZIP is ad-hoc signed and is not notarized with
an Apple Developer ID. If macOS blocks the first launch, Control-click the app
and choose **Open** after reviewing the source.

If Local Network access was denied, enable it in **System Settings → Privacy &
Security → Local Network**, then reopen the app.

## First run and everyday use

1. Leave device selection on **Automatic** to try every registered backend, or
   select one backend to restrict discovery.
2. For VOS, enter the SSH username and password. For the ZTE, enter its Web
   administrator password.
3. Normally, leave each backend's management address at its default. Changing
   it adds that HTTP/HTTPS address as a manual discovery hint while the built-in
   default remains available.
4. Save Settings. The app discovers the device, verifies its identity and then
   begins status polling.
5. Use **Refresh** for an immediate read. The default interval is 30 seconds;
   Settings also offers 1, 5, 10, 15 and 60 seconds.

After polling detects that a modem was unplugged, reconnecting uses the faster
recovery cadence. Registration loss or a PLMN change during replacement of a
powered physical SIM is reflected on a later poll, and stale operator/radio
details are cleared when the backend reports that transition. The app does not
read a SIM identifier, so it cannot distinguish a same-PLMN swap that produces
no observable registration change.

## How the backends work

### ZTE G5 MAX / MC7530CA

Discovery performs a small anonymous UBus schema fingerprint so an unrelated
Web server at the same private address is not accepted as a modem. Status reads
then authenticate with the Web administrator password and reuse a scoped UBus
session for that endpoint and interface.

Normal polling calls the read-only `zte_nwinfo_api.nwinfo_get_netinfo` method.
The parser maps reported operator/PLMN, LTE and NR bands, channels, bandwidth,
PCI, Cell ID, signal metrics and LTE carrier aggregation without inventing
missing values. The ZTE backend advertises only identity, status and Web UI
capabilities; it has no write/control API in this release.

### VOS 5G

Each normal refresh opens one SSH session and performs read-only queries. If a
new serving PLMN has no name in that response, the first lookup for that PLMN
opens one additional read-only QMI session and caches the result:

```text
Cellular Modem Monitor
  → macOS /usr/bin/ssh
  → temporary Perl probe supplied through stdin
  → VOS qrtr-lookup
  → Qualcomm AF_QIPCRTR
  → NAS and DSD QMI services
```

NAS supplies active NR/LTE bands, channels, bandwidth, available RF metrics,
serving-network data, Cell ID, LTE neighbor measurements and detailed LTE
PCell/SCell information. NAS Get PLMN Name resolves an empty serving name. DSD
supplies the explicit SA/NSA service-option bit. QRTR node and port numbers are
discovered for every query rather than hard-coded. `AT+GMR` and the VOS version
file provide modem and device firmware versions.

The probe is executed from SSH stdin and is not installed on VOS. Ordinary
polling is read-only.

## Network and radio controls — VOS only

Expand **Network & radio controls** only when a VOS device is active and you
intend to change registration:

The current VOS-only panel contains operator actions, Auto SA/NSA, SA only, NSA
only and LTE only preferences, NR/LTE band-lock fields and LTE neighbor
measurements. It is not displayed when the active backend is ZTE.

- **Scan Networks** runs `AT+COPS=?`. A full scan may take up to two minutes and
  can temporarily interrupt data. Results distinguish current, available,
  forbidden and unknown PLMNs.
- **Select** runs `AT+COPS=1,2,"MCCMNC"` without forcing an access technology.
  **Automatic Selection** runs `AT+COPS=0`; both operations are verified with
  `AT+COPS?`. The app preserves and restores the current QMI mode and masks
  around these operations.
- **Auto SA/NSA**, **SA only**, **NSA only** and **LTE only** use Qualcomm NAS
  power-cycle-scoped preferences. The original mode and SA/NSA masks are held
  in memory, read back after writes and restored if verification fails. LTE
  only preserves the current extended LTE mask.
- **Lock NR** and **Lock LTE** intersect requested bands with the captured
  factory-enabled masks, write a temporary preference, read it back exactly and
  roll back on failure.
- **Restore automatic defaults** restores the captured SA/NSA tuple, extended
  LTE mask and automatic operator selection. The baseline is bound to a digest
  of the current VOS USB serial; the raw serial is not stored or returned, and
  the masks are not persisted across app launches.
- **Neighbor measurements** reads current Qualcomm LTE measurements; it is not
  an active RF scan. This firmware does not expose a standard NR-neighbor list.

These controls are unavailable for the ZTE backend. Replacing a VOS SIM does
not silently reset a manual selection or temporary radio preference; choose
**Automatic Selection** or **Restore automatic defaults** when needed.

## Connection and security notes

- Modem passwords are stored in the current macOS account's Keychain. They are
  not stored in UserDefaults, endpoint caches, management URLs or diagnostics.
- On upgrade, a legacy VOS password previously stored in UserDefaults is moved
  to Keychain and the old preference is deleted after a successful migration.
  If Keychain is temporarily unavailable, the old value is retained only so a
  later launch can retry the migration.
- ZTE discovery is anonymous, but status collection starts only after the user
  supplies a valid Web administrator password in Settings. The authenticated
  session remains in process memory and is scoped to its endpoint/interface.
- Different VOS units can share `192.168.225.1` while using different SSH host
  keys. For this local modem path, the VOS backend disables SSH host-key
  verification and does not modify `~/.ssh/known_hosts`; point it only at a
  trusted device and network.
- The VOS SSH password is passed through the bundled `SSH_ASKPASS` helper, not
  through command-line arguments. Both backends omit credentials and stable
  device identifiers from diagnostics.
- Clicking an LTE Cell ID sends it in a CellMapper browser URL, where it may
  remain in browser history. Clicking an NR Cell ID first copies the NCI; it is
  sent only if pasted into **Cell Search**.

## Backend architecture and adding another modem

Transport-specific code implements the common `ModemStatusBackend` protocol.
A `ModemDiscoveryProfile` declares a backend's default management endpoints,
and `ModemBackendRegistry` pairs the implementation, discovery profile,
capabilities and credential policy. `ModemCoordinator` selects only registered
backends and keeps discovery separate from status collection.

To add another modem, implement a backend, add its `ModemKind`, provide a
discovery profile and register the pair. Exposing it as a manual Settings choice
also requires a `ModemSelection` case plus the corresponding credential fields
and localized UI. The per-interface topology, candidate ranking, probe timeout
and registry-driven coordinator remain transport-neutral. New write operations
must be represented as explicit capabilities so they cannot appear on a
read-only backend accidentally.

## Build from source and tests

Install Apple Command Line Tools, then run:

```sh
make test    # tests only
make build   # tests, builds and packages the app
```

For a public build that should retain a stable application identity across
upgrades, provide an Apple Developer ID Application signing identity and require
the build to use it:

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  REQUIRE_STABLE_SIGNING=1 make build
```

Without `SIGNING_IDENTITY`, the build script intentionally creates an ad-hoc
signed local build and prints a warning. Because an ad-hoc binary's signing
identity can change when it is rebuilt, macOS may ask for Keychain access again
after an upgrade. The app reports Keychain read/write failures in Settings and
does not silently replace an existing credential when Keychain access fails.

The packaged application archive is written to:

```text
dist/Cellular-Modem-Monitor-macOS.zip
```

Offline tests cover the VOS QMI parsers and temporary-control safeguards; ZTE
UBus authentication/session behavior and radio payload parsing; credential
policies and non-secret preferences; backend registry/coordinator selection;
malformed responses; and
synthetic discovery layouts for USB ECM, RJ45/Ethernet, routed Slate paths,
same-IP multi-interface isolation, interface exclusion, priorities,
scheme/port separation, backend filtering, deadlines and deterministic
concurrent results. These tests do not require or modify a physical modem.

The read-only VOS SSH/QMI and ZTE Web UBus status paths were validated end to
end on physical hardware on 2026-08-31.

## Current limitations

- The prebuilt release is Apple Silicon (`arm64`) only.
- ZTE G5 MAX / MC7530CA support is status-only; VOS network/radio controls are
  not available for it.
- A routed modem requires an existing reachable route. The app does not
  configure the Mac, Slate or another router.
- Some fields are absent when the modem, firmware or network does not report
  them. Missing values are shown as `—` rather than inferred.
- Standard LTE CA data may identify SCell band/channel/bandwidth without every
  SCell's global Cell ID or all signal metrics.
- The UI currently shows one primary NR band and detailed LTE PCell/SCell data;
  neither backend currently enumerates every possible NR component carrier.
- VOS control changes are temporary and limited to the documented registration
  and power-cycle-scoped radio preferences.

## Acknowledgements

Device research and community findings:
[eko.one.pl VOS 5G discussion](https://eko.one.pl/forum/viewtopic.php?id=25031).

## License

[MIT](LICENSE)
