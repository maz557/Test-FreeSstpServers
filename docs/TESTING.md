# Testing and Acceptance Guide

> **Purpose.** This document defines how to verify that `Test-FreeSstpServers v16.1` and any port behave correctly. The reference script ships without an automated test suite; the checks below are the acceptance plan. The normative behavior is in [SPECIFICATION.md](SPECIFICATION.md).

---

## 1. Test strategy

```text
                 ┌─────────────────────────┐
                 │  E2E on real Windows    │  few, slow, critical
                 └───────────▲─────────────┘
              ┌──────────────┴──────────────┐
              │  Integration with mocks     │  medium
              └──────────────▲──────────────┘
        ┌────────────────────┴────────────────────┐
        │              Unit tests                 │  many, fast
        │  parser / scorer / validator / state    │
        └─────────────────────────────────────────┘
```

- **Unit tests** need no VPN and no Administrator rights.
- **Integration tests** use mocked `rasdial`/`curl` or a disposable Windows VM.
- **End-to-end tests** run on a real Windows machine with Administrator rights and a working network.

Never run destructive tests on a production workstation. Use a VM snapshot for scenarios that change RAS state.

---

## 2. Unit tests

| Module | Cases |
|---|---|
| `AddressParser` | FQDN, IPv4, bracketed and bare IPv6, port 443/non-443, invalid port, empty host, trailing dot, `host:0`, `host:65536`. |
| `HostValidator` | Valid/invalid FQDN, IPv4 with an octet above 255, IPv6, length above 253, forbidden characters. |
| `PingParser` | `36 ms`, `36.5 ms`, `-`, `Ping: 9 ms`, `999 ms`, `ms` with no number, arbitrary text. |
| `UptimeParser` | `2 days`, `1 month 3 days`, `5h`, `30 mins`, `1.5 hours`, combined units, missing unit. |
| `ServerListParser` | HTML table, copied text, VPN Gate HTML/text, plain list, incomplete row, duplicates. |
| `CsvLoader` | Full columns, empty `Source`, textual `PingMs`, port mismatch, invalid port, empty row, empty file. |
| `Merger` | Lower PING wins, null PING, filling `Country`/`Uptime`, ordering. |
| `Scorer` | Fixed vectors, single server, all equal, null values, clamping. |
| `Validator` | `V1`–`V10`, message order. |
| `CsvWriter` | Column order, null, bool, quoting, CRLF, invariant culture. |
| `StatusMachine` | All transitions in Section 8 of the specification. |

### 2.1. Scorer test vector

Three records:

| Record | DownloadMbps | MeasuredLatencyMs |
|---|---:|---:|
| A | 100 | 10 |
| B | 50 | 20 |
| C | null | null |

With `maxSpeed=100`, `minLatency=10`, `maxLatency=20`:

| Record | SpeedScore | LatencyScore | Balanced | Speed | Latency |
|---|---:|---:|---:|---:|---:|
| A | 100 | 100 | 100 | 100 | 100 |
| B | 50 | 0 | 35 | 50 | 0 |
| C | 0 | 0 | 0 | 0 | 0 |

Single-server case: if only A is measured, `LatencyScore=100`, not 0.

---

## 3. Parser fixtures

Keep fixtures in `tests/fixtures/`:

- `ipspeed_table.html` — a real table with `# | LOCATION | HOSTNAME | UPTIME | PING`.
- `ipspeed_copied.txt` — text copied from a browser.
- `vpngate.html` — rows containing `SSTP Hostname`.
- `vpngate_copied.txt`.
- `sstp_hosts.txt` — a plain list with comments and section headers.
- `snapshot_v16.csv` — a valid v16 snapshot.
- `snapshot_old.csv` — an old snapshot without `Source`/`PingMs`.
- `snapshot_invalid_port.csv`.

**Pass criterion:** record count, host/port, `Country`, `PingMs`, `UptimeText`, and `UptimeMinutes` all match the expected values.

---

## 4. State-machine tests with mocks

Put dependencies behind interfaces:

```csharp
interface ITcpProbe { TcpResult Probe(string host, int port, int timeoutMs); }
interface IRasDialer {
    DialResult Dial(string profile, string? user, string? pass, int timeoutSec);
    DialResult Disconnect(string profile);
}
interface IVpnProfileStore { /* ... */ }
interface IPublicIpProvider { string Get(string family); }
interface IDownloadProbe { DownloadResult Measure(/* ... */); }
interface IClock { /* ... */ }
```

Scenarios:

| Scenario | Mock behavior | Expected result |
|---|---|---|
| TCP refused | `Reachable=false`, `Error="refused"` | `TCP_UNREACHABLE` |
| TCP timeout with switch | `Error="TCP timeout"` | Dial is attempted |
| TCP timeout without switch | `Error="TCP timeout"` | `TCP_UNREACHABLE` |
| Profile port mismatch | Store returns a different port | `PROFILE_PORT_MISMATCH`; no dial |
| Dial 633 once, then success | Sequence | Retry, then connect |
| Dial 633 repeatedly | Always 633 | `LOCAL_RAS_ERROR_633_AFTER_RETRY` and stop |
| Recovery disconnect timeout | `TimedOut` | `RAS_RECOVERY_TIMEOUT_STATE_UNCERTAIN` |
| Dial timeout | `TimedOut=true` | `VPN_CONNECT_TIMEOUT_RAS_STATE_UNCERTAIN` |
| RAS 638 | Exit 638 | `SSTP_RAS_TIMEOUT_638` |
| Network timeout | Exit `-2147014836` | `NETWORK_CONNECT_TIMEOUT` |
| Other failure | Exit 1 | `VPN_CONNECT_FAILED` |
| Connected + IP changed + download | Yes | `WORKING_TUNNEL_AND_INTERNET` |
| Connected + IP unchanged + download | No | `CONNECTED_ROUTE_UNCONFIRMED` |
| Connected + IP unknown + download | Unknown | `CONNECTED_IP_UNKNOWN` |
| Connected + no download | Null | `CONNECTED_NO_DOWNLOAD` |
| Cleanup still connected | `Removed=false`, `StillConnected=true` | `RAS_CLEANUP_INCOMPLETE` and stop |
| Existing duplicate name | Collision | `DUPLICATE_NAME_ACROSS_PHONEBOOKS` |
| Existing split tunneling | True | `SPLIT_TUNNELING_PROFILE_SKIPPED` |
| Existing 691 twice | Sequence | `CREDENTIALS_REJECTED` |
| Existing 628 twice | Sequence | Fallback, then `VPN_CONNECT_REMOTE_TERMINATED` |
| Existing no internet + same IP | Probe false | Balanced rejects / Conservative keeps |
| Existing post-test disconnect failure | Disconnect false | `PostTestDisconnectFailed=true`, `INCONCLUSIVE` |
| Existing duplicate name across phonebooks | Same name in both | Kept and skipped |

---

## 5. Integration tests on real Windows

Run these on a VM or a disposable test machine with Administrator access.

| # | Scenario | Expected result |
|---|---|---|
| I1 | `-Help` without Administrator | Help is shown; exit code 0 |
| I2 | `-ListExisting` | Table and CSV only; no dial and no change |
| I3 | `-VerifyExisting -ReportOnly` | No deletion; rejected profiles show `REPORT_ONLY_NOT_REMOVED` |
| I4 | `-VerifyExisting` + Enter | No deletion; `NOT_REMOVED_BY_USER_CHOICE` |
| I5 | `-VerifyExisting` + `YES` | Rejected profiles removed; `REMOVED` |
| I6 | `-VerifyExisting` + `yes` | No deletion (case-sensitive) |
| I7 | `-PruneFirst -ReportOnly` | Existing phase without deletion, then the new-server test |
| I8 | `-ListOnly -MaxServers 1` | Snapshot contains all servers, not only one |
| I9 | `-ServerListCsv` | No web request; snapshot used as-is |
| I10 | `-ExtraSourceOnly` | VPN Gate only |
| I11 | `-FinalFallbackOnly` | Plain list only |
| I12 | `-UseClipboard` with an empty clipboard | Fallback to the primary source |
| I13 | `-PortMode 443` | Port 443 only |
| I14 | `-PortMode Non443` | Non-443 only |
| I15 | `-PriorityServer` valid | That server is first |
| I16 | `-PriorityServer` invalid | Warning; PING order |
| I17 | `-MaxServers 3` | Exactly 3 servers tested |
| I18 | `-AddBestVpnCount 0` | No profile added |
| I19 | Existing profile with a duplicate name | `DUPLICATE_NAME_ACROSS_PHONEBOOKS` |
| I20 | Existing split-tunneling profile | `SPLIT_TUNNELING_PROFILE_SKIPPED` |
| I21 | Non-SSTP profile | `NOT_SSTP_SKIPPED` |
| I22 | Profile with an invalid address | `PROFILE_ADDRESS_UNPARSEABLE` |
| I23 | Simulated RAS 633 | `LOCAL_RAS_ERROR_633_AFTER_RETRY` and stop |
| I24 | Temporary profile left behind | `RAS_CLEANUP_INCOMPLETE` and stop |
| I25 | Slow server with a partial download | `WORKING_TUNNEL_AND_INTERNET` with `DownloadComplete=False` |

> **Important:** I25 encodes the v16.1 rule. A partial download that produced real bytes is accepted. Do not require a complete 10 MB transfer.

Use VM snapshots for I23 and I24; they change real RAS state.

---

## 6. Golden CSV comparison

For each reference run and each port run:

1. Use the same input snapshot and the same parameters.
2. Compare both CSVs with a script:
   - headers are byte-for-byte identical;
   - row counts are equal;
   - key columns (`Server`, `Status`, `Verdict`, `PlannedAction`, `ActionTaken`) are equal;
   - numeric speed/latency values match within 0.01.
3. Allowed differences:
   - measured times and speeds (network-dependent);
   - `WindowsStoredServerAddress` when Windows versions differ;
   - exact curl/RAS error text.

**A header mismatch is a hard failure.**

### 6.1. Required headers

| File | Columns |
|---|---|
| New-server results | 43 |
| Existing-profile check | 45 |
| Server snapshot | 8 |
| Profile inventory | 7 |

The exact column names and order are listed in Section 9 of [SPECIFICATION.md](SPECIFICATION.md). Compare them literally, including case.

### 6.2. Serialization checks

- `$null` is an empty field.
- Booleans are `True`/`False`.
- Decimal separators are dots.
- Lines end with CRLF.
- Fields containing commas, quotes, or newlines are quoted with `"` and internal quotes doubled.

---

## 7. Fault injection

| Injection | Method | Expected result |
|---|---|---|
| HTTP 403/503 | Mock server | Fallback to the next source |
| Cloudflare challenge | HTML containing `Just a moment` | Warning and fallback |
| Empty CSV | Empty file | Clear error |
| CSV missing a column | Remove `Host` | Error or row rejection matching the reference |
| curl timeout | Mock curl | `DownloadError`; corresponding status |
| curl zero bytes | Mock | Failed sample |
| DNS failure | Nonexistent host | `TCP_UNREACHABLE` |
| RAS 633 | Mock rasdial | Local status |
| Process kill | Mock timeout | Uncertain-state status |
| Empty clipboard | Mock | Fallback |

---

## 8. Acceptance criteria

- [ ] All parameters and defaults from the specification are implemented.
- [ ] All `V1`–`V10` validations run with the same messages.
- [ ] `-Help` works without Administrator rights.
- [ ] `-ListExisting` makes no changes.
- [ ] `-VerifyExisting -ReportOnly` never deletes.
- [ ] Deletion happens only after an exact uppercase `YES`.
- [ ] Every documented status can be produced.
- [ ] All CSVs have the exact columns and column order.
- [ ] `DownloadComplete=False` does not prevent acceptance.
- [ ] `INCONCLUSIVE` always maps to `KEEP`.
- [ ] `PostTestDisconnectFailed` stops checks and keeps the profile.
- [ ] RAS 633, 638, and network timeouts are distinguished correctly.
- [ ] Only one VPN is tested at a time.
- [ ] Duplicate profiles are not created.
- [ ] Credentials never appear in CSV output or logs.
- [ ] Unit and integration tests pass.
- [ ] CSV headers match the reference.
- [ ] Installation, usage, and troubleshooting documentation is complete.

---

## 9. Behavioral parity checklist

Use this checklist when reviewing a port. Mark the port column only after a test or code review confirms the item.

| # | Feature | Reference | Port | Verified |
|---:|---|---|---|---|
| 1 | Parameter names | Yes | | |
| 2 | Defaults | Yes | | |
| 3 | `ValidateRange` bounds | Yes | | |
| 4 | `PortFilter` alias | Yes | | |
| 5 | `V1`–`V10` | Yes | | |
| 6 | Mode precedence | Yes | | |
| 7 | Help without Administrator | Yes | | |
| 8 | Environment checks | Yes | | |
| 9 | General table parser | Yes | | |
| 10 | VPN Gate parser | Yes | | |
| 11 | Plain-list parser | Yes | | |
| 12 | CSV loader | Yes | | |
| 13 | Merge and dedupe | Yes | | |
| 14 | PING/uptime sort | Yes | | |
| 15 | `PriorityServer` | Yes | | |
| 16 | ListOnly before Max | Yes | | |
| 17 | TCP probe | Yes | | |
| 18 | Temporary profile creation | Yes | | |
| 19 | Profile port verification | Yes | | |
| 20 | RAS 633 retry | Yes | | |
| 21 | New-server dial classification | Yes | | |
| 22 | New-server route check | Yes | | |
| 23 | ICMP/TCP latency | Yes | | |
| 24 | Partial download acceptance | Yes | | |
| 25 | Temporary profile cleanup | Yes | | |
| 26 | New-server statuses | Yes | | |
| 27 | Existing-profile inventory | Yes | | |
| 28 | Existing-profile guards | Yes | | |
| 29 | Existing-profile dial and fallback | Yes | | |
| 30 | Existing-profile route check | Yes | | |
| 31 | Connectivity probe | Yes | | |
| 32 | Existing-profile verdicts | Yes | | |
| 33 | Safe removal | Yes | | |
| 34 | `-ReportOnly` | Yes | | |
| 35 | Exact `YES` | Yes | | |
| 36 | Stop conditions | Yes | | |
| 37 | Scorer | Yes | | |
| 38 | CSV sort | Yes | | |
| 39 | Top N and dedupe | Yes | | |
| 40 | Profile naming | Yes | | |
| 41 | Credential storage | Yes | | |
| 42 | New CSV header (43) | Yes | | |
| 43 | Existing CSV header (45) | Yes | | |
| 44 | Snapshot header (8) | Yes | | |
| 45 | Key messages | Yes | | |

---

## 10. Manual smoke test (reference script)

Run these in order on a test machine. Stop at the first failure.

```powershell
# 1. Help must work in a normal shell (no elevation required).
.\Test-FreeSstpServers_v16_1.ps1 -Help

# 2. Inventory only: no dial, no changes.
.\Test-FreeSstpServers_v16_1.ps1 -ListExisting

# 3. Verify without deletion.
.\Test-FreeSstpServers_v16_1.ps1 -VerifyExisting -ReportOnly

# 4. Small new-server run with no profile installation.
.\Test-FreeSstpServers_v16_1.ps1 -MaxServers 1 -AddBestVpnCount 0 -SpeedSamples 1

# 5. Verify the generated CSV headers (43 and 45 columns).
Import-Csv .\sstp_test_results_*.csv | Select-Object -First 1 |
    ForEach-Object { $_.PSObject.Properties.Name.Count }

Import-Csv .\sstp_existing_profile_check_*.csv | Select-Object -First 1 |
    ForEach-Object { $_.PSObject.Properties.Name.Count }
```

For step 5, compare the headers with the specification, not only the count. A correct count with wrong names is still a failure.

> **Never** run `-VerifyExisting` with `YES` on a machine whose profiles you are not prepared to lose. Test removal only on a VM or with profiles you created for testing.
