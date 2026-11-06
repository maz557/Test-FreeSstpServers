# Test-FreeSstpServers v16.1 — Reimplementation Specification

> **Purpose.** This document is a complete, language-agnostic behavior contract for reimplementing `Test-FreeSstpServers_v16_1.ps1` in another programming language without changing its test logic, safety rules, status strings, CSV columns, or existing-profile removal behavior. Together with [PORTING-PROMPT.md](PORTING-PROMPT.md), it can be given to an AI coding assistant to generate a port in another language.

---

## Document control

| Item | Value |
|---|---|
| Document ID | `PRJ-SSTP-V161-EN` |
| Title | Reimplementation specification for `Test-FreeSstpServers v16.1` |
| Document version | `1.0` |
| Date | 2026-11-05 |
| Status | Baseline — ready for review and implementation |
| Language | English |
| Audience | Developers, software architects, test engineers, operations, product owner |
| Authorship | Designed and tested by maz557; code written by AI under the maintainer's direction |
| Reference behavior | `Test-FreeSstpServers_v16_1.ps1` in this repository |
| Reference size | 4,236 lines, 207,968 bytes |
| Reference environment | Windows 10/11, PowerShell 7.6.9, Administrator session |
| Target language | Not selected; this document is language-agnostic |

The repository copy of the script is behaviorally identical to the internal reference. One help-text example path was sanitized before publication; no executable logic changed.

### Normative language

- **MUST** — required for behavioral parity.
- **MUST NOT** — forbidden; a violation is a compatibility defect.
- **SHOULD** — recommended; deviations need a documented reason.
- **MAY** — optional implementation detail.

### Related documents

- [README](../README.md) — user-facing overview and quick start.
- [PORTING.md](PORTING.md) — language options, API mapping, migration phases.
- [PORTING-PROMPT.md](PORTING-PROMPT.md) — copy-paste AI prompt for generating a port in another language.
- [TESTING.md](TESTING.md) — test strategy and acceptance criteria.
- [SECURITY.md](../SECURITY.md) — operational and reporting guidance.

---

## Contents

1. [Scope and goals](#1-scope-and-goals)
2. [System overview and architecture](#2-system-overview-and-architecture)
3. [Domain model](#3-domain-model)
4. [Source acquisition and parsing](#4-source-acquisition-and-parsing)
5. [Command-line interface](#5-command-line-interface)
6. [New-server workflow](#6-new-server-workflow)
7. [Existing-profile workflow](#7-existing-profile-workflow)
8. [Status and decision matrices](#8-status-and-decision-matrices)
9. [Ranking, profile creation, and CSV schemas](#9-ranking-profile-creation-and-csv-schemas)
10. [Safety, errors, and non-functional requirements](#10-safety-errors-and-non-functional-requirements)
- [Appendix A. Definitive status catalog](#appendix-a-definitive-status-catalog)
- [Appendix B. Reference regular expressions](#appendix-b-reference-regular-expressions)
- [Appendix C. File and output map](#appendix-c-file-and-output-map)
- [Appendix D. Glossary](#appendix-d-glossary)

---

## 1. Scope and goals

### 1.1. Goal

Reimplement the exact observable behavior of `Test-FreeSstpServers_v16_1.ps1` so that:

- existing `.cmd` launchers and user command lines keep working;
- the same modes, defaults, validation errors, and status strings are produced;
- every CSV file has the same name pattern, columns, and column order;
- the same safety rules protect existing Windows VPN profiles;
- the same ranking and selection logic chooses the servers to install.

Behavioral parity is more important than internal structure. A port MAY use different modules, classes, or concurrency for non-VPN work, but the observable contract in this document MUST hold.

### 1.2. In scope

- Windows 10/11 execution.
- Free SSTP server discovery from the primary list, VPN Gate, clipboard, local HTML, CSV snapshots, and a plain host list.
- TCP probing, temporary SSTP profile creation, `rasdial`, public-IP route verification, tunnel latency, and tunnel download measurement.
- Scoring and ranking.
- Adding the best confirmed servers as per-user Windows VPN profiles.
- Inventory, verification, and controlled removal of existing per-user and AllUser SSTP profiles.
- Console reporting and CSV output.

### 1.3. Out of scope

- The v17/v17.1 requirement that a download sample must transfer the complete 10 MB. **v16.1 deliberately accepts partial downloads with real bytes.**
- Non-SSTP VPN protocols.
- A graphical user interface.
- A background service or multi-user server.
- Parallel VPN dialing (forbidden by the single-dial invariant).
- Guaranteeing the long-term quality or trustworthiness of free servers.

### 1.4. Success criteria

A port is accepted when:

1. All 41 parameters, aliases, defaults, and ranges match.
2. All validation rules `V1`–`V10` fire in the same order with the same messages.
3. All status, verdict, planned-action, and action-taken strings match exactly.
4. The four CSV schemas match exactly (43, 45, 8, and 7 columns).
5. `-VerifyExisting -ReportOnly` never deletes a profile.
6. Existing-profile deletion requires an exact uppercase `YES`.
7. Every `INCONCLUSIVE` verdict maps to `KEEP`.
8. A partial download with real bytes can still produce `WORKING_TUNNEL_AND_INTERNET`.
9. The same input snapshot and mocked measurements produce the same decisions.
10. The acceptance checklist in [TESTING.md](TESTING.md) is complete.

---

## 2. System overview and architecture

### 2.1. Context

The tool is a **local orchestrator**, not a network service. Every measurement runs from the same Windows machine where the user is sitting. It has three layers:

1. **List acquisition** — HTTP/HTML/clipboard/CSV to `Server` records.
2. **Measurement** — TCP, temporary profile, `rasdial`, public IP, latency, download.
3. **Decision and reporting** — ranking, status, CSV, profile installation, controlled removal.

```text
┌─────────────────────────────────────────────────────────────────────┐
│                        User / Administrator                        │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ CLI + interactive confirmations
┌───────────────────────────────▼─────────────────────────────────────┐
│                       Command-line layer                            │
│  parameters → combination validation → mode selection → safety     │
└───────────────┬─────────────────────────────────┬───────────────────┘
                │                                 │
┌───────────────▼─────────────────┐   ┌───────────▼───────────────────┐
│   New-server engine (v16)       │   │  Existing-profile phase       │
│  source → shortlist → test      │   │  inventory → test → verdict   │
│  → CSV → install best           │   │  → confirm → remove → CSV     │
└───────┬─────────────┬───────────┘   └───────────┬───────────────────┘
        │             │                           │
┌───────▼──────┐ ┌────▼──────────────┐   ┌────────▼───────────────────┐
│ Online lists │ │ Windows RAS/SSTP  │   │ User + AllUser phonebooks  │
│ HTTP/HTML    │ │ VpnClient/rasdial │   │ VpnClient/rasdial          │
│ Clipboard    │ │ curl.exe          │   │ curl.exe                   │
│ CSV/plain    │ │ IP/latency/speed  │   │ IP/latency/speed           │
└──────────────┘ └───────────────────┘   └────────────────────────────┘
```

### 2.2. Components and responsibilities

| Component | Responsibility | Input | Output |
|---|---|---|---|
| `ParameterBinder` | Bind CLI arguments, validate type and range | Arguments | `Options` |
| `ModeSelector` | Select mode by precedence | `Options` | `RunMode` |
| `SourceFetcher` | Download pages, fall back to Jina, read HTML/clipboard | URL/file | Raw text |
| `ServerListParser` | Detect source type and build `Server` records | Raw text | `Server[]` |
| `ListMerger` | Deduplicate by `host:port`, prefer lower PING | Several `Server[]` | `Server[]` |
| `Shortlister` | Port filter, PING/uptime sort, Priority, Max | `Server[]` | `Server[]` |
| `TcpProbe` | TCP connect with timeout | host/port | `TcpResult` |
| `TemporaryProfileManager` | Create, verify, remove temporary profile | target | profile |
| `RasDialRunner` | Run `rasdial` with timeout and parse errors | profile/credentials | `DialResult` |
| `RouteVerifier` | Compare public IP before/after | baseline | route result |
| `LatencyProbe` | ICMP then TCP, median | host/port | `LatencyResult` |
| `DownloadProbe` | Run curl and parse write-out | URL/bytes | `DownloadResult` |
| `Scorer` | Compute SpeedScore/LatencyScore/SelectionScore | records | records |
| `ResultWriter` | Sort and write CSV | records | CSV |
| `ProfileAdder` | Add top N with dedupe and credential storage | confirmed | profile names |
| `ExistingInventory` | Read both phonebooks | — | `ExistingProfile[]` |
| `ExistingTester` | Test one profile and produce a verdict | profile | `VerificationRecord` |
| `RemovalGuard` | Remove only the tested scope and confirmed state | record | action |
| `Reporter` | Console tables, summary, CSV | records | output |

### 2.3. Normal execution pipeline

```text
Start
  │
  ├─ Help? ──yes──► print help and exit (before Administrator check)
  │
  ├─ Validate parameter combinations ──error──► throw
  │
  ├─ Environment checks: Windows, PS7+, Administrator, VpnClient, curl, rasdial
  │
  ├─ ListExisting? ──yes──► inventory + CSV + exit
  │
  ├─ VerifyExisting/PruneFirst? ──yes──► existing-profile phase
  │                                         ├─ VerifyExisting → exit
  │                                         └─ PruneFirst → continue
  │
  ├─ Acquire list(s) → merge → de-duplicate
  │
  ├─ Port filter → PING/uptime sort → PriorityServer
  │
  ├─ Save snapshot
  │
  ├─ ListOnly? ──yes──► exit
  │
  ├─ Read public IP before truncation (leftover-VPN warning)
  │
  ├─ Apply MaxServers
  │
  ├─ Interactive confirmation: disconnect VPNs + read baseline
  │
  ├─ Per-server loop: TCP → profile → dial → route → latency → download → cleanup
  │
  ├─ Compute scores → write results CSV
  │
  ├─ Print summary tables
  │
  ├─ Add top N to Windows VPN
  │
  └─ End
```

### 2.4. Mode precedence

The exact order in the reference script is:

1. `-Help` → print help and `return`; before environment checks and before combination validation.
2. Forbidden parameter combinations → `throw`.
3. Environment prerequisites: Windows, PowerShell 7+, Administrator, `VpnClient`, `curl.exe`, `rasdial.exe`.
4. `-ListExisting` → `Show-ExistingVpnProfiles` and `return`.
5. `-VerifyExisting` or `-PruneFirst` → `Invoke-ExistingProfileVerification`.
   - `-VerifyExisting` returns after the phase.
   - `-PruneFirst` prints a continuation message and enters the normal flow.
6. Normal new-server flow.

> **Critical:** environment checks run **before** mode dispatch. Therefore `-ListExisting` and `-VerifyExisting` also require PowerShell 7, Administrator, `VpnClient`, `curl.exe`, and `rasdial.exe`. Only `-Help` is exempt.

`-ListExisting` is checked before `-VerifyExisting`, but combining them is forbidden by validation, so the precedence only matters for valid modes.

### 2.5. Environment prerequisite order

After parameter validation, before mode dispatch and before any network or VPN operation:

1. `$env:OS -ne 'Windows_NT'` → error: this script must run on Windows 10/11.
2. `$PSVersionTable.PSVersion.Major -lt 7` → PowerShell 7 is required.
3. `Test-IsAdministrator` → error: open PowerShell as Administrator.
4. `Import-Module VpnClient` → terminating error if missing.
5. `Get-Command curl.exe` → terminating error if missing.
6. `%WINDIR%\System32\rasdial.exe` exists → error if missing.

A port MUST perform these checks before changing the system. `-Help` MUST work without Administrator rights.

### 2.6. Single-dial invariant

At most one VPN connection may be active at any time. Reasons:

- `Get-PublicIp` must see the exit IP of the tunnel under test; two tunnels make the result indeterminate.
- `rasdial` and RAS state are shared; parallel dials can create false 633/638 errors.
- A temporary profile must be fully disconnected before removal.
- Baseline-to-tunnel IP comparison is meaningful only with one tunnel.

**Implementation requirement:** no thread or process may dial or test servers in parallel. Fetching and parsing sources MAY be parallelized, but the VPN test queue MUST be single-threaded.

### 2.7. Design principles for a port

| Principle | Meaning |
|---|---|
| **Behavioral parity** | Every status, message, and column must have an equivalent; cosmetic improvements belong to a later version. |
| **Fail closed for deletion** | Any ambiguity → `KEEP` and `INCONCLUSIVE`. |
| **Explicit consent** | Deletion requires exact `YES`; Enter means keep. |
| **Scope fidelity** | Remove only from the phonebook scope that was tested; never fall back to the other scope. |
| **Idempotent-ish** | Re-running must not create duplicate profiles; dedupe by name and `host:port`. |
| **Observability** | Every decision must have a reason in the CSV or console. |
| **No silent success** | Install a profile only after verifying name, address, port, tunnel type, and `RememberCredential`. |
| **Partial measurement accepted** | A partial download with real bytes is valid, but `DownloadComplete=false` is recorded. |

### 2.8. High-level data flow

```text
URL/Clipboard/HTML/CSV
        │
        ▼
   RawContent
        │
        ▼
 ServerListParser ──► Server {Country, Source, Server, Host, Port, PingMs, UptimeText, UptimeMinutes}
        │
        ▼
 ListMerger (key = lowercase canonical Server)
        │
        ▼
 PortFilter → PingSort → PriorityServer → Snapshot
        │
        ▼
 MaxServers
        │
        ▼
 TestRecord (TCP → Dial → Route → Latency → Download)
        │
        ├──► Results CSV (sorted DownloadMbps desc)
        └──► Console ranking (SelectionScore) → Top N → Windows profiles
```

### 2.9. Temporary profile lifecycle (new-server flow)

```text
Add-VpnConnection (SSTP, MSChapv2, Encryption Optional)
        │
        ▼
Get-VpnConnection → verify stored ServerAddress
        │
        ├─ unparseable or host/port mismatch → PROFILE_PORT_MISMATCH
        │
        ▼
rasdial profile username password (with timeout)
        │
        ├─ error → corresponding status
        │
        ▼
Connected → route verification → latency → download
        │
        ▼
finally: rasdial /disconnect → wait for Disconnected → Remove-VpnConnection -Force
        │
        ├─ removed → continue
        └─ still connected → RAS_CLEANUP_INCOMPLETE + pause later dials
```

### 2.10. Existing-profile lifecycle

```text
Get-VpnConnection (User) + Get-VpnConnection -AllUserConnection
        │
        ▼
Detect name collision / split tunneling / unparseable address
        │
        ├─ any ambiguity → INCONCLUSIVE/KEEP
        ▼
TCP probe (multiple attempts) → dial with stored credentials
        │
        ├─ 691/649 → retry with Username/Password
        ├─ 633 → disconnect + retry
        ├─ 619/628/629/631 → delayed retry (maximum 2)
        ▼
Connected → IP comparison → latency → download → (if no download) internet probe
        │
        ▼
Verdict + PlannedAction
        │
        ▼
Summary → (optional) YES → Remove in the original scope → CSV
```

### 2.11. External dependencies

| Dependency | Type | Used for | Behavior if missing |
|---|---|---|---|
| `VpnClient` PowerShell module | Windows module | `Add/Get/Set/Remove-VpnConnection` | Terminating error at startup |
| `rasdial.exe` | Windows binary | Dial/disconnect | Terminating error at startup |
| `curl.exe` | Windows binary | IP, download, connectivity | Terminating error at startup |
| `speed.cloudflare.com` | HTTP service | Download | Sample fails; server may become `CONNECTED_NO_DOWNLOAD` |
| `api.ipify.org` | HTTP service | Public IP | Empty IP → route unknown |
| `ipspeed.info` | List source | Primary list | Fallbacks |
| `v-dot-pn-ams2.opengw.net` | List source | VPN Gate | Warning; continue with primary |
| `raw.githubusercontent.com` | List source | Final fallback | Warning; continue |
| `r.jina.ai` | Mirror | Readable-text fallback | Warning |

### 2.12. Deliberate differences from v17/v17.1

| Topic | v16.1 (target) | v17/v17.1 (out of scope) |
|---|---|---|
| Download sample criterion | Any real bytes over HTTP 2xx | Requires a complete 10 MB download |
| Slow but healthy server | Accepted; `DownloadComplete=false` | Rejected |
| New-server test engine | v16 | Changed |
| Existing-profile phase | Present (backported with stricter removal) | Present |
| Purpose of this document | Reimplement v16.1 | Comparison reference |

---

## 3. Domain model

### 3.1. `Server`

Every source row is normalized to this record:

| Field | Type | Description |
|---|---|---|
| `Country` | string | Country or region from the source; may be empty. |
| `Source` | string | `ipspeed.info`, `VPN Gate`, `clipboard`, `local HTML`, `CSV snapshot`, or `final fallback list`. |
| `Server` | string | Canonical address: `host`, `host:port`, `[ipv6]`, or `[ipv6]:port`. |
| `Host` | string | Host without brackets. |
| `Port` | int | Port in the range 1–65535. |
| `PingMs` | number? | PING published by the source; `null` means unknown. |
| `UptimeText` | string | Uptime text from the source; may be empty. |
| `UptimeMinutes` | number? | Uptime normalized to minutes; `null` means unknown. |
| `InputOrder` | int | In-memory only; stable tie-breaker after sorting. |

**Unique key:** `Server` after `ToLowerInvariant()`. `Example.com:443` and `example.com:443` are the same endpoint.

### 3.2. `Target` and canonicalization

`Resolve-SstpServerTarget` produces:

| Field | Type | Description |
|---|---|---|
| `Host` | string | Final host without brackets. |
| `Port` | int | Final port. |
| `ServerAddress` | string | Canonical form expected by Windows. |

Canonicalization rules:

| Input | Output |
|---|---|
| `example.com` | `example.com` (port 443) |
| `example.com:1909` | `example.com:1909` |
| `1.2.3.4` | `1.2.3.4` |
| `1.2.3.4:1909` | `1.2.3.4:1909` |
| `[2001:db8::1]` | `[2001:db8::1]` |
| `[2001:db8::1]:1909` | `[2001:db8::1]:1909` |
| `2001:db8::1` | `[2001:db8::1]` (IPv6 without a port) |

Detailed rules:

- IPv6 is always rendered in brackets.
- If the port is 443, the port suffix is omitted.
- An unbracketed IPv6 literal is allowed only when it has no explicit port. `2001:db8::1:443` is interpreted as an IPv6 address, not `host:port`.
- A trailing dot on an FQDN (`example.com.`) is removed during normalization.

### 3.3. Host validation (`Test-SstpHostName`)

A host is accepted when:

1. It is not empty.
2. Its length is 1–253 characters.
3. It is a valid IPv4 address (each octet 0–255), or
4. It is a valid IPv6 address (`IPAddress.TryParse` with `InterNetworkV6`), or
5. It is a valid FQDN matching:

```regex
^(?i)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$
```

Brackets around IPv6 are removed before validation.

### 3.4. `TcpResult`

| Field | Type | Description |
|---|---|---|
| `Reachable` | bool | TCP connection established? |
| `Milliseconds` | number? | Connect time, one decimal place. |
| `Error` | string | `TCP timeout` or the exception message. |

### 3.5. `DialResult`

| Field | Type | Description |
|---|---|---|
| `ExitCode` | int | `rasdial` exit code; timeout = `-1`. |
| `TimedOut` | bool | Was the process killed by the timeout? |
| `StdOut` | string | Standard output. |
| `StdErr` | string | Standard error. |
| `Seconds` | number | Elapsed time, two decimal places. |

### 3.6. `LatencyResult`

| Field | Type | Description |
|---|---|---|
| `LatencyMs` | number? | Median of successful samples. |
| `Method` | `ICMP` \| `TCP` \| `none` | Measurement method. |
| `SuccessfulSamples` | int | Number of successful samples. |
| `Samples` | string | Sample values joined with `\|`. |
| `Min` / `Max` | number? | Minimum and maximum. |
| `Error` | string | Unique errors, truncated to 350 characters. |

### 3.7. `DownloadResult`

| Field | Type | Description |
|---|---|---|
| `Samples` | array | Per sample: `Sample`, `Mbps`, `MB`, `Seconds`, `Complete`, `HttpCode`, `TimedOut`, `Error`. |
| `SuccessfulSamples` | int | Samples with a non-null `Mbps`. |
| `MedianMbps` | number? | Median speed of successful samples. |
| `AverageMbps` | number? | Average speed. |
| `MinMbps` / `MaxMbps` | number? | Minimum and maximum. |
| `TotalMB` / `TotalSeconds` | number? | Sums over successful samples. |
| `AllComplete` | bool | Every sample succeeded and was complete. |
| `Error` | string | Overall error when no sample succeeded. |
| `SampleErrors` | string | Errors from failed samples. |

### 3.8. `TestRecord` (new server)

This record is serialized to the results CSV. The logical fields are listed in Section 9. Important semantics:

- `VPNServerAddress` is the canonical address.
- `WindowsStoredServerAddress` is what Windows reports after `Add-VpnConnection`.
- `ProfilePortVerified` becomes `true` only after host and port match.
- `MeasuredLatencyMs` is computed after testing: `VPNLatencyMs` if > 0, otherwise `TcpConnectMs` if > 0, otherwise `null`.
- `SpeedScore`, `LatencyScore`, and `SelectionScore` are added after all tests.

### 3.9. `ExistingProfile`

| Field | Type | Description |
|---|---|---|
| `Name` | string | Profile name, trimmed. |
| `Scope` | `User` \| `AllUser` | Phonebook scope. |
| `ServerAddress` | string | Address stored by Windows. |
| `TunnelType` | string | For example `Sstp`, `L2tp`, `Pptp`, `Ikev2`. |
| `ConnectionStatus` | string | `Connected`, `Disconnected`, or another Windows value. |
| `SplitTunneling` | bool | Is split tunneling enabled? |
| `NameCollision` | bool | Does the same name exist in another phonebook or more than once? |

### 3.10. `VerificationRecord` (existing profile)

Contains the 45 CSV fields in Section 9. Decision fields:

| Field | Values |
|---|---|
| `Status` | One of the existing-profile statuses. |
| `Verdict` | `ACCEPT` \| `REJECT` \| `INCONCLUSIVE` \| `SKIPPED` |
| `PlannedAction` | `KEEP` \| `DELETE` |
| `ActionTaken` | `KEPT` \| `REMOVED` \| `REMOVE_FAILED` \| `REPORT_ONLY_NOT_REMOVED` \| `NOT_REMOVED_BY_USER_CHOICE` \| `NOT_APPLICABLE` |
| `PostTestDisconnectFailed` | bool |

---

## 4. Source acquisition and parsing

### 4.1. Primary source (`-Url`)

`Get-SstpServers` makes three attempts, in order:

1. The configured `$PageUrl`.
2. `https://r.jina.ai/http://<hostPart>`.
3. `https://r.jina.ai/https://<hostPart>`.

`hostPart` is the original URL with a leading `http://` or `https://` removed. Each request uses:

- `Invoke-WebRequest` with a 30-second timeout.
- A Chrome-like User-Agent (Chrome 128 on Windows).
- `-SkipHttpErrorCheck` so error bodies are still inspected.

If the response contains Cloudflare challenge markers (`Just a moment`, `Enable JavaScript and cookies to continue`, `cf_chl_`, `challenge-platform`), a challenge warning is recorded. If the status is ≥ 400, an HTTP warning is recorded. If no recognizable server row is found, a "did not contain recognizable server rows" warning is recorded.

If no source yields a result, a guidance error is thrown suggesting the clipboard or a saved HTML file.

### 4.2. Generic table parser (`Convert-ServerListContent`)

**HTML path:**

- Extract all `<tr>` elements with a regex.
- Each row must contain at least three `<td>` cells.
- `Country` = cell index 1.
- `Host` = cell index 2.
- From cell index 3 onward:
  - The first text matching the uptime pattern becomes `UptimeText`.
  - The first text matching the PING pattern becomes `PingMs`.
- The server address is extracted from the host cell with:

```regex
(?i)(?<server>\[[0-9a-fA-F:.]+\](?::\d{1,5})?|(?:(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}|(?:\d{1,3}\.){3}\d{1,3})(?::\d{1,5})?)
```

- Unbracketed IPv6 is intentionally unsupported here so that a textual `a:b` is not misread as an IPv6 address.
- Each row is validated with `Parse-SstpServerAddress`.
- At the end, duplicates are removed by `Server` (case-insensitive).

**Plain-text fallback:**

If no HTML rows are found, lines that start with a row number are inspected:

```regex
^\s*\|?\s*\d{1,3}(?:\.|\s*\||\s+)
```

- The country is taken from the text before the host; the leading row number is removed.
- `PingMs` and `UptimeText` are read from the rest of the line.
- Headers such as `LOCATION`, `COUNTRY`, and `---` are skipped.

### 4.3. VPN Gate parser (`Convert-VpnGateServerListContent`)

VPN Gate publishes only servers that have an `MS-SSTP` column and the phrase `SSTP Hostname`.

**HTML path:**

- Process every `<tr>` containing `SSTP Hostname`.
- `Country` = cell index 0.
- Find the cell containing `SSTP Hostname`.
- Extract the endpoint with:

```regex
(?i)SSTP\s+Hostname\s*:?\s*(?<server>[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?(?::\d{1,5})?)
```

- Search cells 1 and later for PING and uptime.
- Rows without `SSTP Hostname` (for example, UDP-only rows) are deliberately skipped; guessing a port is forbidden.

**Plain-text path:**

- Extract every line containing `SSTP Hostname : host[:port]`.
- Attempt to recover PING, uptime, and country from the same line.
- The country is guessed from the beginning of the line before the `opengw.net` domain or IPv4 address.

### 4.4. Parser selection (`Convert-AnyServerListContent`)

Both parsers run on the content:

- If the VPN Gate parser produced at least one result and its count is ≥ the generic parser's count, use the VPN Gate result.
- Otherwise, if the generic parser produced a result, use it.
- Otherwise, return the VPN Gate result (even if empty).

This rule handles pages that look like a generic table and also contain an SSTP column.

### 4.5. Plain host-list parser (`Convert-PlainSstpHostListContent`)

Format of `sstp_hosts.txt`:

```text
# comment
=== Japan (JP) - 195 servers ===
vpn123.opengw.net:443
vpn456.opengw.net:1556
```

Rules:

- Skip empty lines and lines starting with `#`.
- Recognize section headers with `^=+\s*(?<country>.+?)\s*=+$`; remove the trailing `(CC) - N servers` phrase from the country.
- Remove trailing comments (` # ...`).
- Trim trailing `,` and `;`.
- Remove a `sstp://` prefix.
- Reject a line that still contains whitespace after normalization (prose).
- Accept only a valid `host[:port]`.
- Set `PingMs=null`, `UptimeText=''`, `UptimeMinutes=null`.
- Remove duplicates.

### 4.6. CSV snapshot loader (`Get-SstpServersFromCsv`)

- The file must exist and must not be empty.
- Required columns: `Country`, `Server`, `Host`, `Port`.
- `Source` is optional; when empty, use `CSV snapshot`.
- `PingMs` is optional: a valid number ≥ 0 or text of the form `NN ms`.
- `UptimeText` or `Uptime`; `UptimeMinutes` is optional.
- Address priority:
  1. The `Server` column (authoritative when it contains an explicit port).
  2. The `Host` column (when `Server` is empty or invalid).
  3. The `Port` column only when the address has no explicit port.
- If `Server` has an explicit port that differs from the `Port` column: warn, but use the address port.
- Invalid port → skip the row with a warning.
- Invalid host → skip the row silently.
- At the end, remove duplicates by `Server`.
- If no valid row remains, throw: `No valid server entries were found in the CSV. Required columns: Country, Server, Host, Port.`

> The `Host` column is treated as a bare host. A value such as `example.com:443` is not split into host and port; use the `Server` column for an address with a port.

### 4.7. Supplementary sources and fallback

| Mode | Sources used |
|---|---|
| Default | `Url` + all `ExtraSourceUrl` entries |
| `-NoExtraSource` | Only `Url`; final fallback is also disabled |
| `-ExtraSourceOnly` | Only `ExtraSourceUrl`; no primary/clipboard/HTML/CSV/final |
| `-FinalFallbackOnly` | Only `FinalFallbackUrl` |
| `-ServerListCsv` | Only the CSV snapshot; no web source |
| `-HtmlFile` | Local HTML + extra sources |
| `-UseClipboard` | Clipboard; if empty/invalid, primary; then extra; then final |
| `-ListOnly` | Normal acquisition, then exit |

**Important:** if `-UseClipboard` is combined with `-ServerListCsv`, the CSV wins because the clipboard branch requires an empty `ServerListCsv`.

**Note:** `-FinalFallbackOnly` cannot be combined with `-ServerListCsv`, `-HtmlFile`, `-ExtraSourceOnly`, or `-NoExtraSource`.

### 4.8. Source fetching and error handling

`Get-SstpServersFromUrls`:

- Skip empty URLs.
- Call `Get-SstpServers` for each URL.
- Collect errors as `URL: message` (truncated to 220 characters plus `...`).
- Return `{ Servers, Errors }`.

`Merge-ExtraServerSources`:

- An empty URL list returns no error.
- Append results to the target list and return errors.
- A supplementary-source error is never fatal.

`Get-SstpServersFromPlainHostListUrls`:

- For each URL, try the URL itself, then `https://r.jina.ai/<url>`.
- 30-second timeout.
- If no valid host is found, record an error.
- Return `{ Servers, Errors }`.

### 4.9. Merge and deduplication (`Merge-SstpServerLists`)

- Key: `Server.Trim().ToLowerInvariant()`.
- A new key is appended.
- For a duplicate:
  - If the existing record has no PING and the new one does → replace.
  - If both have a PING and the new one is lower → replace.
  - Otherwise keep the existing record.
- On replacement: if the new `Country` is empty, fill it from the old record; if the new `UptimeText` is empty, fill it from the old record and derive `UptimeMinutes` when needed.
- On non-replacement: if the existing `Country` or `UptimeText` is empty, fill it from the new record.
- Final order: first appearance of each key in an `OrderedDictionary`.

### 4.10. Initial shortlist

After merge and port filtering:

1. Assign `InputOrder` to each record (1-based).
2. Stable sort by:
   - `PingMs` ascending; `null` = `Double.MaxValue` (last).
   - `UptimeMinutes` descending; `null` = `-1`.
   - `InputOrder` ascending.
3. Apply `PriorityServer` (optional) after the sort; move the matching record to the front.
4. Apply `MaxServers` (optional) after Priority.

> **`-ListOnly` behavior:** the snapshot is saved after the port filter, PING sort, and `PriorityServer`, but **before** `MaxServers`. The snapshot therefore contains every sorted candidate, not only the first N.

### 4.11. `PriorityServer` logic

- Parse the input with `Parse-SstpServerAddress`.
- If invalid: warn and keep the PING order.
- Compare host case-insensitively, trim trailing dots, strip IPv6 brackets, and compare the port exactly.
- If found and not already first: move it to the front, preserving the order of the rest.
- If not found: warn and keep the PING order.

### 4.12. PING and uptime patterns

**PING:**

```regex
(?i)(?<!\d)(?<ms>\d{1,5}(?:\.\d{1,2})?)\s*ms(?![\p{L}\d])
```

- Only `NN ms` or `NN.NN ms`; a dash or any other text means `null`.
- Parse with `InvariantCulture`.

**Uptime:**

```regex
(?<n>\d+(?:\.\d+)?)\s*(?<unit>months?|days?|hours?|hrs?|minutes?|mins?|d|h|m)\b
```

- month = 43,200 minutes.
- day = 1,440 minutes.
- hour = 60 minutes.
- minute = 1 minute.
- Sum all components and round to two decimals.
- `Get-UptimeTextFromLine` returns the first valid sequence of units.

### 4.13. Median

`Get-MedianValue`:

- Empty array → `null`.
- Sort ascending.
- Odd count → middle value.
- Even count → average of the two middle values.
- Round to two decimals.

---

## 5. Command-line interface

### 5.1. CLI principles

- Parameter names and switches MUST be preserved exactly so existing `.cmd` launchers and user commands continue to work.
- PowerShell parameter names are case-insensitive; a port SHOULD register the same names in the same shape.
- Every switch defaults to `false`.
- Numeric parameters have `ValidateRange`; an out-of-range value MUST be rejected before execution, not clamped.
- `-PortFilter` is an alias for `-PortMode` and MUST be supported.
- Enum values are case-insensitive on input, but output status strings MUST be uppercase and exact.
- `-OutputCsv` and `-ServerListCsv` accept relative and absolute paths; normalize the final path with `GetFullPath`.

### 5.2. Source and mode parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Url` | string | `https://ipspeed.info/free-sstp.php` | Primary list page. |
| `-ExtraSourceUrl` | string[] | `@('http://v-dot-pn-ams2.opengw.net:34637/en/')` | One or more supplementary sources (VPN Gate). |
| `-NoExtraSource` | switch | false | Disable supplementary sources and the final fallback. |
| `-ExtraSourceOnly` | switch | false | Use only supplementary sources; no primary/clipboard/HTML/CSV. |
| `-FinalFallbackOnly` | switch | false | Use only `-FinalFallbackUrl`. |
| `-FinalFallbackUrl` | string | `https://raw.githubusercontent.com/Delta-Kronecker/Vpn-Gate/refs/heads/main/sstp_hosts.txt` | Plain host list for the last fallback. |
| `-UseClipboard` | switch | false | Read the list from the clipboard. |
| `-HtmlFile` | string | `''` | Path to a saved HTML capture. |
| `-ServerListCsv` | string | `''` | Path to a snapshot CSV; no web source is fetched. |
| `-PriorityServer` | string | `''` | `host[:port]` to move to the front of the queue. |
| `-ListOnly` | switch | false | Acquire, filter, sort, and save a snapshot, then exit. |
| `-VerifyExisting` | switch | false | Standalone existing-profile verification, then exit. |
| `-PruneFirst` | switch | false | Verify existing profiles, then continue with the normal run. |
| `-ReportOnly` | switch | false | Report only during the existing-profile phase; never delete. |
| `-ListExisting` | switch | false | List existing profiles and exit; no dial. |
| `-Help` | switch | false | Show help and exit; before the Administrator check. |

### 5.3. Test and measurement parameters

| Parameter | Type | Range | Default | Description |
|---|---|---|---|---|
| `-ConnectTimeoutSec` | int | 10–300 | `150` | Maximum time for one SSTP dial. |
| `-SpeedTimeoutSec` | int | 1–120 | `12` | Maximum time for one download sample. |
| `-SpeedSamples` | int | 1–5 | `1` | Download samples per server; median is used. |
| `-SpeedDownloadBytes` | int | 1,000,000–100,000,000 | `10000000` | Bytes requested per sample. |
| `-SpeedTestUrl` | string | — | `https://speed.cloudflare.com/__down?bytes={0}` | URL template; `{0}` is replaced with the byte count. |
| `-LatencyTestHost` | string | — | `1.1.1.1` | Latency target inside the tunnel. |
| `-LatencyTestPort` | int | 1–65535 | `443` | TCP fallback port. |
| `-LatencyTimeoutMs` | int | 250–10,000 | `2000` | Timeout per latency probe. |
| `-LatencySamples` | int | 1–5 | `1` | Probes per measurement; median is used. |
| `-RankMode` | enum | `Speed`, `Balanced`, `Latency` | `Balanced` | Final ranking formula. |
| `-MaxServers` | int | 0–10,000 | `0` | 0 = all; otherwise the first N servers after sorting. |
| `-PortMode` | enum | `All`, `443`, `Non443` | `All` | Port filter; alias: `-PortFilter`. |
| `-TcpTimeoutMs` | int | 250–10,000 | `1800` | TCP probe timeout. |
| `-RasRecoveryDelaySec` | int | 1–30 | `4` | RAS recovery/cleanup delay. |
| `-Ras633Retries` | int | 0–3 | `1` | Retries after local RAS 633. |
| `-TrySstpAfterTcpTimeout` | switch | false | false | Dial even when the TCP probe times out (not when it is refused). |
| `-ContinueAfterLocalRas633` | switch | false | false | Continue later dials after repeated 633. |

### 5.4. Credential, output, and profile parameters

| Parameter | Type | Range | Default | Description |
|---|---|---|---|---|
| `-Username` | string | — | `vpn` | VPN username for new profiles and fallback. |
| `-Password` | string | — | `vpn` | VPN password. |
| `-OutputCsv` | string | — | `''` | Results CSV path; empty = `sstp_test_results_<timestamp>.csv` next to the script. |
| `-AddBestVpnCount` | int | 0–20 | `3` | Number of best confirmed servers to install. 0 disables. |

### 5.5. Existing-profile parameters

| Parameter | Type | Range | Default | Description |
|---|---|---|---|---|
| `-ExistingRemovalMode` | enum | `Balanced`, `Conservative` | `Balanced` | Removal policy for existing profiles. |
| `-ExistingTcpAttempts` | int | 1–5 | `3` | TCP probes used to confirm a failure. |
| `-ExistingTcpRetryDelaySec` | int | 0–10 | `1` | Delay between TCP probes. |
| `-TransientDialRetryDelaySec` | int | 0–60 | `15` | Delay before retrying after RAS 619/628/629/631. |

### 5.6. Complete defaults block

```text
Url                       = https://ipspeed.info/free-sstp.php
ExtraSourceUrl            = @('http://v-dot-pn-ams2.opengw.net:34637/en/')
NoExtraSource             = false
ExtraSourceOnly           = false
FinalFallbackOnly         = false
FinalFallbackUrl          = https://raw.githubusercontent.com/Delta-Kronecker/Vpn-Gate/refs/heads/main/sstp_hosts.txt
ConnectTimeoutSec         = 150
SpeedTimeoutSec           = 12
SpeedSamples              = 1
SpeedDownloadBytes        = 10000000
SpeedTestUrl              = https://speed.cloudflare.com/__down?bytes={0}
LatencyTestHost           = 1.1.1.1
LatencyTestPort           = 443
LatencyTimeoutMs          = 2000
LatencySamples            = 1
RankMode                  = Balanced
MaxServers                = 0
PortMode                  = All
TcpTimeoutMs              = 1800
RasRecoveryDelaySec       = 4
Ras633Retries             = 1
Username                  = vpn
Password                  = vpn
OutputCsv                 = ''
HtmlFile                  = ''
ServerListCsv             = ''
PriorityServer            = ''
AddBestVpnCount           = 3
UseClipboard              = false
ListOnly                  = false
TrySstpAfterTcpTimeout    = false
ContinueAfterLocalRas633  = false
VerifyExisting            = false
PruneFirst                = false
ReportOnly                = false
ListExisting              = false
ExistingRemovalMode       = Balanced
ExistingTcpAttempts       = 3
ExistingTcpRetryDelaySec  = 1
TransientDialRetryDelaySec = 15
Help                      = false
```

### 5.7. Combination validation rules

These rules run **before** any environment check and MUST preserve both their order and their messages.

| ID | Condition | Message / behavior |
|---|---|---|
| V1 | `ExtraSourceOnly` and `NoExtraSource` | `-ExtraSourceOnly cannot be combined with -NoExtraSource.` |
| V2 | `ExtraSourceOnly` and non-empty `ServerListCsv` | `-ExtraSourceOnly cannot be combined with -ServerListCsv. Use -ServerListCsv alone to reuse a saved snapshot.` |
| V3 | `FinalFallbackOnly` and (`ExtraSourceOnly` or `NoExtraSource`) | `-FinalFallbackOnly cannot be combined with -ExtraSourceOnly or -NoExtraSource.` |
| V4 | `FinalFallbackOnly` and (`ServerListCsv` or `HtmlFile`) | `-FinalFallbackOnly cannot be combined with -ServerListCsv or -HtmlFile.` |
| V5 | `FinalFallbackOnly` and empty `FinalFallbackUrl` | `-FinalFallbackOnly requires a non-empty -FinalFallbackUrl value.` |
| V6 | `VerifyExisting` and `PruneFirst` | `-VerifyExisting and -PruneFirst cannot be combined. Use -VerifyExisting for a standalone cleanup run or -PruneFirst before a normal run.` |
| V7 | `ReportOnly` without `VerifyExisting`/`PruneFirst` | `-ReportOnly only affects existing-profile verification; combine it with -VerifyExisting or -PruneFirst.` |
| V8 | (`VerifyExisting` or `PruneFirst`) and (`ExtraSourceOnly` or `FinalFallbackOnly` or `ListOnly` or `ListExisting`) | `-VerifyExisting and -PruneFirst cannot be combined with -ExtraSourceOnly, -FinalFallbackOnly, -ListOnly, or -ListExisting.` |
| V9 | `ListExisting` and (`VerifyExisting` or `PruneFirst` or `ListOnly` or `ExtraSourceOnly` or `FinalFallbackOnly`) | `-ListExisting is a standalone inventory command; do not combine it with other modes.` |
| V10 | `ListExisting` and `ReportOnly` | `-ListExisting does not delete anything; -ReportOnly is not needed.` |

**Evaluation order:** V1 → V2 → V3/V4/V5 → V6 → V7 → V8 → V9 → V10. Preserve this order so comparative message tests remain stable.

### 5.8. Valid mode matrix

| Mode | Key parameters | Operation | Output |
|---|---|---|---|
| Help | `-Help` | Print help | Exit; no environment checks |
| Inventory | `-ListExisting` | List both phonebooks | `sstp_existing_profiles_<ts>.csv` |
| Verify dry-run | `-VerifyExisting -ReportOnly` | Test SSTP profiles; no deletion | `sstp_existing_profile_check_<ts>.csv` |
| Verify apply | `-VerifyExisting` | Test + summary + `YES` + removal | CSV + removal |
| Prune + normal | `-PruneFirst` | Existing-profile phase + new-server test | Two CSVs |
| Prune dry-run | `-PruneFirst -ReportOnly` | Existing-profile phase without deletion + new-server test | Two CSVs |
| List only | `-ListOnly` | Acquire/sort/save snapshot | `sstp_server_list_<ts>.csv` |
| Snapshot test | `-ServerListCsv <path>` | Test from CSV; no web | Results CSV |
| Clipboard | `-UseClipboard` | Clipboard → primary → extra → final | Results CSV |
| Extra only | `-ExtraSourceOnly` | VPN Gate only | Results CSV |
| Final only | `-FinalFallbackOnly` | Plain list only | Results CSV |
| Normal | no special mode | Primary + extra | Results CSV + new profiles |

> **Note:** every mode except `-Help` passes the environment checks (Windows, PowerShell 7, Administrator, `VpnClient`, `curl.exe`, `rasdial.exe`). `-ListExisting` and `-ListOnly` therefore also require Administrator.

### 5.9. Invocation examples

```powershell
# List existing profiles only.
.\Test-FreeSstpServers_v16_1.ps1 -ListExisting

# Test existing profiles without deleting anything (recommended first run).
.\Test-FreeSstpServers_v16_1.ps1 -VerifyExisting -ReportOnly

# Test and remove after an explicit YES.
.\Test-FreeSstpServers_v16_1.ps1 -VerifyExisting

# Prune existing profiles, then test 10 Non443 servers from the clipboard.
.\Test-FreeSstpServers_v16_1.ps1 -PruneFirst -UseClipboard -PortMode Non443 -MaxServers 10

# Acquire the list and save a snapshot only.
.\Test-FreeSstpServers_v16_1.ps1 -UseClipboard -ListOnly

# Re-test a snapshot without downloading the list again.
.\Test-FreeSstpServers_v16_1.ps1 -ServerListCsv .\sstp_server_list_20261105_065304.csv -MaxServers 5 -AddBestVpnCount 0

# VPN Gate only.
.\Test-FreeSstpServers_v16_1.ps1 -ExtraSourceOnly -PortMode Non443 -MaxServers 30

# Delta-Kronecker plain list only.
.\Test-FreeSstpServers_v16_1.ps1 -FinalFallbackOnly -PortMode All -MaxServers 30

# Longer run with three download samples and speed-first ranking.
.\Test-FreeSstpServers_v16_1.ps1 -UseClipboard -PortMode Non443 -MaxServers 10 -RankMode Speed -SpeedSamples 3 -AddBestVpnCount 5
```

### 5.10. `-Help` behavior

- Run `Get-Help -Name $PSCommandPath -Full | Out-Host`.
- Then `return`.
- This happens **before** the Windows, PowerShell 7, and Administrator checks.
- A port MUST show help without Administrator rights and without changing the system.
- By contrast, `-ListExisting` and `-ListOnly` require PowerShell 7, Administrator, `VpnClient`, `curl.exe`, and `rasdial.exe` because environment checks precede mode dispatch.

### 5.11. CLI compatibility notes

- `-ExtraSourceUrl` accepts multiple values; in PowerShell, use an array or comma-separated values.
- `-PortFilter` MUST map to the same `PortMode` value.
- Enum values MUST be accepted case-insensitively; output status strings MUST be exact uppercase.
- Out-of-range numeric values MUST produce a validation error, not automatic clamping.
- `-OutputCsv` and `-ServerListCsv` MUST accept relative and absolute paths; normalize with `GetFullPath`.

---

## 6. New-server workflow

This is the v16 engine. It runs after the existing-profile phase when `-PruneFirst` is used, or directly in a normal run.

### 6.1. List preparation and snapshot

After acquiring and merging the list:

1. Record `serverCountBeforePortFilter = servers.Count`.
2. Apply `PortMode`:
   - `All`: no change.
   - `443`: keep only `Port == 443`.
   - `Non443`: keep only `Port != 443`.
3. If the result is empty, throw: `No servers matched -PortMode '<mode>'. Use -PortMode All or refresh the server list.`
4. Assign `InputOrder` (1-based).
5. Sort by PING/uptime/InputOrder as described in Section 4.10.
6. Apply `PriorityServer`.
7. Save the snapshot with columns:
   `Country, Source, Server, Host, Port, PingMs, UptimeText, UptimeMinutes`
8. If `-ListOnly`, print a success message and `return`.
9. Read `listFetchIp4 = Get-PublicIp(IPv4)` **before** truncation.
10. Apply `MaxServers` when > 0.
11. Print threshold messages and enter baseline confirmation.

> The snapshot is always saved in a normal run, even without `-ListOnly`. It is the evidence of the input list and a valid input for `-ServerListCsv`.

### 6.2. Baseline confirmation and temporary VPN disconnection

Interactive loop:

```text
while true:
    input = Read-Host("After disconnecting all other VPNs, press Enter to verify and start tests (or type Q to quit)")
    if input matches '^q$' (case-insensitive):
        throw "Stopped by user. The downloaded server list is saved at: <snapshotPath>"

    active = Get-ActiveWindowsVpnConnections()
    if active.Count > 0:
        warn "Windows still reports these VPN connections as active: <names>. Disconnect them and press Enter again."
        continue

    sleep 2
    baselineIPv4 = Get-PublicIp(IPv4)
    baselineIPv6 = Get-PublicIp(IPv6)

    if baselineIPv4 == '' and baselineIPv6 == '':
        warn "Could not read a public IPv4 or IPv6 address..."
        manual = Read-Host("Type YES only if you have manually confirmed all other VPNs are disconnected; otherwise press Enter to retry")
        if manual == 'YES' (case-sensitive):
            break   # continue without a baseline
        continue

    routeTestFamily = if baselineIPv4 != '' then 'IPv4' else 'IPv6'

    if usedVpnRetry and listFetchIp4 != '' and baselineIPv4 != '' and baselineIPv4 == listFetchIp4:
        warn "The public IPv4 address (...) is unchanged from when the list was fetched..."
        manual = Read-Host("Disconnect/check the VPN again. Type YES to continue anyway only if you are sure; otherwise press Enter to retry")
        if manual == 'YES':
            break
        continue

    break
```

**Meaning of `usedVpnRetry`:** it becomes `true` when the user chooses the `V` option in the fallback menu and fetches the list with a VPN active. If the baseline IP then equals the list-fetch IP, the VPN is probably still active and the warning is shown.

**`Get-ActiveWindowsVpnConnections`:** reads per-user and AllUser profiles, keeps only records whose `ConnectionStatus` is `Connected`, and returns them sorted and unique by `Name`. Errors from either phonebook are ignored.

**If the baseline cannot be read and the user types `YES`:**

- Testing continues.
- `BaselineIPv4` and `BaselineIPv6` stay empty.
- Every connected server gets `PublicIPChanged = Unknown` and lands in `CONNECTED_IP_UNKNOWN` or `CONNECTED_NO_DOWNLOAD`; it can never become `WORKING_TUNNEL_AND_INTERNET`.

### 6.3. Main loop pseudocode

```text
runId = now.Format("MMddHHmmss")
results = []
stopFurtherVpnAttempts = false
stopReason = ""

for index, server in servers (1-based):
    target = Resolve-SstpServerTarget(server)
    profileName = "SSTPCHK_{runId}_{index:D3}"

    record = new TestRecord(
        Country=server.Country, Source=server.Source,
        Server=target.ServerAddress, Host=target.Host, Port=target.Port,
        PingMs=server.PingMs, VPNServerAddress=target.ServerAddress,
        BaselineIPv4=baselineIPv4, BaselineIPv6=baselineIPv6, ...)

    tcp = Test-TcpPort(target.Host, target.Port, TcpTimeoutMs)
    record.TcpReachable = tcp.Reachable
    record.TcpConnectMs = tcp.Milliseconds
    record.TcpProbeError = tcp.Error

    if stopFurtherVpnAttempts:
        record.Status = "SKIPPED_AFTER_RAS_STATE_UNCERTAIN"
        record.Error = "<tcpSummary>; VPN dial skipped because the prior attempt left RAS state uncertain (<stopReason>)."
        results.add(record); continue

    if not tcp.Reachable:
        if TrySstpAfterTcpTimeout and tcp.Error == "TCP timeout":
            # continue to dial
        else:
            record.Status = "TCP_UNREACHABLE"
            record.Error = tcp.Error
            results.add(record); continue

    profileCreated = false
    try:
        Add-VpnConnection(profileName, target.ServerAddress, TunnelType=SSTP,
                          AuthenticationMethod=MSChapv2, EncryptionLevel=Optional, Force)
        profileCreated = true

        profileCheck = Get-VpnConnection(profileName)
        storedAddress = profileCheck.ServerAddress.Trim()
        record.WindowsStoredServerAddress = storedAddress

        storedParsed = Parse-SstpServerAddress(storedAddress)
        if not storedParsed:
            record.Status = "PROFILE_PORT_MISMATCH"
            record.Error = "Windows profile stored '<stored>', which could not be parsed; expected '<target>'."
            throw

        if storedParsed.Host.TrimEnd('.') != target.Host.TrimEnd('.')
           or storedParsed.Port != target.Port:
            record.Status = "PROFILE_PORT_MISMATCH"
            record.Error = "Windows profile stored '<stored>' (parsed host '<h>', port <p>); expected '<target>' (port <tp>)."
            throw

        record.ProfilePortVerified = true

        dialAttempts = 0
        rasDisconnectTimedOut = false
        do:
            dialAttempts++
            dial = Invoke-NativeTimed(rasdial, [profileName, Username, Password], ConnectTimeoutSec)
            record.VPNConnectSeconds += dial.Seconds
            if dial.TimedOut or dial.ExitCode == 0: break

            rasCode = Get-RasErrorCode(dialText, dial.ExitCode)
            if rasCode == 633 and dialAttempts <= Ras633Retries:
                disconnect = rasdial profileName /disconnect (12s timeout)
                if disconnect.TimedOut:
                    rasDisconnectTimedOut = true; break
                sleep RasRecoveryDelaySec
                continue
            break
        while dialAttempts <= Ras633Retries

        record.DialAttempts = dialAttempts

        if rasDisconnectTimedOut:
            record.Status = "RAS_RECOVERY_TIMEOUT_STATE_UNCERTAIN"
            stopFurtherVpnAttempts = true
            stopReason = "rasdial /disconnect timed out during RAS recovery"
        elif dial.TimedOut:
            record.Status = "VPN_CONNECT_TIMEOUT_RAS_STATE_UNCERTAIN"
            stopFurtherVpnAttempts = true
            stopReason = "rasdial timeout at <ConnectTimeoutSec>s"
        elif dial.ExitCode != 0:
            classifyDialFailure(record, dial)
        else:
            record.VPNConnected = true
            sleep 2
            verifyRoute(record)
            measureLatency(record)
            measureDownload(record)
            classifyConnected(record)
    catch:
        if record.Status != "PROFILE_PORT_MISMATCH":
            record.Status = "PROFILE_OR_TEST_ERROR"
            record.Error = caughtMessage
        truncate error to 350
    finally:
        if profileCreated:
            cleanup = Remove-TestVpnProfileSafely(profileName, 20s, RasRecoveryDelaySec)
            if not cleanup.Removed:
                append cleanup.Error
                if cleanup.StillConnected:
                    stopFurtherVpnAttempts = true
                    stopReason = "profile cleanup failed: <profileName> remains connected"
                    if record.Status != "WORKING_TUNNEL_AND_INTERNET":
                        record.Status = "RAS_CLEANUP_INCOMPLETE"

    results.add(record)
```

### 6.4. TCP probe

`Test-TcpPort`:

```text
client = new TcpClient()
watch = Stopwatch.StartNew()
try:
    task = client.ConnectAsync(host, port)
    if not task.Wait(timeoutMs):
        client.Close()
        task.Wait(200)  # best effort
        return { Reachable=false, Milliseconds=null, Error="TCP timeout" }
    task.GetAwaiter().GetResult()
    watch.Stop()
    return { Reachable=client.Connected, Milliseconds=round(ms,1), Error="" }
catch:
    watch.Stop()
    return { Reachable=false, Milliseconds=round(ms,1), Error=exceptionMessage }
finally:
    client.Dispose()
```

Notes:

- `host` never contains brackets; they are removed upstream.
- The exact string `TCP timeout` matters: `-TrySstpAfterTcpTimeout` applies only to that string, not to refused or unreachable errors.
- `Milliseconds` is `null` on timeout and contains the elapsed time on an immediate error.

### 6.5. Temporary profile creation and verification

`Add-VpnConnection`:

```text
-Name              <SSTPCHK_runId_index>
-ServerAddress     <target.ServerAddress>
-TunnelType        SSTP
-AuthenticationMethod MSChapv2
-EncryptionLevel   Optional
-Force
```

Then:

- `Get-VpnConnection -Name <profile>` with `-ErrorAction Stop`.
- If null → exception: `Windows did not return the temporary VPN profile '<name>' for verification.`
- Parse the stored `ServerAddress` with `Parse-SstpServerAddress`.
- Host comparison: `TrimEnd('.')`, case-insensitive.
- Port comparison: exact.
- On mismatch → `PROFILE_PORT_MISMATCH` and **no dial**.
- On success → `ProfilePortVerified = true`.

**Why this check matters:** some Windows versions do not preserve the port in `ServerAddress` or store it in a different form. Testing the wrong endpoint is dangerous.

### 6.6. Dial and local RAS 633 retry

- Command: `rasdial <profileName> <Username> <Password>`.
- Process timeout: `ConnectTimeoutSec`; the process is killed with `Kill(true)`.
- `VPNConnectSeconds` is the sum of all attempts, rounded to two decimals.
- Only error `633` is retried, up to `Ras633Retries` times.
- Before a retry: `rasdial <profileName> /disconnect` with a 12-second timeout.
- If that disconnect times out → `rasDisconnectTimedOut = true` and stop.
- Otherwise sleep `RasRecoveryDelaySec` and retry.
- Maximum attempts: `Ras633Retries + 1`.
- **There is no automatic retry for 619/628/629/631 in the new-server flow.** This is an important difference from the existing-profile phase.
- Credentials are always passed on the command line; the temporary profile does not use the credential store.

### 6.7. New-server dial failure classification

After the loop:

| Condition | Status | Action |
|---|---|---|
| `rasDisconnectTimedOut` | `RAS_RECOVERY_TIMEOUT_STATE_UNCERTAIN` | `stopFurtherVpnAttempts=true` |
| `dial.TimedOut` | `VPN_CONNECT_TIMEOUT_RAS_STATE_UNCERTAIN` | `stopFurtherVpnAttempts=true` |
| `rasCode == 633` | `LOCAL_RAS_ERROR_633_AFTER_RETRY` | If `ContinueAfterLocalRas633` is false → pause later dials; show diagnostics |
| `rasCode == 638` | `SSTP_RAS_TIMEOUT_638` | Continue |
| `dial.ExitCode == -2147014836` or text matches `connection attempt failed.*period of time\|timed out\|timeout` | `NETWORK_CONNECT_TIMEOUT` | Continue |
| Any other error | `VPN_CONNECT_FAILED` | Continue |

**`Get-RasErrorCode`:**

```regex
(?i)Remote Access error\s+(\d{3})
```

If the regex does not match and `ProcessExitCode` is one of `633, 638, 691, 720, 809, 810`, return that code; otherwise return `0`.

### 6.8. Route verification after connection

```text
sleep 2

vpnIp4 = ""
if baselineIPv4 != "":
    vpnIp4 = Get-PublicIp(IPv4)

vpnIp6 = ""
needIpv6Probe = baselineIPv6 != "" and
                (baselineIPv4 == "" or vpnIp4 == "" or baselineIPv4 == vpnIp4)
if needIpv6Probe:
    vpnIp6 = Get-PublicIp(IPv6)

record.VPNIPv4 = vpnIp4
record.VPNIPv6 = vpnIp6

if baselineIPv4 != "" and vpnIp4 != "":
    record.IPv4Changed = (baselineIPv4 != vpnIp4) ? "Yes" : "No"

if baselineIPv6 != "" and vpnIp6 != "":
    record.IPv6Changed = (baselineIPv6 != vpnIp6) ? "Yes" : "No"

if baselineIPv4 != "" and vpnIp4 != "":
    record.RouteVerificationFamily = "IPv4"
    record.VPNPublicIP = vpnIp4
    record.PublicIPChanged = record.IPv4Changed
elif baselineIPv6 != "" and vpnIp6 != "":
    record.RouteVerificationFamily = "IPv6"
    record.VPNPublicIP = vpnIp6
    record.PublicIPChanged = record.IPv6Changed
else:
    record.RouteVerificationFamily = ""
    record.PublicIPChanged = "Unknown"
```

Important rules:

- Compare only the same address family.
- IPv4 is preferred; IPv6 is used only when no comparable IPv4 pair exists.
- If a baseline IPv4 exists but `vpnIp4` cannot be read, the IPv6 probe runs only when a baseline IPv6 exists.
- `PublicIPChanged` is `Yes`, `No`, or `Unknown`.
- In the new-server flow, `Get-PublicIp` reads only `api.ipify.org`; the additional fallbacks are specific to the existing-profile phase.

### 6.9. Tunnel latency measurement

`Measure-TunnelLatency`:

```text
icmpValues = []
tcpValues = []
errors = []
icmpTimeout = min(LatencyTimeoutMs, 1500)

for i in 1..LatencySamples:
    ping = new Ping()
    reply = ping.Send(LatencyTestHost, icmpTimeout)
    if reply.Status == Success:
        icmpValues.add(reply.RoundtripTime)

if icmpValues.Count == 0:
    for i in 1..LatencySamples:
        tcp = Test-TcpPort(LatencyTestHost, LatencyTestPort, LatencyTimeoutMs)
        if tcp.Reachable:
            tcpValues.add(tcp.Milliseconds)
        elif tcp.Error != "":
            errors.add(tcp.Error)

values = icmpValues if icmpValues.Count > 0 else tcpValues
method = "ICMP" if icmpValues.Count > 0 else ("TCP" if tcpValues.Count > 0 else "none")
latency = median(values)
min = min(values) or null
max = max(values) or null
error = unique(errors).join(" | "), truncated to 350
```

> If ICMP produces even one successful sample, the TCP fallback does not run at all. If ICMP produces none, all TCP samples run.

### 6.10. Download measurement

For each sample, `Measure-DownloadSpeed` runs:

```text
familyArg = "--ipv6" if IPv6 else "--ipv4"
url = SpeedTestUrl.replace("{0}", DownloadBytes) if contains "{0}" else SpeedTestUrl

curl.exe <familyArg> --location --silent --show-error --fail \
  --max-time <SpeedTimeoutSec> --connect-timeout 5 \
  --output NUL \
  --write-out "%{http_code}|%{size_download}|%{time_total}|%{speed_download}" \
  <url>
```

Process timeout: `SpeedTimeoutSec + 4`.

Parse the output with:

```regex
(\d{3})\|([\d.]+)\|([\d.]+)\|([\d.]+)
```

A sample is successful (enters the median) when:

- `200 <= httpCode < 300`
- `bytes > 0`
- `seconds > 0`

Calculations:

```text
Mbps    = round(bytesPerSecond * 8 / 1_000_000, 2)
MB      = round(bytes / 1_000_000, 2)
Seconds = round(seconds, 2)
Complete = (not TimedOut) and ExitCode == 0 and bytes >= DownloadBytes * 0.95
```

**Critical difference from v17:**

- `Complete=false` does **not** reject the sample.
- Every sample with real bytes and HTTP 2xx enters the median.
- `AllComplete` is true only when every sample succeeded and was complete.
- `DownloadComplete` in the record equals `AllComplete`, not each sample's `Complete`.
- If no sample succeeds, `MedianMbps=null` and `Error` is built from unique errors.
- `SampleErrors` includes errors from failed samples, even when some samples succeeded.

### 6.11. Post-connect classification

```text
if download.MedianMbps != null:
    record.DownloadMbps = median
    record.DownloadMB = totalMB / successfulSamples
    record.DownloadSeconds = totalSeconds / successfulSamples
    record.DownloadComplete = allComplete

    if PublicIPChanged == "Yes":
        Status = "WORKING_TUNNEL_AND_INTERNET"
    elif PublicIPChanged == "No":
        Status = "CONNECTED_ROUTE_UNCONFIRMED"
    else:
        Status = "CONNECTED_IP_UNKNOWN"
else:
    Status = "CONNECTED_NO_DOWNLOAD"
    Error = SampleErrors or "Download test returned no usable sample."
```

> In the new-server flow, a failed download produces `CONNECTED_NO_DOWNLOAD` even if general internet access through the tunnel works. The separate connectivity probe exists only in the existing-profile phase.

### 6.12. Temporary profile cleanup

`Remove-TestVpnProfileSafely`:

1. `rasdial <profile> /disconnect` with a 12-second timeout (ignore errors).
2. Poll `Get-VpnConnection` every second for up to `WaitSeconds=20`.
3. If the profile does not exist or `ConnectionStatus != Connected` → disconnected.
4. If it is still connected → `Removed=false, StillConnected=true` with an error; **do not remove**.
5. If disconnected → `Remove-VpnConnection -Name <profile> -Force`.
6. If removal throws but the profile no longer exists → success.
7. Sleep `SettleSeconds = RasRecoveryDelaySec`.
8. Return `{ Removed, StillConnected, Error }`.

In the new-server `finally`:

- If `Removed=false` and `StillConnected=true`:
  - Append the error to the record (maximum 700 characters).
  - Set `stopFurtherVpnAttempts=true`.
  - Set `stopReason = "profile cleanup failed: <profile> remains connected"`.
  - If the current status is not `WORKING_TUNNEL_AND_INTERNET`, set `RAS_CLEANUP_INCOMPLETE`.
- If `Removed=false` but `StillConnected=false`:
  - Warn only; later dials do not need to stop.

### 6.13. Conditions that pause later dials

`stopFurtherVpnAttempts` becomes true only when:

1. `rasdial /disconnect` times out during RAS 633 recovery.
2. `rasdial` itself times out and is killed.
3. A temporary profile remains connected after cleanup.
4. RAS 633 persists after retries and `ContinueAfterLocalRas633` is false.

Once true:

- Later servers are **still TCP-probed**.
- Their status is `SKIPPED_AFTER_RAS_STATE_UNCERTAIN`.
- The error includes the TCP result and the stop reason.
- No new temporary profile is created.

**Conditions that do not pause the run:** 638, network timeout, `VPN_CONNECT_FAILED`, download failure, port mismatch, and general test errors. These affect only their own record.

### 6.14. Summary and console output

After all servers are tested:

- `confirmed` = records with `Status == WORKING_TUNNEL_AND_INTERNET`.
- `connectedUnverified` = records with `CONNECTED_ROUTE_UNCONFIRMED` or `CONNECTED_IP_UNKNOWN`.
- Other groups are printed without extra sorting.

Console ranking:

```text
Confirmed working:
  filter Status == "WORKING_TUNNEL_AND_INTERNET"
  sort by SelectionScore descending, then DownloadMbps descending, stable

Connected but unverified:
  filter Status in ["CONNECTED_ROUTE_UNCONFIRMED", "CONNECTED_IP_UNKNOWN"]
  sort by SelectionScore descending, then DownloadMbps descending, stable
```

Final messages:

```text
Ranking mode: <mode> (source PING only shortlisted; final order uses measured VPN latency + measured download speed).

================ CONFIRMED WORKING SERVERS ================
...
Finished: <N> server TCP checks | <T> TCP ports reachable | <V> VPN connections established | <C> confirmed working.
Full CSV report (sorted by DownloadMbps descending; includes VPNLatencyMs and SelectionScore): <path>
Speed and latency are observed during this test, not guaranteed long-term VPN values.
```

---

## 7. Existing-profile workflow

This phase is enabled only by `-ListExisting`, `-VerifyExisting`, or `-PruneFirst`. It is separate from the new-server engine. Its purpose is to test existing SSTP profiles, identify dead or non-routing ones, and remove them only after explicit confirmation.

### 7.1. Inventory (`-ListExisting`)

`Get-ExistingSstpVpnProfiles`:

1. `Get-VpnConnection` (per-user) → each item with `Scope='User'`.
2. `Get-VpnConnection -AllUserConnection` → each item with `Scope='AllUser'`.
3. Unique key: `scope|name`, lowercased.
4. Skip empty names or duplicates within the same scope.
5. For each profile: `Name`, `Scope`, `ServerAddress`, `TunnelType`, `ConnectionStatus`, `SplitTunneling`, `NameCollision=false`.
6. Group by lowercased name; if a group has more than one member, set `NameCollision=true` for every member.

`Show-ExistingVpnProfiles`:

- Table columns: `Name, Scope, TunnelType, ServerAddress, ConnectionStatus, SplitTunneling, NameCollision`.
- Counts: total, SSTP, non-SSTP, duplicate-name records.
- CSV: `sstp_existing_profiles_<yyyyMMdd_HHmmss>.csv` in `$PSScriptRoot`.
- Message: "Nothing was dialed or changed."
- Suggests running `-VerifyExisting -ReportOnly`.

> `-ListExisting` performs no dial, removal, or profile change. It does not even read the baseline IP. However, because environment checks precede mode dispatch, it still requires PowerShell 7, Administrator, `VpnClient`, `curl.exe`, and `rasdial.exe`.

### 7.2. Phase setup

`Invoke-ExistingProfileVerification` with `Mode = Standalone | PruneFirst`:

- Phase label:
  - `Standalone` → `VERIFY EXISTING WINDOWS SSTP VPN PROFILES`
  - `PruneFirst` → `PRUNE FIRST: VERIFY EXISTING WINDOWS SSTP VPN PROFILES`
- Print a description: TCP, real dial, IP change, latency, download.
- Print the removal mode and the "only after summary and YES" rule.
- Collect all profiles.
- `sstpProfiles` = `TunnelType -ieq 'Sstp'`.
- `nonSstpProfiles` = the rest.
- If there are no profiles → message and zero counters; **no CSV is created**.
- If there are no SSTP profiles → message and list the non-SSTP profiles; zero counters; **no CSV is created**.

### 7.3. Baseline confirmation in the existing-profile phase

Similar to the normal flow, with these differences:

- Prompt: `After disconnecting all other VPNs, press Enter to verify the baseline and start profile tests (or type Q to quit)`.
- `Q` → `Stopped by user before existing-profile verification.`
- Check `Get-ActiveWindowsVpnConnections`.
- `sleep 2`.
- `baselineIPv4 = Get-PublicIpRobust(IPv4)`.
- `baselineIPv6 = Get-PublicIpRobust(IPv6)`.
- If both are empty:
  - Warn.
  - `manual = Read-Host('Type YES only if you have manually confirmed all other VPNs are disconnected; otherwise press Enter to retry')`.
  - Exact `YES` → `baselineAvailable=false` and break.
  - Otherwise retry.
- `routeTestFamily = IPv4` if `baselineIPv4` exists, otherwise `IPv6`.
- `baselineAvailable=true` in the normal case.
- If `-ReportOnly` → print the report-only message.
- Otherwise → print "removal only after summary and YES".

**Difference from the normal flow:** `Get-PublicIpRobust` tries, in addition to ipify:

1. `https://checkip.amazonaws.com`
2. `https://icanhazip.com`
3. `https://ifconfig.me/ip`
4. `https://ident.me`
5. `https://api64.ipify.org`

Every response must be a valid address of the requested family; an HTML block page or an invalid response is rejected. If the response is `ip=...`, the address is extracted.

### 7.4. Profile loop

```text
results = []
index = 0
stopFurtherChecks = false
stopReason = ""

for profile in sstpProfiles:
    index++
    print "[index/total] '<name>' (Scope: <scope>, ServerAddress='<addr>')"

    if stopFurtherChecks:
        results.add(skippedRecord(profile, "SKIPPED_AFTER_RAS_STATE_UNCERTAIN",
                    "Skipped because the prior attempt left RAS state uncertain (<stopReason>)."))
        continue

    result = Test-ExistingSstpProfile(profile, baselineIPv4, baselineIPv6, routeTestFamily, ...)
    results.add(result)

    switch result.Verdict:
        ACCEPT: print KEPT ...
        REJECT: print REJECTED ...
        default: print KEPT - INCONCLUSIVE ...

    if result.PostTestDisconnectFailed:
        stopFurtherChecks = true
        stopReason = "profile '<name>' remains connected after its test"
    elif result.Status in ["DISCONNECT_FAILED_STATE_UNCERTAIN",
                           "VPN_CONNECT_TIMEOUT_RAS_STATE_UNCERTAIN",
                           "RAS_RECOVERY_TIMEOUT_STATE_UNCERTAIN"]:
        stopFurtherChecks = true
        stopReason = result.Status
    elif result.Status == "LOCAL_RAS_ERROR_633_AFTER_RETRY" and not ContinueAfterLocalRas633:
        stopFurtherChecks = true
        stopReason = "local Windows RAS error 633 after retry"
```

After the loop, non-SSTP profiles are appended as `SKIPPED` records:

- `Status=NOT_SSTP_SKIPPED`
- `Verdict=SKIPPED`
- `PlannedAction=KEEP`
- `ActionTaken=NOT_APPLICABLE`
- `Error="Tunnel type '<type>' is not SSTP; this script verifies SSTP profiles only."`

### 7.5. Per-profile test: initial guards

`Test-ExistingSstpProfile` first creates a 45-field record with default values. Then:

1. **Duplicate name across phonebooks** (`NameCollision=true`):
   - `Status=DUPLICATE_NAME_ACROSS_PHONEBOOKS`
   - `Verdict=INCONCLUSIVE`
   - `PlannedAction=KEEP`
   - `ActionTaken=KEPT`
   - Error: `The same VPN profile name exists in both User and AllUser phonebooks...`
   - Immediate return; no dial or disconnect.
2. **Split tunneling**:
   - `Status=SPLIT_TUNNELING_PROFILE_SKIPPED`
   - `INCONCLUSIVE/KEEP/KEPT`
   - Error: public-IP comparison is not reliable.
   - Immediate return.
3. **Unparseable address**:
   - `Status=PROFILE_ADDRESS_UNPARSEABLE`
   - `INCONCLUSIVE/KEEP/KEPT`
   - Error: the stored address cannot be parsed safely.
   - Immediate return.
4. Otherwise, populate `Host` and `Port` from the stored address.

### 7.6. Disconnecting a profile that was connected at start

If `WasConnectedAtStart=true`:

- `testStarted=true`.
- `Disconnect-ExistingVpnProfile` with `WaitSeconds=20`.
- If disconnection is not confirmed:
  - `Status=DISCONNECT_FAILED_STATE_UNCERTAIN`
  - `Verdict=INCONCLUSIVE`
  - `PlannedAction=KEEP`
  - `ActionTaken=KEPT`
  - Error: the profile is connected and removal is unsafe; later checks are paused.
  - Return. The `finally` block tries again; if it fails, `PostTestDisconnectFailed=true` is also set.

`Disconnect-ExistingVpnProfile`:

1. `rasdial <profile> /disconnect` with a 12-second timeout.
2. Poll the state of the same scope every second for up to 20 seconds.
3. Return `true` if `Disconnected`.
4. Return `false` if the state is empty/unreadable.
5. Return `false` on timeout.

### 7.7. Multi-attempt TCP probe

```text
tcp = null
for attempt in 1..ExistingTcpAttempts:
    tcp = Test-TcpPort(host, port, TcpTimeoutMs)
    record.TcpAttempts = attempt
    record.TcpReachable = tcp.Reachable
    record.TcpConnectMs = tcp.Milliseconds
    record.TcpProbeError = tcp.Error
    if tcp.Reachable: break
    if attempt < ExistingTcpAttempts and ExistingTcpRetryDelaySec > 0:
        sleep ExistingTcpRetryDelaySec
```

If still unreachable after all attempts:

- If `TrySstpAfterTcpTimeout` and `tcp.Error == "TCP timeout"` → try the dial.
- Otherwise:
  - `Status=TCP_UNREACHABLE`
  - `Error="TCP/<port> was unreachable after <N> attempt(s): <error>"`
  - `Balanced` → `Verdict=REJECT`, `PlannedAction=DELETE` (no `ActionTaken`).
  - `Conservative` → `INCONCLUSIVE/KEEP/KEPT`.
  - Return.

**Difference from the new-server flow:** multiple probes with delays avoid a false positive from transient packet loss. In `Balanced`, a TCP failure is treated as destination evidence, not a local RAS error.

### 7.8. Existing-profile dial and retry chain

`testStarted=true` before dialing.

```text
transientRasCodes = [619, 628, 629, 631]
dialAttempts = 0
rasDisconnectTimedOut = false
usingFallbackCredentials = false
credentialSource = "Stored Windows credentials"
attemptLog = []
transientRetryCount = 0
dial = null

do:
    dialAttempts++
    args = if usingFallbackCredentials
           then [profileName, Username, Password]
           else [profileName]
    dial = Invoke-NativeTimed(rasdial, args, ConnectTimeoutSec)
    record.VPNConnectSeconds += dial.Seconds
    record.CredentialSource = credentialSource

    if dial.TimedOut or dial.ExitCode == 0: break

    text = normalize(dial.StdOut + " " + dial.StdErr)
    attemptLog.add("attempt <n> (<credentialSource>): <text, 300 chars>")
    rasCode = Get-RasErrorCode(text, dial.ExitCode)

    # 1) credential fallback
    if not usingFallbackCredentials and rasCode in [691, 649]:
        credentialSource = "Fallback vpn/vpn (RAS 691/649 on the stored credentials)"
        usingFallbackCredentials = true
        continue

    # 2) local RAS 633
    if rasCode == 633 and dialAttempts <= Ras633Retries:
        disconnect = rasdial profileName /disconnect (12s)
        if disconnect.TimedOut:
            rasDisconnectTimedOut = true
            break
        sleep RasRecoveryDelaySec
        continue

    # 3) remote transient termination
    if rasCode in transientRasCodes and transientRetryCount < 2:
        transientRetryCount++
        if not usingFallbackCredentials and transientRetryCount >= 2:
            credentialSource = "Fallback vpn/vpn (remote terminated the stored-credential dials with RAS 619/628/629/631)"
            usingFallbackCredentials = true
        sleep TransientDialRetryDelaySec
        continue

    break
while dialAttempts <= (Ras633Retries + 4)
```

Exact rules:

- The first dial uses only the profile name so Windows can use its stored credentials.
- In fallback, `Username`/`Password` are passed explicitly.
- If 691/649 occurs on stored credentials, fallback happens **immediately**, with no delay.
- 633 is retried up to `Ras633Retries`; before each retry, disconnect and wait `RasRecoveryDelaySec`.
- 619/628/629/631 are retried at most twice; on the second retry with stored credentials, switch to fallback.
- The loop cap is `Ras633Retries + 4` so a combination of 633 and transient errors cannot run away.
- `VPNConnectSeconds` is the sum of all attempts.
- `CredentialSource` shows the last source used.

### 7.9. Existing-profile dial failure classification

After the loop:

| Condition | Status | Verdict / Action |
|---|---|---|
| `rasDisconnectTimedOut` | `RAS_RECOVERY_TIMEOUT_STATE_UNCERTAIN` | `INCONCLUSIVE / KEEP / KEPT` |
| `dial.TimedOut` | `VPN_CONNECT_TIMEOUT_RAS_STATE_UNCERTAIN` | `INCONCLUSIVE / KEEP / KEPT` |
| exit != 0 and `rasCode=633` | `LOCAL_RAS_ERROR_633_AFTER_RETRY` | `INCONCLUSIVE / KEEP / KEPT` + diagnostics |
| exit != 0 and `rasCode in [691,649]` | `CREDENTIALS_REJECTED` | `INCONCLUSIVE / KEEP / KEPT` |
| exit != 0 and `rasCode in [619,628,629,631]` | `VPN_CONNECT_REMOTE_TERMINATED` | Balanced: `REJECT / DELETE`; Conservative: `INCONCLUSIVE / KEEP / KEPT` |
| exit != 0 and (`rasCode=638` or exit=`-2147014836` or regex timeout) | `VPN_CONNECT_TIMEOUT` | Balanced: `REJECT / DELETE`; Conservative: `INCONCLUSIVE / KEEP / KEPT` |
| Any other error | `VPN_CONNECT_FAILED` | `INCONCLUSIVE / KEEP / KEPT` |

**Final `Error`:** when `attemptLog` is non-empty, it is built as `attempt 1 (...): ... | attempt 2 (...): ... | FINAL: <detail>` and limited to 1,200 characters. An explanatory message is then appended for some statuses, and the whole error is limited to 1,400 characters.

**Conservative note:** in `Conservative` mode, even TCP unreachable, remote termination, and timeout become `INCONCLUSIVE/KEEP`. Only "connected but route not confirmed" can be `REJECT`.

### 7.10. Existing-profile route verification

After a successful connection:

```text
record.VPNConnected = true
sleep 2

vpnIp4 = ""
vpnIp6 = ""
if baselineIPv4 != "": vpnIp4 = Get-PublicIpRobust(IPv4)
if baselineIPv6 != "": vpnIp6 = Get-PublicIpRobust(IPv6)
record.VPNIPv4 = vpnIp4
record.VPNIPv6 = vpnIp6

baselineFamilies = 0
comparableFamilies = 0
changedFamilies = 0

if baselineIPv4 != "":
    baselineFamilies++
    if vpnIp4 != "":
        comparableFamilies++
        record.IPv4Changed = (baselineIPv4 != vpnIp4) ? "Yes" : "No"
        if changed: changedFamilies++

if baselineIPv6 != "":
    baselineFamilies++
    if vpnIp6 != "":
        comparableFamilies++
        record.IPv6Changed = (baselineIPv6 != vpnIp6) ? "Yes" : "No"
        if changed: changedFamilies++

if changedFamilies > 0:
    record.PublicIPChanged = "Yes"
    labels = []
    if IPv4Changed == "Yes": labels.add("IPv4")
    if IPv6Changed == "Yes": labels.add("IPv6")
    record.RouteVerificationFamily = labels.join("+")
    record.VPNPublicIP = join("; ", "IPv4=<v4>" if changed, "IPv6=<v6>" if changed)
elif baselineFamilies > 0 and comparableFamilies == baselineFamilies:
    record.PublicIPChanged = "No"
    record.RouteVerificationFamily = "IPv4+IPv6" if baselineFamilies == 2
                                     else ("IPv4" if baselineIPv4 else "IPv6")
    record.VPNPublicIP = join("; ", "IPv4=<v4>" if v4, "IPv6=<v6>" if v6)
else:
    record.PublicIPChanged = "Unknown"
    record.RouteVerificationFamily = "Incomplete comparison"
```

**Differences from the new-server flow:**

- Both families are probed (when a baseline exists), not only the primary family.
- `PublicIPChanged=Yes` if **any** family changed.
- `PublicIPChanged=No` only if every baseline family is comparable and none changed.
- Otherwise `Unknown` with `RouteVerificationFamily="Incomplete comparison"`.

### 7.11. Latency, download, and connectivity

- Latency uses the same `Measure-TunnelLatency` and CLI parameters.
- `downloadFamily`:
  - If `IPv6Changed == "Yes"` and `IPv4Changed != "Yes"` → `IPv6`.
  - Otherwise → `RouteTestFamily` (the primary baseline family).
- Download uses `Measure-DownloadSpeed` and the same parameters.
- If `MedianMbps != null`:
  - `DownloadMbps`, `DownloadMB` (average per sample), `DownloadSeconds`, `DownloadComplete=AllComplete`.
  - Classification:
    - `PublicIPChanged=Yes` → `WORKING_TUNNEL_AND_INTERNET` / `ACCEPT` / `KEEP` / `KEPT`
    - `PublicIPChanged=No` → `CONNECTED_ROUTE_UNCONFIRMED` / `REJECT` / `DELETE` (no `ActionTaken`)
    - `PublicIPChanged=Unknown` → `CONNECTED_IP_UNKNOWN` / `INCONCLUSIVE` / `KEEP` / `KEPT`
- If `MedianMbps == null`:
  - `InternetReachable=false`, `InternetCheckUrl=''`.
  - `detail = SampleErrors` or a default message.
  - `Test-InternetConnectivity` tries:
    1. `https://www.google.com/generate_204`
    2. `https://www.gstatic.com/generate_204`
    3. `https://connectivitycheck.gstatic.com/generate_204`
    4. `https://www.msftconnecttest.com/connecttest.txt`
    5. `https://example.com/`
  - Each URL uses `curl --max-time 6 --connect-timeout 4 -o NUL -w "%{http_code}"`.
  - Success: status 200–399, exit 0, not timed out.
  - If `InternetReachable=true`:
    - `PublicIPChanged=Yes` → `WORKING_TUNNEL_CONNECTIVITY_ONLY` / `ACCEPT` / `KEEP` / `KEPT`
    - `No` → `CONNECTED_ROUTE_UNCONFIRMED` / `REJECT` / `DELETE`
    - `Unknown` → `CONNECTED_IP_UNKNOWN` / `INCONCLUSIVE` / `KEEP` / `KEPT`
  - If `InternetReachable=false`:
    - `PublicIPChanged=No` → `CONNECTED_NO_INTERNET`; Balanced: `REJECT/DELETE`; Conservative: `INCONCLUSIVE/KEEP/KEPT`
    - Otherwise → `CONNECTED_NETWORK_TESTS_INCONCLUSIVE` / `INCONCLUSIVE` / `KEEP` / `KEPT`

> `WORKING_TUNNEL_CONNECTIVITY_ONLY` means the speed endpoint was unavailable but internet access through the tunnel was confirmed. For an existing profile this is `ACCEPT`, but the new-server flow has no equivalent (it uses `CONNECTED_NO_DOWNLOAD`).

### 7.12. Error handling and `finally`

- `catch`:
  - If `Status` is empty → `PROFILE_OR_TEST_ERROR` / `INCONCLUSIVE` / `KEEP`.
  - Append the error to `Error`, maximum 700 characters.
  - `ActionTaken=KEPT`.
  - Red message: "Error while testing this profile; it will be kept as inconclusive".
- `finally`:
  - Only when `testStarted=true` (the profile was dialed or was connected at start).
  - `Disconnect-ExistingVpnProfile` with `WaitSeconds=20`.
  - If disconnection is not confirmed:
    - `PostTestDisconnectFailed=true`
    - `Verdict=INCONCLUSIVE`
    - `PlannedAction=KEEP`
    - `ActionTaken=KEPT`
    - Error: `Profile '<name>' still reports Connected after its test; Windows RAS may be busy, so it cannot be removed.`
    - Maximum 900 characters.
    - Warn that later checks are paused.
  - Profiles rejected by the initial guards (`testStarted=false`) are never disconnected.

### 7.13. Summary and controlled removal

After testing all profiles:

```text
accepted = results where Verdict == "ACCEPT"
rejected = results where Verdict == "REJECT"
uncertain = results where Verdict == "INCONCLUSIVE"

print "Checked <N> SSTP profile(s): <a> accepted (kept) | <r> rejected (marked for removal) | <u> inconclusive (kept)."

if accepted: table ProfileName, Scope, ServerAddress, VPNLatencyMs, VPNLatencyMethod, DownloadMbps, DownloadComplete, VPNPublicIP, CredentialSource, Status
if uncertain: table ProfileName, Scope, ServerAddress, Status, Error
if rejected: table ProfileName, Scope, ServerAddress, Status, Error
```

Then:

- If `rejected.Count == 0` → message: "No existing SSTP profile was rejected; nothing to remove."
- If `ReportOnly`:
  - For each rejected profile: `ActionTaken = "REPORT_ONLY_NOT_REMOVED"`.
  - Message: "REPORT-ONLY mode: no profiles were removed...".
- Otherwise:
  - `confirmRemove = Read-Host("Type YES to permanently remove the <N> rejected profile(s) from Windows; press Enter to keep them all")`.
  - Only when `confirmRemove -ceq 'YES'` (case-sensitive):
    - For each rejected profile: `Remove-ExistingVpnProfile`.
    - Success → `ActionTaken=REMOVED`, `Deleted++`.
    - Failure → `ActionTaken=REMOVE_FAILED`, `DeleteFailed++`, append the error (maximum 1,000 characters).
  - Any other input (including `yes`, `Yes`, `Y`) → `ActionTaken=NOT_REMOVED_BY_USER_CHOICE` and message: "Removal was not confirmed; all rejected profiles were kept."

### 7.14. Safe removal (`Remove-ExistingVpnProfile`)

```text
state = Get-VpnProfileState(name, PreferredScope)

if state == "Connected":
    ok = Disconnect-ExistingVpnProfile(name, PreferredScope, 20s)
    if not ok:
        return { Removed=false, Error="Profile '<name>' (<scope>) could not be confirmed disconnected; it was kept." }
elif state != "Disconnected":
    return { Removed=false, Error="Could not read the state of profile '<name>' in scope '<scope>'; removal was cancelled." }

try:
    if PreferredScope == "AllUser":
        Remove-VpnConnection -Name name -AllUserConnection -Force
    else:
        Remove-VpnConnection -Name name -Force
catch:
    return { Removed=false, Error=message }

sleep SettleSeconds (RasRecoveryDelaySec)
if not Test-ExistingVpnProfileExists(name, PreferredScope):
    return { Removed=true, Error="" }
return { Removed=false, Error="Windows still reports profile '<name>' in scope '<scope>' after removal." }
```

Absolute rules:

- Remove only the scope that was tested; never fall back to the other scope.
- If the state is unreadable, cancel removal.
- If the profile is connected and disconnection is not confirmed, do not remove.
- Remove with `-Force`, but only after confirming the state.
- After removal, verify that the profile no longer exists.

### 7.15. Existing-profile CSV report

- Path: `sstp_existing_profile_check_<yyyyMMdd_HHmmss>.csv` in `$PSScriptRoot`.
- Contains every tested SSTP record plus non-SSTP records with `NOT_SSTP_SKIPPED`.
- Written even when no removal happens or the user does not type `YES`.
- If writing fails: `CsvPath=''` and a warning.
- `CsvPath` is returned from the function.

### 7.16. Final counters

```text
Checked      = sstpProfiles.Count
Accepted     = accepted.Count
Rejected     = rejected.Count
Inconclusive = uncertain.Count
Deleted      = number of successful removals
DeleteFailed = number of failed removals
CsvPath      = CSV path or ''
```

Final message:

```text
Finished existing-profile verification (<Mode>): <Checked> checked | <kept> kept | <Rejected> rejected | <Deleted> removed | <DeleteFailed> removal failure(s) | <Inconclusive> inconclusive.
```

Here `kept = Accepted.Count` (not accepted + uncertain). The exact script text is the contract.

### 7.17. Verification pause message

If `stopFurtherChecks=true`:

```text
Verification was paused after: <stopReason>. Start a fresh run to check the remaining profiles.
```

Remaining profiles are recorded as `SKIPPED_AFTER_RAS_STATE_UNCERTAIN`; no dial or disconnect is performed on them.

### 7.18. `-PruneFirst` behavior

- Runs the same verification phase with `Mode=PruneFirst`.
- After the phase (with or without removal), prints:
  `Prune-first phase finished; continuing with the normal server-test run.`
- Then runs the normal new-server flow.
- `-ReportOnly` affects only the existing-profile phase; the new-server test still runs and can add new profiles.
- If the existing-profile phase stops because RAS state is uncertain, the new-server flow **does not** stop; only the existing-profile phase ends. This must be preserved.

---

## 8. Status and decision matrices

> **Golden rule:** the `Status` strings are exactly the values in these tables. Changing case, adding a prefix, or translating them breaks CSV compatibility and comparative tests.

### 8.1. New-server statuses

| Status | Exact condition | Meaning | Pause later dials? |
|---|---|---|---|
| `TCP_UNREACHABLE` | TCP probe failed and the `TrySstpAfterTcpTimeout` exception does not apply | TCP port did not open; SSTP was not attempted. | No |
| `PROFILE_PORT_MISMATCH` | The stored Windows address cannot be parsed, or host/port does not match the target | The temporary profile stored the wrong endpoint; no dial. | No |
| `RAS_RECOVERY_TIMEOUT_STATE_UNCERTAIN` | `rasdial /disconnect` timed out during 633 recovery | RAS state is unknown; the profile may remain. | **Yes** |
| `VPN_CONNECT_TIMEOUT_RAS_STATE_UNCERTAIN` | `rasdial` itself was killed by the timeout | Final dial result unknown; RAS may be busy. | **Yes** |
| `LOCAL_RAS_ERROR_633_AFTER_RETRY` | RAS 633 remains after the allowed retries | Local Windows error, not necessarily a server rejection. | **Yes** unless `-ContinueAfterLocalRas633` |
| `SSTP_RAS_TIMEOUT_638` | RAS 638 | Timeout in the SSTP/RAS layer; a successful TCP probe is not enough. | No |
| `NETWORK_CONNECT_TIMEOUT` | exit `-2147014836` or timeout text | Network/SSTP timeout, not local 633. | No |
| `VPN_CONNECT_FAILED` | Any other nonzero dial error | Dial failed for another reason. | No |
| `WORKING_TUNNEL_AND_INTERNET` | Connected + successful download + `PublicIPChanged=Yes` | Confirmed server; candidate for installation. | No |
| `CONNECTED_ROUTE_UNCONFIRMED` | Connected + successful download + `PublicIPChanged=No` | Tunnel is up but traffic does not use it. | No |
| `CONNECTED_IP_UNKNOWN` | Connected + successful download + `PublicIPChanged=Unknown` | Download works but the IP comparison is incomplete. | No |
| `CONNECTED_NO_DOWNLOAD` | Connected but `MedianMbps=null` | Tunnel is up but no download sample succeeded. | No |
| `RAS_CLEANUP_INCOMPLETE` | Cleanup could not remove the profile and it is still connected; previous status was not `WORKING_TUNNEL_AND_INTERNET` | A temporary profile remains; the system may be contaminated. | **Yes** |
| `SKIPPED_AFTER_RAS_STATE_UNCERTAIN` | `stopFurtherVpnAttempts=true` before this server's dial | Only TCP was tested; no dial. | — |
| `PROFILE_OR_TEST_ERROR` | Exception during create/test/cleanup (except port mismatch) | Unexpected error; server not confirmed. | No |

**`RAS_CLEANUP_INCOMPLETE` note:** if the previous status was `WORKING_TUNNEL_AND_INTERNET`, the success status is kept and only the cleanup error is appended to `Error`; however, `stopFurtherVpnAttempts` still becomes true. Preserve this exactly.

### 8.2. Existing-profile statuses

| Status | Exact condition | Default verdict | PlannedAction | ActionTaken | Pause checks? |
|---|---|---|---|---|---|
| `DUPLICATE_NAME_ACROSS_PHONEBOOKS` | Same name in User and AllUser | `INCONCLUSIVE` | `KEEP` | `KEPT` | No |
| `SPLIT_TUNNELING_PROFILE_SKIPPED` | `SplitTunneling=true` | `INCONCLUSIVE` | `KEEP` | `KEPT` | No |
| `PROFILE_ADDRESS_UNPARSEABLE` | `ServerAddress` cannot be parsed | `INCONCLUSIVE` | `KEEP` | `KEPT` | No |
| `DISCONNECT_FAILED_STATE_UNCERTAIN` | Profile was connected at start and could not be disconnected | `INCONCLUSIVE` | `KEEP` | `KEPT` | **Yes** |
| `TCP_UNREACHABLE` | TCP failed after N attempts | Balanced: `REJECT`; Conservative: `INCONCLUSIVE` | Balanced: `DELETE`; Conservative: `KEEP` | Conservative: `KEPT` | No |
| `RAS_RECOVERY_TIMEOUT_STATE_UNCERTAIN` | Recovery disconnect timed out | `INCONCLUSIVE` | `KEEP` | `KEPT` | **Yes** |
| `VPN_CONNECT_TIMEOUT_RAS_STATE_UNCERTAIN` | `rasdial` killed by timeout | `INCONCLUSIVE` | `KEEP` | `KEPT` | **Yes** |
| `LOCAL_RAS_ERROR_633_AFTER_RETRY` | 633 remains after retries | `INCONCLUSIVE` | `KEEP` | `KEPT` | **Yes** unless `-ContinueAfterLocalRas633` |
| `CREDENTIALS_REJECTED` | 691/649 on both credential sources | `INCONCLUSIVE` | `KEEP` | `KEPT` | No |
| `VPN_CONNECT_REMOTE_TERMINATED` | 619/628/629/631 after retries | Balanced: `REJECT`; Conservative: `INCONCLUSIVE` | Balanced: `DELETE`; Conservative: `KEEP` | Conservative: `KEPT` | No |
| `VPN_CONNECT_TIMEOUT` | 638 / `-2147014836` / timeout regex | Balanced: `REJECT`; Conservative: `INCONCLUSIVE` | Balanced: `DELETE`; Conservative: `KEEP` | Conservative: `KEPT` | No |
| `VPN_CONNECT_FAILED` | Other dial errors | `INCONCLUSIVE` | `KEEP` | `KEPT` | No |
| `WORKING_TUNNEL_AND_INTERNET` | Connected + download + IP changed | `ACCEPT` | `KEEP` | `KEPT` | No |
| `WORKING_TUNNEL_CONNECTIVITY_ONLY` | Connected + internet through tunnel + IP changed, but no download sample | `ACCEPT` | `KEEP` | `KEPT` | No |
| `CONNECTED_ROUTE_UNCONFIRMED` | Connected + (download or internet) + IP not changed | `REJECT` | `DELETE` | — | No |
| `CONNECTED_IP_UNKNOWN` | Connected + (download or internet) + IP unknown | `INCONCLUSIVE` | `KEEP` | `KEPT` | No |
| `CONNECTED_NO_INTERNET` | Connected + no download + no internet + IP not changed | Balanced: `REJECT`; Conservative: `INCONCLUSIVE` | Balanced: `DELETE`; Conservative: `KEEP` | Conservative: `KEPT` | No |
| `CONNECTED_NETWORK_TESTS_INCONCLUSIVE` | Connected + no download + no internet + IP unknown/changed | `INCONCLUSIVE` | `KEEP` | `KEPT` | No |
| `PROFILE_OR_TEST_ERROR` | Exception | `INCONCLUSIVE` | `KEEP` | `KEPT` | No |
| `SKIPPED_AFTER_RAS_STATE_UNCERTAIN` | Remaining profiles after a pause | `INCONCLUSIVE` | `KEEP` | `KEPT` | — |
| `NOT_SSTP_SKIPPED` | Non-SSTP profile | `SKIPPED` | `KEEP` | `NOT_APPLICABLE` | — |

### 8.3. Verdict → PlannedAction matrix

| Verdict | PlannedAction | Meaning |
|---|---|---|
| `ACCEPT` | `KEEP` | Profile is healthy; leave it untouched. |
| `REJECT` | `DELETE` | Profile is dead or does not route; candidate for removal after `YES`. |
| `INCONCLUSIVE` | `KEEP` | Not enough evidence; always keep. |
| `SKIPPED` | `KEEP` | Not tested (non-SSTP); keep. |

**`INCONCLUSIVE` must never be combined with `DELETE`.** Assert this invariant in tests.

### 8.4. ActionTaken matrix

| ActionTaken | Meaning | When |
|---|---|---|
| `KEPT` | Profile kept | ACCEPT/INCONCLUSIVE or Conservative. |
| `REMOVED` | Successful removal | Only after `YES` and confirmed removal. |
| `REMOVE_FAILED` | Removal attempt failed | After `YES` but removal/verification failed. |
| `REPORT_ONLY_NOT_REMOVED` | Reported without removal | `-ReportOnly` with rejected profiles. |
| `NOT_REMOVED_BY_USER_CHOICE` | User did not confirm | Input other than `YES`. |
| `NOT_APPLICABLE` | Not applicable | Non-SSTP profile. |

### 8.5. Evidence-based decision matrix (existing-profile phase)

| TCP | Dial | Download | Internet | IP changed | Status | Balanced | Conservative |
|---|---|---|---|---|---|---|---|
| fail | — | — | — | — | `TCP_UNREACHABLE` | REJECT | INCONCLUSIVE |
| ok | fail 633 | — | — | — | `LOCAL_RAS_ERROR_633_AFTER_RETRY` | INCONCLUSIVE | INCONCLUSIVE |
| ok | fail 691/649 | — | — | — | `CREDENTIALS_REJECTED` | INCONCLUSIVE | INCONCLUSIVE |
| ok | fail transient | — | — | — | `VPN_CONNECT_REMOTE_TERMINATED` | REJECT | INCONCLUSIVE |
| ok | fail timeout | — | — | — | `VPN_CONNECT_TIMEOUT` | REJECT | INCONCLUSIVE |
| ok | fail other | — | — | — | `VPN_CONNECT_FAILED` | INCONCLUSIVE | INCONCLUSIVE |
| ok | ok | yes | — | Yes | `WORKING_TUNNEL_AND_INTERNET` | ACCEPT | ACCEPT |
| ok | ok | yes | — | No | `CONNECTED_ROUTE_UNCONFIRMED` | REJECT | REJECT |
| ok | ok | yes | — | Unknown | `CONNECTED_IP_UNKNOWN` | INCONCLUSIVE | INCONCLUSIVE |
| ok | ok | no | yes | Yes | `WORKING_TUNNEL_CONNECTIVITY_ONLY` | ACCEPT | ACCEPT |
| ok | ok | no | yes | No | `CONNECTED_ROUTE_UNCONFIRMED` | REJECT | REJECT |
| ok | ok | no | yes | Unknown | `CONNECTED_IP_UNKNOWN` | INCONCLUSIVE | INCONCLUSIVE |
| ok | ok | no | no | No | `CONNECTED_NO_INTERNET` | REJECT | INCONCLUSIVE |
| ok | ok | no | no | Yes/Unknown | `CONNECTED_NETWORK_TESTS_INCONCLUSIVE` | INCONCLUSIVE | INCONCLUSIVE |

> `CONNECTED_NETWORK_TESTS_INCONCLUSIVE` occurs when `PublicIPChanged` is not `No` (that is, `Yes` or `Unknown`). If the IP changed but no internet probe succeeded, the result is still inconclusive, not ACCEPT.

### 8.6. New statuses without an existing-profile equivalent

| New status | Closest existing equivalent | Difference |
|---|---|---|
| `CONNECTED_NO_DOWNLOAD` | `WORKING_TUNNEL_CONNECTIVITY_ONLY` or `CONNECTED_NETWORK_TESTS_INCONCLUSIVE` | The new flow has no separate connectivity probe. |
| `SSTP_RAS_TIMEOUT_638` | `VPN_CONNECT_TIMEOUT` | The existing flow merges 638 into timeout. |
| `NETWORK_CONNECT_TIMEOUT` | `VPN_CONNECT_TIMEOUT` | The existing flow treats both the same. |
| `RAS_CLEANUP_INCOMPLETE` | `DISCONNECT_FAILED_STATE_UNCERTAIN` / `PostTestDisconnectFailed` | Different cleanup mechanism. |
| `PROFILE_PORT_MISMATCH` | `PROFILE_ADDRESS_UNPARSEABLE` | The existing flow uses an already-created profile and does not re-verify the address. |

### 8.7. Testable invariants

1. `Status` is never empty in a final record (except very early errors caught and filled).
2. `Verdict=ACCEPT` ⇒ `PlannedAction=KEEP` and `ActionTaken=KEPT`.
3. `Verdict=REJECT` ⇒ `PlannedAction=DELETE` and `ActionTaken` is one of `—`, `REMOVED`, `REMOVE_FAILED`, `REPORT_ONLY_NOT_REMOVED`, `NOT_REMOVED_BY_USER_CHOICE`.
4. `Verdict=INCONCLUSIVE` ⇒ `PlannedAction=KEEP` and `ActionTaken=KEPT` (even after a failed removal attempt, the verdict returns to INCONCLUSIVE).
5. `PostTestDisconnectFailed=true` ⇒ `Verdict=INCONCLUSIVE` and `PlannedAction=KEEP`.
6. `NOT_SSTP_SKIPPED` ⇒ `Verdict=SKIPPED` and `ActionTaken=NOT_APPLICABLE`.
7. In the new flow, `WORKING_TUNNEL_AND_INTERNET` requires `PublicIPChanged=Yes` and `DownloadMbps != null`.
8. In the existing flow, `WORKING_TUNNEL_AND_INTERNET` requires a successful download; `WORKING_TUNNEL_CONNECTIVITY_ONLY` requires successful internet and no download.

---

## 9. Ranking, profile creation, and CSV schemas

### 9.1. `MeasuredLatencyMs`

After all tests, `Add-SelectionScores` computes for each record:

```text
if VPNLatencyMs != null and VPNLatencyMs > 0:
    MeasuredLatencyMs = VPNLatencyMs
elif TcpConnectMs != null and TcpConnectMs > 0:
    MeasuredLatencyMs = TcpConnectMs
else:
    MeasuredLatencyMs = null
```

The tunnel latency has priority; if unavailable, the pre-VPN TCP connect time is the fallback. The source-published PING is **not** used here (it is only used for the shortlist).

### 9.2. Speed normalization

```text
speedValues = [DownloadMbps for records where DownloadMbps != null]
maxSpeed = max(speedValues) or null

for each record:
    if DownloadMbps != null and maxSpeed != null and maxSpeed > 0:
        SpeedScore = round(100.0 * DownloadMbps / maxSpeed, 2)
        clamp(SpeedScore, 0, 100)
    else:
        SpeedScore = 0.0
```

- Fastest → 100.
- Slower → linear ratio.
- Missing → 0.
- Clamp protects against abnormal data.

### 9.3. Latency normalization

```text
latencyValues = [MeasuredLatencyMs for records where MeasuredLatencyMs != null]
minLatency = min(latencyValues) or null
maxLatency = max(latencyValues) or null

for each record:
    if MeasuredLatencyMs == null:
        LatencyScore = 0.0
    elif latencyValues.Count <= 1 or maxLatency <= minLatency:
        LatencyScore = 100.0
    else:
        LatencyScore = round(100.0 * (maxLatency - MeasuredLatencyMs) / (maxLatency - minLatency), 2)
        clamp(LatencyScore, 0, 100)
```

- Lowest latency → 100.
- Highest latency → 0.
- If only one server was measured, or all values are equal → every measured server gets 100 (latency cannot discriminate).
- Missing latency → 0.

### 9.4. `SelectionScore`

```text
switch RankMode:
    "Speed":    SelectionScore = SpeedScore
    "Latency":  SelectionScore = LatencyScore
    "Balanced": SelectionScore = round(0.7 * SpeedScore + 0.3 * LatencyScore, 2)
```

- `Balanced` is the default: 70% speed + 30% latency.
- `Speed`: speed only.
- `Latency`: latency only.
- `SelectionScore` may have two decimal places.

### 9.5. Results CSV sort

```text
sort records by DownloadMbps descending, stable
records with DownloadMbps == null go last
```

- This sort is **independent of `RankMode`**.
- Even in `Latency` mode, the CSV is sorted by download speed.
- `-Stable` preserves the test order for equal speeds.
- `SpeedScore`, `LatencyScore`, and `SelectionScore` are included so the user can re-rank offline.

### 9.6. Console table sort

**Confirmed working:**

```text
filter Status == "WORKING_TUNNEL_AND_INTERNET"
sort by SelectionScore descending, then DownloadMbps descending, stable
```

**Connected but unverified:**

```text
filter Status in ["CONNECTED_ROUTE_UNCONFIRMED", "CONNECTED_IP_UNKNOWN"]
sort by SelectionScore descending, then DownloadMbps descending, stable
```

**Other tables:**

- `CONNECTED_NO_DOWNLOAD`: no extra sort (test order).
- `LOCAL_RAS_ERROR_633_AFTER_RETRY`: no extra sort.
- `NETWORK_CONNECT_TIMEOUT` + `SSTP_RAS_TIMEOUT_638`: no extra sort.

### 9.7. Top N selection for installation

```text
topServers = []
seenEndpoints = {}

for srv in confirmed (already sorted by SelectionScore):
    if topServers.Count >= AddBestVpnCount: break
    hostKey = lower(trimTrailingDot(srv.Host))
    portKey = int(srv.Port) or 443
    if hostKey == "": continue
    endpointKey = hostKey + ":" + portKey
    if seenEndpoints contains endpointKey: continue
    seenEndpoints[endpointKey] = true
    topServers.add(srv)
```

- Only `WORKING_TUNNEL_AND_INTERNET` records are eligible.
- Internal dedupe is by `host:port`.
- If none are available → warning: "No confirmed working server was found. Nothing was added...".
- `AddBestVpnCount=0` disables the entire section.

### 9.8. New profile naming

```text
baseProfileName = target.Host.TrimEnd('.')
if baseProfileName == "":
    baseProfileName = regex replace target.ServerAddress:
        '^\[|\](?::\d+)?$|:\d+$' -> ''

newProfileName = if target.Port == 443
                 then baseProfileName
                 else baseProfileName + "-p" + target.Port

if newProfileName == "": skip

newProfileName = regex replace '[\\/:*?"<>|\[\]]' -> '_'
```

Examples:

| Host | Port | Name |
|---|---|---|
| `vpn.example.com` | 443 | `vpn.example.com` |
| `vpn.example.com` | 1556 | `vpn.example.com-p1556` |
| `2001:db8::1` | 443 | `2001_db8__1` (after sanitize) |
| `2001:db8::1` | 1556 | `2001_db8__1-p1556` |

### 9.9. Duplicate detection during installation

For each `topServer`:

1. `existingProfiles = Get-VpnConnection` (per-user only).
2. For each existing profile:
   - If `existing.Name -ieq newProfileName` → duplicate.
   - Or if `Parse-SstpServerAddress(existing.ServerAddress)` succeeds and host (trim trailing dot, case-insensitive) and port equal the target → duplicate.
3. If duplicate:
   - Message: `Skipping duplicate profile '<existing>' (a Windows VPN entry already uses <address>).`
   - Record the name in `skippedExisting`.
   - Make no change to the existing profile.
4. If not duplicate:
   - `Add-VpnConnection -Name <name> -ServerAddress <address> -TunnelType SSTP -AuthenticationMethod MSChapv2 -EncryptionLevel Optional -RememberCredential`
   - `Set-VpnConnection -Name <name> -RememberCredential $true -Force`
   - `Get-VpnConnection -Name <name>` to verify.
   - Parse `ServerAddress`; host/port must match.
   - Check `TunnelType -eq 'Sstp'`.
   - Check `RememberCredential`; if false → warning (not abort).
   - Store credentials with `RasSetCredentials`.
   - On success → `addedNames`.
   - On error → warning and continue with the next server.

> **Important:** only per-user profiles are checked for duplicates at this stage; AllUser profiles are not checked. Preserve this behavior.

### 9.10. Credential storage (`Set-VpnConnectionCredentials`)

The `VpnClient` module cannot set a username/password directly. The script P/Invokes `rasapi32.dll`:

```c
RasSetCredentials(
    NULL,                 // default per-user phonebook
    entryName,            // profile name
    &credentials,         // RASCREDENTIALS
    FALSE                 // do not clear
);
```

`RASCREDENTIALS`:

| Field | Value |
|---|---|
| `size` | `Marshal.SizeOf` |
| `options` | `UserName \| Password \| Domain` |
| `userName` | `-Username` |
| `password` | `-Password` |
| `domain` | `''` |

- On `ERROR_ACCESS_DENIED` (5) → `UnauthorizedAccessException`.
- Other errors → `RasGetErrorString` and message `RAS <code>`.
- If credential storage fails, the profile is **not** removed; only a warning: "Profile was added, but credentials could not be stored".
- A port MAY use direct P/Invoke or `rasdial` with credentials, but the behavior "profile is added even if the credential store fails" MUST be preserved.

### 9.11. New-server results CSV (43 columns)

**Default name:** `sstp_test_results_<yyyyMMdd_HHmmss>.csv` next to the script.
**Encoding:** `utf8` (PowerShell 7).
**Sorted:** `DownloadMbps` descending, null last.

| # | Column | Type | Description |
|---:|---|---|---|
| 1 | `Country` | string | Source country. |
| 2 | `Source` | string | Row source. |
| 3 | `Server` | string | Canonical address. |
| 4 | `Host` | string | Host. |
| 5 | `Port` | int | Port. |
| 6 | `PingMs` | number? | Source PING. |
| 7 | `VPNServerAddress` | string | Same canonical address. |
| 8 | `WindowsStoredServerAddress` | string | Address reported by Windows. |
| 9 | `ProfilePortVerified` | bool? | Host/port verification. |
| 10 | `TcpReachable` | bool | TCP result. |
| 11 | `TcpConnectMs` | number? | TCP connect time. |
| 12 | `TcpProbeError` | string | TCP error. |
| 13 | `VPNLatencyMs` | number? | Median tunnel latency. |
| 14 | `VPNLatencyMethod` | string | `ICMP`/`TCP`/`none`. |
| 15 | `VPNLatencySamples` | int | Successful samples. |
| 16 | `VPNLatencyMin` | number? | Minimum. |
| 17 | `VPNLatencyMax` | number? | Maximum. |
| 18 | `VPNLatencyError` | string | Latency error. |
| 19 | `VPNConnected` | bool | Connection succeeded. |
| 20 | `VPNConnectSeconds` | number? | Total dial time. |
| 21 | `BaselineIPv4` | string | IP before VPN. |
| 22 | `VPNIPv4` | string | IP inside tunnel. |
| 23 | `IPv4Changed` | `Yes`/`No`/`Unknown` | IPv4 change. |
| 24 | `BaselineIPv6` | string | IP before. |
| 25 | `VPNIPv6` | string | IP inside tunnel. |
| 26 | `IPv6Changed` | `Yes`/`No`/`Unknown` | IPv6 change. |
| 27 | `RouteVerificationFamily` | string | `IPv4`/`IPv6`/empty. |
| 28 | `VPNPublicIP` | string | IP used for verification. |
| 29 | `PublicIPChanged` | `Yes`/`No`/`Unknown` | Route result. |
| 30 | `DownloadMbps` | number? | Median speed. |
| 31 | `DownloadMB` | number? | Average MB per sample. |
| 32 | `DownloadSeconds` | number? | Average seconds. |
| 33 | `DownloadComplete` | bool | All samples complete. |
| 34 | `DownloadSamples` | int | Successful samples. |
| 35 | `DownloadMinMbps` | number? | Minimum. |
| 36 | `DownloadMaxMbps` | number? | Maximum. |
| 37 | `DownloadError` | string | Download error. |
| 38 | `Status` | string | Final status. |
| 39 | `Error` | string | Error detail. |
| 40 | `MeasuredLatencyMs` | number? | Latency used for scoring. |
| 41 | `SpeedScore` | number | 0–100. |
| 42 | `LatencyScore` | number | 0–100. |
| 43 | `SelectionScore` | number | Final score. |

**Why this order?** The initial record places `MeasuredLatencyMs` before `VPNConnected` and the score fields before `Status`. `Add-SelectionScores` re-adds those four properties with `Add-Member -Force`, and PowerShell moves them to the end of the property order. The actual PowerShell 7.6.9 output is the table above. Serialize this exact order for parity.

### 9.12. Existing-profile CSV (45 columns)

**Default name:** `sstp_existing_profile_check_<yyyyMMdd_HHmmss>.csv`.

| # | Column | Type | Description |
|---:|---|---|---|
| 1 | `ProfileName` | string | Profile name. |
| 2 | `Scope` | `User`/`AllUser` | Phonebook. |
| 3 | `ServerAddress` | string | Stored address. |
| 4 | `Host` | string | Parsed host. |
| 5 | `Port` | int? | Port. |
| 6 | `WasConnectedAtStart` | bool | Initial connection state. |
| 7 | `TcpReachable` | bool | TCP result. |
| 8 | `TcpConnectMs` | number? | TCP time. |
| 9 | `TcpProbeError` | string | TCP error. |
| 10 | `TcpAttempts` | int | Attempt count. |
| 11 | `CredentialSource` | string | Credential source. |
| 12 | `DialAttempts` | int | Dial count. |
| 13 | `VPNConnected` | bool | Connected. |
| 14 | `VPNConnectSeconds` | number? | Total time. |
| 15 | `BaselineIPv4` | string | IP before. |
| 16 | `VPNIPv4` | string | IP after. |
| 17 | `IPv4Changed` | string | Change. |
| 18 | `BaselineIPv6` | string | IP before. |
| 19 | `VPNIPv6` | string | IP after. |
| 20 | `IPv6Changed` | string | Change. |
| 21 | `RouteVerificationFamily` | string | Verification family. |
| 22 | `VPNPublicIP` | string | Verification IP. |
| 23 | `PublicIPChanged` | string | Result. |
| 24 | `VPNLatencyMs` | number? | Latency. |
| 25 | `VPNLatencyMethod` | string | Method. |
| 26 | `VPNLatencySamples` | int | Samples. |
| 27 | `VPNLatencyMin` | number? | Minimum. |
| 28 | `VPNLatencyMax` | number? | Maximum. |
| 29 | `VPNLatencyError` | string | Error. |
| 30 | `DownloadMbps` | number? | Speed. |
| 31 | `DownloadMB` | number? | MB. |
| 32 | `DownloadSeconds` | number? | Seconds. |
| 33 | `DownloadComplete` | bool | Complete. |
| 34 | `DownloadSamples` | int | Successful samples. |
| 35 | `DownloadMinMbps` | number? | Minimum. |
| 36 | `DownloadMaxMbps` | number? | Maximum. |
| 37 | `DownloadError` | string | Error. |
| 38 | `InternetReachable` | bool | Connectivity result. |
| 39 | `InternetCheckUrl` | string | Successful URL. |
| 40 | `Status` | string | Status. |
| 41 | `Verdict` | string | Verdict. |
| 42 | `PlannedAction` | string | KEEP/DELETE. |
| 43 | `ActionTaken` | string | Action. |
| 44 | `PostTestDisconnectFailed` | bool | Post-test disconnect failed. |
| 45 | `Error` | string | Detail. |

### 9.13. Snapshot CSV (8 columns)

**Name:** `sstp_server_list_<yyyyMMdd_HHmmss>.csv`.

| # | Column |
|---:|---|
| 1 | `Country` |
| 2 | `Source` |
| 3 | `Server` |
| 4 | `Host` |
| 5 | `Port` |
| 6 | `PingMs` |
| 7 | `UptimeText` |
| 8 | `UptimeMinutes` |

> The snapshot is saved after the port filter, sort, and Priority, but before `MaxServers`. It is a valid `-ServerListCsv` input.

### 9.14. Inventory CSV (7 columns)

**Name:** `sstp_existing_profiles_<yyyyMMdd_HHmmss>.csv`.

| # | Column |
|---:|---|
| 1 | `Name` |
| 2 | `Scope` |
| 3 | `TunnelType` |
| 4 | `ServerAddress` |
| 5 | `ConnectionStatus` |
| 6 | `SplitTunneling` |
| 7 | `NameCollision` |

### 9.15. CSV serialization rules

- `Export-Csv -NoTypeInformation -Encoding utf8`.
- `$null` → empty field.
- `bool` → `True` / `False` (capitalized).
- Decimal numbers use a dot (invariant culture) for Excel and comparative tests.
- Fields containing commas, quotes, or newlines are quoted with `"` and internal quotes escaped as `""` (standard CSV).
- Lines end with CRLF.
- A port using a CSV library MUST guarantee the same quoting behavior.

### 9.16. Key end-of-run messages

New-server flow:

```text
Ranking mode: <mode> (source PING only shortlisted; final order uses measured VPN latency + measured download speed).

================ CONFIRMED WORKING SERVERS ================
...
Finished: <N> server TCP checks | <T> TCP ports reachable | <V> VPN connections established | <C> confirmed working.
Full CSV report (sorted by DownloadMbps descending; includes VPNLatencyMs and SelectionScore): <path>
Speed and latency are observed during this test, not guaranteed long-term VPN values.
```

Existing-profile phase:

```text
================ EXISTING PROFILE VERIFICATION SUMMARY ================
Checked <N> SSTP profile(s): <A> accepted (kept) | <R> rejected (marked for removal) | <U> inconclusive (kept).
...
Full verification CSV report: <path>
Finished existing-profile verification (<Mode>): <N> checked | <A> kept | <R> rejected | <D> removed | <F> removal failure(s) | <U> inconclusive.
```

### 9.17. Example CSV rows

New-server example (fictional, to show data types):

```csv
"Germany","VPN Gate","vpn123.opengw.net:1556","vpn123.opengw.net","1556","42","vpn123.opengw.net:1556","vpn123.opengw.net:1556","True","True","85.3","","","","0","","","","True","18.42","203.0.113.10","198.51.100.25","Yes","","","Unknown","IPv4","198.51.100.25","Yes","12.34","10.2","0.66","False","1","12.34","12.34","","WORKING_TUNNEL_AND_INTERNET","","12.34","100","87.5","96.25"
```

Existing-profile example:

```csv
"vpn123.opengw.net-p1556","User","vpn123.opengw.net:1556","vpn123.opengw.net","1556","False","True","85.3","","1","Stored Windows credentials","1","True","18.42","203.0.113.10","198.51.100.25","Yes","","","Unknown","IPv4","198.51.100.25","Yes","12.34","ICMP","1","12.34","12.34","","12.34","10.2","0.66","False","1","12.34","12.34","","False","","WORKING_TUNNEL_AND_INTERNET","ACCEPT","KEEP","KEPT","False",""
```

> The values are illustrative only and do not indicate that a server is valid.

---

## 10. Safety, errors, and non-functional requirements

### 10.1. Non-negotiable safety rules

| ID | Rule | Reason |
|---|---|---|
| `SAFE-01` | Delete an existing profile only after showing a summary and receiving exactly `YES`. | Prevent accidental deletion. |
| `SAFE-02` | `-ReportOnly` never deletes. | Safe first run. |
| `SAFE-03` | Every `INCONCLUSIVE` status is kept. | A local error must not cause removal of a healthy profile. |
| `SAFE-04` | Split tunneling, duplicate names, unparseable addresses, rejected credentials, and local RAS errors are always kept. | These conditions are unsafe to judge as server failure. |
| `SAFE-05` | Delete only in the scope that was tested. | A same-named profile in the other phonebook may point to a different server. |
| `SAFE-06` | Remove a temporary profile only after confirming disconnection. | Removing a connected profile can leave RAS in an uncertain state. |
| `SAFE-07` | Only one VPN connection at a time. | Public-IP and RAS results depend on it. |
| `SAFE-08` | Never overwrite an existing profile. | Preserve user settings. |
| `SAFE-09` | Add a new profile only for `WORKING_TUNNEL_AND_INTERNET` servers. | Never install an unconfirmed server. |
| `SAFE-10` | After an uncertain RAS state, do not dial further servers. | Prevent contaminated results. |

These rules are part of the observable contract. A port MUST enforce them even if its internal structure differs.

### 10.2. Destructive operations and preconditions

| Operation | Precondition | Confirmation | Scope |
|---|---|---|---|
| `Remove-VpnConnection` (temporary profile) | Profile is disconnected | Automatic (temporary profile) | Per-user |
| `Remove-VpnConnection` (existing profile) | Verdict `REJECT` and state `Disconnected` | Exact `YES` | The tested scope |
| `Add-VpnConnection` (new profile) | Status `WORKING_TUNNEL_AND_INTERNET` | None (automatic) | Per-user |
| `Set-VpnConnectionCredentials` | New profile was created | None | Per-user phonebook |
| `rasdial /disconnect` | The tested profile | None | Not applicable |
| `Set-VpnConnection -RememberCredential` | New profile | None | Per-user |

### 10.3. RAS 633 diagnostics

When RAS 633 remains after the allowed retries, the script runs `Show-Ras633Diagnostics`:

1. **Services:** `Get-CimInstance Win32_Service` filtered to `RasMan` and `SstpSvc`; display Name, State, StartMode, ExitCode.
2. **WAN Miniports:** `Get-PnpDevice -Class Net` filtered by `WAN Miniport|SSTP`; display Status, FriendlyName, Problem, InstanceId.
3. **Recent events:** the last 15 minutes from `Microsoft-Windows-RasClient/Operational` (at most 8 events); if empty, `Application` with ProviderName `RasClient`.
4. **Warning message:** "Do not change registry values or reinstall WAN Miniports yet; use the diagnostic output first."

**Port requirement:** provide at least equivalent diagnostics, optionally in a separate module. The critical rule is that `LOCAL_RAS_ERROR_633_AFTER_RETRY` MUST never become `REJECT`.

### 10.4. Error taxonomy

| Category | Example | Behavior |
|---|---|---|
| Configuration error | Forbidden parameter combination | `throw` before any change. |
| Environment error | Not Administrator, no curl, no VpnClient | `throw` at startup. |
| Source error | Blocked site, invalid HTML, empty CSV | Fallback; ultimately `throw` with guidance. |
| TCP error | Refused, timeout, DNS | `TCP_UNREACHABLE`, or continue with the switch. |
| Profile error | Wrong address stored | `PROFILE_PORT_MISMATCH`. |
| Dial error | 633/638/691/628/timeout | Corresponding status. |
| Route error | IP unchanged or unknown | Corresponding status. |
| Download error | HTTP error, timeout, zero bytes | `CONNECTED_NO_DOWNLOAD` (new flow) or connectivity probe (existing flow). |
| Cleanup error | Profile remained connected | `RAS_CLEANUP_INCOMPLETE` and stop. |
| Unexpected error | Exception | `PROFILE_OR_TEST_ERROR` and keep. |

### 10.5. Timeout table

| Operation | Value | Configurable? |
|---|---|---|
| TCP probe | `TcpTimeoutMs` (default 1800 ms) | Yes |
| `rasdial` dial | `ConnectTimeoutSec` (default 150 s) | Yes |
| `rasdial /disconnect` | 12 seconds (fixed) | No |
| Wait for profile disconnect | 20 seconds (fixed) | No |
| Latency ICMP, per sample | `min(LatencyTimeoutMs, 1500)` | Yes |
| Latency TCP fallback | `LatencyTimeoutMs` | Yes |
| Download, per sample | `SpeedTimeoutSec` (default 12 s) | Yes |
| Download process | `SpeedTimeoutSec + 4` | Indirectly |
| Public IP (ipify) | curl max-time 7, connect 4, process 9 | No |
| Public IP (robust) | curl max-time 6, connect 3, process 8 | No |
| Connectivity probe | curl max-time 6, connect 4, process 8 | No |
| Source page download | 30 seconds | No |
| `Invoke-WebRequest` | 30 seconds | No |
| Settle pause after connect | 2 seconds | No |
| Baseline settle pause | 2 seconds | No |

### 10.6. Behavior on network errors

- Supplementary source failure → warning; continue with the primary source.
- Primary source failure → try Jina, then clipboard/HTML/CSV, then the extra source, then the final fallback.
- Public IP failure → empty string; route result `Unknown`.
- Latency failure → `LatencyMs=null`, `Method=none`; the server can still be confirmed by a successful download.
- Download failure → if the median is null, status `CONNECTED_NO_DOWNLOAD` (new flow) or run the internet probe (existing flow).
- Connectivity probe failure → `InternetReachable=false`; status `CONNECTED_NO_INTERNET` or `CONNECTED_NETWORK_TESTS_INCONCLUSIVE`.

### 10.7. Logging and observability

The script uses `Write-Host`, `Write-Warning`, `Write-Progress`, and colors. A port MUST provide at least the same information:

- Progress `[index/total]` with the server address.
- Per-server result: TCP, connection, latency, speed, status.
- Summary tables with the documented columns.
- Paths of all CSV files.
- Reason for any stop.
- Duplicate, credential, and cleanup warnings.

**Requirement:** never write a password to a CSV or log. A message such as "password set" is sufficient.

### 10.8. Non-functional requirements

#### Compatibility

- Windows 10/11 (x64/ARM64 with PowerShell 7).
- PowerShell 7+ for the reference version; a port MAY be native but MUST expose the same capabilities.
- Administrator access.
- `VpnClient` module, `rasdial.exe`, `curl.exe`.

#### Performance

- Servers are tested sequentially; total time is approximately `N × (TCP + dial + latency + download + cleanup)`.
- `MaxServers` controls the run time.
- `SpeedSamples=1` is the default for the shortest run.
- `ConnectTimeoutSec=150` accommodates slow servers; lowering it speeds up runs but increases false negatives.
- No extra preflight is performed on all candidates; only the shortlist is tested.

#### Reliability

- Every external operation MUST have a timeout.
- Every process MUST be disposed or killed in `finally`.
- Every temporary profile MUST be removed in `finally`.
- A single server error MUST NOT stop the whole run, except for RAS stop conditions.
- The CSV MUST still be written on partial failure when records exist.

#### Security and privacy

- Credentials are stored only in memory and in the per-user phonebook; they never appear in CSV output.
- `rasdial` receives the password on the command line; this is an inherent Windows risk. A port SHOULD use a safer API when possible, but MUST preserve behavior.
- Online source content is **untrusted**; parsers MUST accept only valid host/port values and MUST NOT execute commands from content.
- Profile names are sanitized to prevent dangerous characters.
- Use `ProcessStartInfo.ArgumentList` (or an equivalent argument array) to reduce argument injection.
- Use TLS for HTTPS sources and validate certificates when possible.

#### Maintainability

- Parsers, scorer, RAS wrapper, and reporter SHOULD be separate modules.
- Statuses SHOULD be defined as a central enum or constants.
- Message text SHOULD be collected in one resource or constants file.
- Unit tests for parsers and the scorer MUST run without a VPN.
- Integration tests SHOULD mock `rasdial`/`curl` for error paths.

#### Localization

- Console messages in the reference version are English; keep them English for behavioral parity.
- User documentation MAY be localized.
- CSV column names MUST NEVER be translated.

### 10.9. "Does this error reject the server?" decision table

| Error | New server | Existing profile (Balanced) | Existing profile (Conservative) |
|---|---|---|---|
| TCP refused | Reject (`TCP_UNREACHABLE`) | Reject | Keep |
| TCP timeout | Reject, unless the switch applies | Reject | Keep |
| RAS 633 | Keep/stop | Keep | Keep |
| RAS 638 | Reject (`SSTP_RAS_TIMEOUT_638`) | Reject | Keep |
| RAS 691/649 | Reject (`VPN_CONNECT_FAILED`) | Keep | Keep |
| RAS 619/628/629/631 | Reject (`VPN_CONNECT_FAILED`) | Reject | Keep |
| Network timeout | Reject | Reject | Keep |
| Connected + IP unchanged | Reject | Reject | Reject |
| Connected + IP unknown | Keep | Keep | Keep |
| Connected + no download | Reject (`CONNECTED_NO_DOWNLOAD`) | ACCEPT if internet works; otherwise depends on IP | Same |
| Cleanup error | Keep + stop | Keep + stop | Keep + stop |

### 10.10. Stop and recovery scenarios

| Scenario | Behavior | Recovery |
|---|---|---|
| Repeated RAS 633 | Stop further dials; TCP-only for the rest | Fresh run after checking services |
| `rasdial` timeout | Stop; state uncertain | Fresh run; ensure the VPN is disconnected |
| Recovery disconnect timeout | Stop | Fresh run |
| Temporary profile remained connected | Stop; `RAS_CLEANUP_INCOMPLETE` | Disconnect manually and run again |
| Existing profile could not be disconnected | Stop checks; `PostTestDisconnectFailed` | Disconnect manually and run again |
| Empty source list | V/C/H/Q menu | Choose clipboard/HTML or enable the VPN |
| Empty or invalid CSV | Error | Fix the file or obtain a new one |

### 10.11. Suggested exit codes for a port

The PowerShell version does not set custom exit codes; `throw` produces a nonzero exit. A port MAY use:

| Code | Meaning |
|---|---|
| `0` | Success (including ListOnly and Verify without a fatal error) |
| `1` | Configuration or validation error |
| `2` | Environment error (OS/PowerShell/Admin/tool) |
| `3` | Could not acquire a server list |
| `4` | Unexpected runtime error |
| `5` | Cancelled by the user |

> **Parity note:** if exact parity with the reference script is required, do not change exit codes; preserve only 0/nonzero.

---

## Appendix A. Definitive status catalog

### A.1. New-server statuses

```text
WORKING_TUNNEL_AND_INTERNET
CONNECTED_ROUTE_UNCONFIRMED
CONNECTED_IP_UNKNOWN
CONNECTED_NO_DOWNLOAD
TCP_UNREACHABLE
PROFILE_PORT_MISMATCH
RAS_CLEANUP_INCOMPLETE
LOCAL_RAS_ERROR_633_AFTER_RETRY
SSTP_RAS_TIMEOUT_638
NETWORK_CONNECT_TIMEOUT
VPN_CONNECT_FAILED
VPN_CONNECT_TIMEOUT_RAS_STATE_UNCERTAIN
RAS_RECOVERY_TIMEOUT_STATE_UNCERTAIN
SKIPPED_AFTER_RAS_STATE_UNCERTAIN
PROFILE_OR_TEST_ERROR
```

### A.2. Existing-profile statuses

```text
WORKING_TUNNEL_AND_INTERNET
WORKING_TUNNEL_CONNECTIVITY_ONLY
CONNECTED_ROUTE_UNCONFIRMED
CONNECTED_NO_INTERNET
CONNECTED_NETWORK_TESTS_INCONCLUSIVE
CONNECTED_IP_UNKNOWN
CREDENTIALS_REJECTED
VPN_CONNECT_REMOTE_TERMINATED
VPN_CONNECT_TIMEOUT
VPN_CONNECT_FAILED
DUPLICATE_NAME_ACROSS_PHONEBOOKS
SPLIT_TUNNELING_PROFILE_SKIPPED
PROFILE_ADDRESS_UNPARSEABLE
DISCONNECT_FAILED_STATE_UNCERTAIN
NOT_SSTP_SKIPPED
LOCAL_RAS_ERROR_633_AFTER_RETRY
VPN_CONNECT_TIMEOUT_RAS_STATE_UNCERTAIN
RAS_RECOVERY_TIMEOUT_STATE_UNCERTAIN
SKIPPED_AFTER_RAS_STATE_UNCERTAIN
PROFILE_OR_TEST_ERROR
```

### A.3. Verdicts

```text
ACCEPT
REJECT
INCONCLUSIVE
SKIPPED
```

### A.4. PlannedAction values

```text
KEEP
DELETE
```

### A.5. ActionTaken values

```text
KEPT
REMOVED
REMOVE_FAILED
REPORT_ONLY_NOT_REMOVED
NOT_REMOVED_BY_USER_CHOICE
NOT_APPLICABLE
```

---

## Appendix B. Reference regular expressions

```text
Host FQDN:
^(?i)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$

Server in the general table:
(?i)(?<server>\[[0-9a-fA-F:.]+\](?::\d{1,5})?|(?:(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}|(?:\d{1,3}\.){3}\d{1,3})(?::\d{1,5})?)

PING:
(?i)(?<!\d)(?<ms>\d{1,5}(?:\.\d{1,2})?)\s*ms(?![\p{L}\d])

Uptime:
(?<n>\d+(?:\.\d+)?)\s*(?<unit>months?|days?|hours?|hrs?|minutes?|mins?|d|h|m)\b

VPN Gate endpoint:
(?i)SSTP\s+Hostname\s*:?\s*(?<server>[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?(?::\d{1,5})?)

RAS error:
(?i)Remote Access error\s+(\d{3})

curl write-out:
(\d{3})\|([\d.]+)\|([\d.]+)\|([\d.]+)

CSV/plain text row start:
^\s*\|?\s*\d{1,3}(?:\.|\s*\||\s+)

Section header in a plain list:
^=+\s*(?<country>.+?)\s*=+$
```

These patterns are the reference behavior. A port MAY use a real HTML parser, but the extracted host/port/country/ping/uptime values MUST match these patterns on the same input.

---

## Appendix C. File and output map

| Output | Name pattern | When |
|---|---|---|
| Server snapshot | `sstp_server_list_<yyyyMMdd_HHmmss>.csv` | Normal flow, after sort/Priority, before `MaxServers` |
| New-server results | `sstp_test_results_<yyyyMMdd_HHmmss>.csv` | End of the new-server flow |
| Existing-profile check | `sstp_existing_profile_check_<yyyyMMdd_HHmmss>.csv` | Verify/Prune phase with SSTP |
| Profile inventory | `sstp_existing_profiles_<yyyyMMdd_HHmmss>.csv` | `-ListExisting` |
| Custom results | `-OutputCsv <path>` | New-server flow |

All default outputs are written next to the script (or executable). Parent directories are created when needed.

---

## Appendix D. Glossary

| Term | Meaning |
|---|---|
| **AllUser phonebook** | The system-wide Windows VPN phonebook; profiles are visible to all users and require elevation to change. |
| **Balanced mode** | Default existing-profile policy: reject dead or non-routing profiles, keep ambiguous ones. |
| **Baseline IP** | Public IP address observed before dialing the VPN. |
| **Conservative mode** | Existing-profile policy that keeps every profile unless the evidence is conclusive; only clear route failures are rejected. |
| **Dial** | The act of bringing up a VPN connection with `rasdial`. |
| **Endpoint** | A `host:port` pair identifying an SSTP server. |
| **Existing profile** | A VPN profile that already exists in the Windows phonebook and is tested in place. |
| **Golden comparison** | Comparing a port's CSV output with the reference output for the same input and parameters. |
| **INCONCLUSIVE** | Not enough evidence to accept or reject; always kept. |
| **Per-user phonebook** | The current user's Windows VPN profile store; no elevation is required to modify it. |
| **Public IP change** | Whether the observed public IP inside the tunnel differs from the baseline. |
| **RAS** | Windows Remote Access Service, the subsystem behind `rasdial` and the `VpnClient` module. |
| **RAS 633** | A local Windows error indicating that no remote-access port could be allocated; not proof of server rejection. |
| **RAS 638** | A timeout reported by the RAS/SSTP layer. |
| **RAS 691/649** | Authentication rejection (bad credentials or account state). |
| **RAS 619/628/629/631** | Remote termination or link-failure family treated as a transient remote failure. |
| **Shortlist** | The sorted and filtered set of servers that will actually be tested. |
| **Snapshot** | The `sstp_server_list_*.csv` file saved before testing; it can be fed back through `-ServerListCsv`. |
| **SSTP** | Secure Socket Tunneling Protocol, the VPN tunnel type used by this tool. |
| **Temporary profile** | A per-user VPN profile created only for testing and removed afterward. |
| **Verdict** | The existing-profile decision: `ACCEPT`, `REJECT`, `INCONCLUSIVE`, or `SKIPPED`. |

---

*End of specification.*

