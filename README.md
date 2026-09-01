# Cellular Modem Monitor for macOS

English | [简体中文](README.zh-CN.md)

**Cellular Modem Monitor** is a native macOS menu-bar app for viewing live
cellular radio information. This release supports both **VOS 5G** and the
**ZTE G5 MAX / MC7530CA**.

Normal status collection is read-only on both devices. An optional, explicitly
opened **Network & radio controls** panel provides verified controls through
either the VOS SSH/QMI backend or the ZTE authenticated Web UBus backend.

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
- An interface-bound speed test with live download/upload rates and final
  capacity, idle-latency and responsiveness results
- Manual refresh, 1/5/10/15/30/60-second polling, launch at login, faster
  recovery polling and copyable diagnostics

### Device-control features

- Network scan, manual PLMN selection and automatic operator selection
- Auto SA/NSA, SA only, NSA only and LTE only preferences with exact read-back
- NR and LTE band locks with allowlist validation and automatic rollback
- A backend-specific restore operation with final read-back verification
- Physical-device identity verification before every write
- Read-only LTE neighbor measurements when the active backend reports them

Controls are routed through the currently active backend rather than directly
to a particular transport. VOS preferences last until power loss. MC7530CA
preferences are persistent until changed or restored. The UI shows each section
only when the active backend declares that capability.

The current Settings panel contains the Automatic/VOS/ZTE selector, each
backend's address and credential fields, polling and display preferences, and
the runtime language selector. Passwords are saved unencrypted in an app-local
file whose directory/file permissions are `0700`/`0600`; the app never requests
Keychain access.

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
| VOS 5G | `192.168.225.1` | SSH to Qualcomm QRTR/QMI | Read-back-verified network/radio controls |
| ZTE G5 MAX / MC7530CA | `192.168.254.1` | Authenticated Web UBus | Read-back-verified network/radio controls |

The tested VOS reference unit reports firmware `326.73_0R19` and internal modem
firmware `RXMG1.20.00.326_0R05`. Its published factory SSH login is
`root` / `oelinux123`; change or override it in Settings if your unit differs.

For the ZTE, enter the existing Web administrator password—the same password
used by its normal management page—in Settings. The application does not ship
with, derive or display a device-specific administrator password.

Both read-only physical-device status paths were validated on 2026-08-31. On
2026-09-01, the MC7530CA SA-only (`Only_5G`) control request and its
`Z-Mode: 0`/empty-`Z-Tag` SID-authenticated form were exercised on the physical
unit and confirmed by authoritative mode readback. After registration, the unit
reported TELUS `302-220` in SA, first on `n71` and later after normal reselection
on `n77`. The complete control path is also covered by offline request,
read-back, rollback and restore tests.

## Connection layouts and automatic discovery

The discovery layer supports these layouts:

```text
Mac ← USB ECM ← modem
Mac ← USB-to-RJ45 adapter / Ethernet ← modem
Mac ← Wi-Fi or Ethernet ← router ← modem
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

In a routed layout, the modem management address does **not**
need to be the Mac's default gateway. A working route to that address must
already exist through the selected interface. The app relies on that existing
macOS route and does not inspect the full route table or create or change
system routes.

## Interface-bound speed test

The **Speed test** card runs the macOS 13+ built-in `networkQuality` tool with
`-I` set to the exact interface discovered for the active modem. The test never
falls back to the default route when that interface or its index cannot be
verified. Live download/upload values come from that interface's byte counters;
the final rates, idle latency and responsiveness come from `networkQuality`'s
structured result, which must report the same interface before the app accepts
it.

On a direct USB or Ethernet link, this binds the public test to the modem's Mac
interface. On a routed layout such as Mac → router → modem, it proves that
the test used the Mac-to-router interface; the router still controls its own
WAN, VPN and multi-WAN selection. A speed test transfers a substantial amount
of data and should be started only when that usage is acceptable.

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

Discovery first uses anonymous UBus reads to require the expected network-info
schema and an exact `MC7530CA` product prefix from
`zwrt_common_info.common_config.wa_inner_version`. Only after both checks match
does it authenticate with the configured Web administrator password and call
the verified `zwrt_zte_mdm.api/get_modem_msn` method. The app retains only a
SHA-256 digest of that value as the physical-device identity, reuses the scoped
authenticated session for that endpoint/interface, and requires the same
identity before exposing any write operation.

Normal polling calls the read-only `zte_nwinfo_api.nwinfo_get_netinfo` method.
The parser maps reported operator/PLMN, LTE and NR bands, channels, bandwidth,
PCI, Cell ID, signal metrics and LTE carrier aggregation without inventing
missing values.

When the control panel is opened, the same scoped authenticated session exposes
only the radio methods declared by the backend. Every MC7530CA radio RPC uses the
device-verified SID-authenticated request form, `Z-Mode: 0` with an empty
`Z-Tag`; on the tested firmware, the same valid SID with the browser-style
`Z-Mode: 1`/method-tag form returns JSON-RPC `-32002 Access denied`. An initial
access-denied response causes one reauthentication and one identical retry. The
action path accepts UBus status zero even when the firmware returns the
payload-free `result: [0]` used by the real setters; reads and polls still require
their expected payload. The backend checks UBus/JSON-RPC errors, waits for
asynchronous modem work, then verifies the result with a fresh
`nwinfo_get_netinfo` read. If a change or
verification fails, the session attempts a verified rollback when the device
identity still matches and the API provides the required setters; any rollback
failure is reported explicitly.

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

## Network and radio controls

Expand **Network & radio controls** only when you intend to change cellular
registration. A full operator scan, manual registration, radio-mode change or
band lock can temporarily interrupt data on either modem.

The panel has one backend-neutral contract: open a session bound to the active
physical modem, perform one command, read the authoritative state back, and
attempt a verified rollback of the pre-operation vendor state when it is safe
and supported. A rollback failure is reported instead of being hidden. Changing
the active modem, endpoint or credential invalidates that session.

### VOS 5G control path

- **Scan Networks** uses `AT+COPS=?`; manual and automatic selection use
  `AT+COPS=1,2,"MCCMNC"` and `AT+COPS=0`, with `AT+COPS?` verification.
- The current Qualcomm QMI mode and band tuple is preserved around operator
  actions. SA/NSA/LTE preferences and band locks are read back exactly and are
  scoped to the current power cycle.
- **Restore automatic defaults** writes the automatic tuple captured in this
  app session and returns operator selection to automatic.
- The session is bound to a SHA-256 digest of the VOS USB serial. The raw serial
  is not stored or returned.
- **Neighbor measurements** shows current Qualcomm LTE measurements; it is not
  an active RF scan. This firmware does not expose a standard NR-neighbor list.

### ZTE G5 MAX / MC7530CA control path

- All authenticated network-info controls—including setters, scan/status/result
  polling and authoritative readback—use `Z-Mode: 0` and an empty `Z-Tag`. This
  is the request form verified on the physical MC7530CA; the generic transport
  still retains both header modes for other ZTE call paths.
- A setter or action succeeds when UBus returns status zero, including the
  physical unit's payload-free JSON-RPC `result: [0]`. Status/readback calls are
  separate and reject a status-zero response that omits their required payload.
- Scan uses `nwinfo_manual_scan`, bounded status polling and
  `nwinfo_m_netselect_contents`. Manual registration replays the exact RAT token
  returned by that scan and polls `nwinfo_m_netselect_result`; automatic
  selection is verified from `net_select_mode`.
- If a control session opens while the modem is already in manual selection,
  `nwinfo_get_netinfo` does not expose the exact `m_rat` needed to replay that
  state. Run **Scan Networks** first; the backend captures the token only when
  one unique `current` scan row matches the active PLMN. Until then it fails
  closed before changing the manual operator, returning to automatic selection,
  changing radio mode, locking LTE/NR bands or restoring defaults. A saved RAT
  is also rejected before any write when it is incompatible with the target
  `net_select` mode.
- Auto SA/NSA, NSA only, SA only and LTE only write the exact retail tokens
  `WL_AND_NSA`, `LTE_AND_5G`, `Only_5G` and `Only_LTE` through
  `nwinfo_set_netselect`.
- LTE locking uses `nwinfo_set_lte_ext_band`. SA and NSA locking both use
  `nwinfo_set_nrbandlock`, with the documented type `0` and `1` respectively.
  The verified product allowlists are LTE
  `2,4,5,7,12,13,17,25,26,29,30,38,41,42,43,48,66,71` and NR
  `2,5,7,12,25,29,30,38,41,66,71,77`.
- These ZTE preferences persist across power loss until changed or restored.
  Before any persistent control write, the backend validates a complete recovery
  image: mode/operator replay data, GW/LTE/SA/NSA values, cell locks, and the
  exact verified default NRDC list. The retail schema exposes no NRDC setter, so
  a non-default NRDC list blocks the operation before its first write. Successful
  commands verify that every persistent field outside the requested change stayed
  unchanged; collateral firmware changes are treated as failures.
  **Restore automatic defaults** calls the dedicated
  `nwinfo_reset_band_cell_setting`, then verifies the exact LTE/SA/NSA vendor
  lists, the MC7530CA legacy GW mask, cleared LTE/NR cell locks and the exact
  verified default NRDC list before explicitly restoring and verifying
  `WL_AND_NSA` automatic mode. Before the first reset write, every recoverable
  pre-operation value is parsed and validated. After any ambiguous write,
  verification failure, cancellation or collateral change, an uncancelled
  recovery task runs the reset and then rebuilds and verifies the previous
  GW/LTE/SA/NSA/cell/operator state with the exact retail setters. Independent
  recovery steps continue after a lost response, and exact final readback decides
  success. It is not a factory reset and does not read or modify APN profiles.
- Before every write, the authenticated session reads the modem MSN and compares
  only its SHA-256 digest with the session identity. The raw MSN is neither
  exposed nor stored. Once a mismatch is observed, that session refuses all
  later writes, including rollback writes to the replacement modem.
- The firmware reports LTE/NR neighbor fields, but the tested unit has not
  provided a non-empty sample whose format can be validated. The app therefore
  does not claim ZTE neighbor-measurement visualization.

## Connection and security notes

- Modem passwords are stored unencrypted in
  `~/Library/Application Support/Cellular Modem Monitor/credentials.json`.
  Its containing directory is mode `0700` and the file is mode `0600`, so only
  the current macOS account can read it. Software running as that same account
  can still read it. Passwords are not included in UserDefaults, endpoint
  caches, management URLs or diagnostics.
- On upgrade, a legacy VOS password previously stored in UserDefaults is moved
  to this local file and the old preference is deleted only after a successful
  write. Credentials saved by v1.3.0–v1.3.3 in macOS Keychain are never read or
  deleted by this version; enter them once in Settings to use the local file.
- ZTE discovery first reads only the anonymous schema and exact product field.
  After those match MC7530CA, it authenticates and calls the verified
  `get_modem_msn` method, retaining only its SHA-256 digest to bind the physical
  device. Status collection starts only after the user supplies a valid Web
  administrator password in Settings. Each authenticated session and its
  credential failure gate remain in process memory and are isolated to one
  endpoint/interface. Control writes require the modem-MSN digest to match the
  authenticated discovery identity.
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
Backends that expose writes also implement `ModemControlBackend` and return a
device-bound `ModemControlSession`; vendor tokens, retry order, baseline state
and rollback logic never leak into `StatusModel` or SwiftUI.
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
signed local build and prints a warning. macOS may require the user to approve
an ad-hoc build again after an upgrade. The app does not access macOS Keychain.

The packaged application archive is written to:

```text
dist/Cellular-Modem-Monitor-macOS.zip
```

Offline tests cover the VOS QMI parsers and temporary-control safeguards; ZTE
UBus authentication/session/header behavior, radio read-payload parsing,
payload-free action-result handling, exact
control methods and parameters, asynchronous polling, read-back verification,
strict PLMN/RAT parsing, full-state rollback after collateral changes, lost
responses and cancellation, verified restore and physical-device mismatch rejection; credential
policies and non-secret preferences; backend registry/coordinator selection;
malformed responses; and
synthetic discovery layouts for USB ECM, RJ45/Ethernet, routed-router paths,
same-IP multi-interface isolation, interface exclusion, priorities,
scheme/port separation, backend filtering, deadlines and deterministic
concurrent results. These tests do not require or modify a physical modem.

The read-only VOS SSH/QMI and ZTE Web UBus status paths were validated end to
end on physical hardware on 2026-08-31. The MC7530CA SA-only write and
authoritative readback described above were validated on physical hardware on
2026-09-01; the other ZTE control families remain covered by offline tests.

## Current limitations

- The prebuilt release is Apple Silicon (`arm64`) only.
- ZTE neighbor fields are not visualized until a non-empty, device-verified
  sample establishes their exact format.
- A routed modem requires an existing reachable route. The app does not
  configure the Mac or router.
- Some fields are absent when the modem, firmware or network does not report
  them. Missing values are shown as `—` rather than inferred.
- Standard LTE CA data may identify SCell band/channel/bandwidth without every
  SCell's global Cell ID or all signal metrics.
- The UI currently shows one primary NR band and detailed LTE PCell/SCell data;
  neither backend currently enumerates every possible NR component carrier.
- VOS radio preferences are power-cycle scoped. MC7530CA radio preferences are
  persistent and remain in effect until changed or explicitly restored.

## Acknowledgements

Device research and community findings:
[eko.one.pl VOS 5G discussion](https://eko.one.pl/forum/viewtopic.php?id=25031).

## License

[MIT](LICENSE)
