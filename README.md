# Test-FreeSstpServers v16.1.1

> **Authorship.** I designed and tested this program; AI wrote the code under my direction. The behavior contract is documented in [the specification](docs/SPECIFICATION.md), and the [porting guide](docs/PORTING.md) plus the [AI porting prompt](docs/PORTING-PROMPT.md) explain how to reimplement it in other programming languages.

A safety-first PowerShell tool for Windows that discovers free SSTP VPN servers, proves that they actually carry traffic, measures real tunnel latency and download speed, and installs the best working endpoints as Windows VPN profiles. It can also audit and clean up existing SSTP profiles without guessing.

Version 16.1.1 changes only the new-profile naming rule; all other v16.1 behavior is unchanged.

---

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Modes](#modes)
- [How it works](#how-it-works)
- [Safety model](#safety-model)
- [Output files](#output-files)
- [Common commands](#common-commands)
- [Important parameters](#important-parameters)
- [Limitations and privacy](#limitations-and-privacy)
- [Repository layout](#repository-layout)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- Fetches free SSTP endpoints from the ipspeed.info table, a VPN Gate mirror, a local HTML capture, the clipboard, a saved CSV snapshot, or a plain host list.
- Parses FQDN, IPv4, and bracketed IPv6 endpoints with optional non-443 ports.
- Merges duplicate endpoints, keeping the entry with the lower published PING.
- Filters by port (`All`, `443`, `Non443`) and shortlists by the source PING, then by uptime.
- Creates a temporary per-user SSTP profile for each candidate and verifies that Windows stored the expected host and port before dialing.
- Dials with `rasdial`, verifies that the public IP actually changed, measures ICMP/TCP latency through the tunnel, and measures download speed through the tunnel.
- Ranks results with normalized speed and latency scores (`Speed`, `Balanced`, or `Latency`).
- Adds the top N confirmed servers to Windows as SSTP profiles named `<country> - <server host>` (non-443 endpoints keep a `-p<port>` suffix) and stores the username/password in the RAS phonebook.
- Inventories existing per-user and AllUser VPN profiles, including duplicate-name and split-tunneling detection.
- Tests existing SSTP profiles with the same route, latency, and speed measurements, then produces an `ACCEPT` / `REJECT` / `INCONCLUSIVE` verdict.
- Removes rejected existing profiles only after a summary table and an explicit uppercase `YES`; `-ReportOnly` never removes anything.
- Writes machine-readable CSV reports for every phase.

## Requirements

| Requirement | Details |
|---|---|
| Operating system | Windows 10 or Windows 11 |
| Shell | PowerShell 7 or newer (`pwsh.exe`) |
| Privileges | Administrator session (the script changes VPN profiles and RAS state) |
| Windows component | `VpnClient` PowerShell module (inbox) |
| Windows tools | `rasdial.exe` and `curl.exe` |
| Network | Access to the configured server-list sources and public-IP services |

`-Help` is the only mode that works without Administrator rights.

## Quick start

```powershell
# 1. Open PowerShell 7 as Administrator and go to the repository folder.
cd C:\path\to\Test-FreeSstpServers

# 2. Read the full built-in help.
.\Test-FreeSstpServers_v16_1.ps1 -Help

# 3. Inventory existing VPN profiles. Nothing is dialed or changed.
.\Test-FreeSstpServers_v16_1.ps1 -ListExisting

# 4. Safest first maintenance run: test existing SSTP profiles, delete nothing.
.\Test-FreeSstpServers_v16_1.ps1 -VerifyExisting -ReportOnly

# 5. Normal test: use the server list copied to the clipboard.
#    Non-443 ports only, at most 30 servers, install the best 3.
.\Test-FreeSstpServers_v16_1.ps1 -UseClipboard -PortMode Non443 -MaxServers 30 -AddBestVpnCount 3
```

On a fresh machine, run the normal test without `-UseClipboard` first; the script fetches the primary list automatically:

```powershell
.\Test-FreeSstpServers_v16_1.ps1 -PortMode Non443 -MaxServers 10
```

The repository also includes double-click launchers that request elevation automatically:

| Launcher | What it does |
|---|---|
| `Run-Normal.cmd` | Clipboard list, `Non443`, 30 servers, add top 3 |
| `Run-ListExisting.cmd` | Inventory only; no dial, no change |
| `Run-ReportOnly.cmd` | Existing-profile test with `-ReportOnly` |
| `Run-ApplyRemovals.cmd` | Existing-profile test with controlled removal after `YES` |

## Modes

| Mode | Key parameters | What happens | Output |
|---|---|---|---|
| Help | `-Help` | Prints help and exits before environment checks | Console |
| Inventory | `-ListExisting` | Lists per-user and AllUser profiles; no dial | `sstp_existing_profiles_<ts>.csv` |
| Verify dry-run | `-VerifyExisting -ReportOnly` | Tests existing SSTP profiles; never deletes | `sstp_existing_profile_check_<ts>.csv` |
| Verify apply | `-VerifyExisting` | Tests, shows summary, asks for `YES`, removes rejected | CSV + removals |
| Prune + normal | `-PruneFirst` | Existing-profile phase, then the normal new-server run | Two CSVs |
| Prune dry-run | `-PruneFirst -ReportOnly` | Existing-profile phase without deletion, then normal run | Two CSVs |
| List only | `-ListOnly` | Fetch, filter, sort, save snapshot, exit | `sstp_server_list_<ts>.csv` |
| Snapshot test | `-ServerListCsv <path>` | Test a saved snapshot; no web fetch | Results CSV |
| Clipboard | `-UseClipboard` | Clipboard, then primary, then extra, then final fallback | Results CSV |
| Extra only | `-ExtraSourceOnly` | VPN Gate source only | Results CSV |
| Final only | `-FinalFallbackOnly` | Plain host list only | Results CSV |
| Normal | no special mode | Primary + supplementary sources | Results CSV + new profiles |

Mode precedence is fixed:

1. `-Help`
2. Parameter-combination validation
3. Environment checks
4. `-ListExisting`
5. `-VerifyExisting` or `-PruneFirst`
6. Normal new-server run

## How it works

```text
Sources (HTTP / HTML / clipboard / CSV / plain list)
        |
        v
Parse and normalize  ->  merge by host:port  ->  port filter
        |
        v
Sort by source PING (ascending, unknown last), then uptime (descending)
        |
        v
PriorityServer  ->  save snapshot  ->  MaxServers
        |
        v
For each server (strictly one VPN at a time):
  TCP probe -> temporary SSTP profile -> verify stored host/port
  -> rasdial -> public-IP comparison -> tunnel latency
  -> tunnel download -> classify -> remove temporary profile
        |
        v
Score -> results CSV -> console ranking -> add top N profiles
```

Every candidate is tested serially. Parallel VPN dials would make public-IP comparisons meaningless and could corrupt shared Windows RAS state.

## Safety model

The tool changes Windows VPN configuration, so the following rules are non-negotiable:

- **Explicit consent for deletion.** Existing profiles are removed only after the summary table and an exact uppercase `YES`. Pressing Enter, `yes`, `Yes`, or `Y` keeps every profile.
- **Report-only never deletes.** `-ReportOnly` is the recommended first maintenance run.
- **Uncertain means keep.** Any `INCONCLUSIVE` verdict maps to `KEEP`. Local RAS errors, credential rejections, split tunneling, duplicate names, and unparseable addresses are never grounds for deletion.
- **Scope fidelity.** A profile is removed only from the phonebook scope that was tested (`User` or `AllUser`). The tool never falls back to the other scope.
- **Disconnect before delete.** A connected profile is never removed. The tool first disconnects it and confirms the state.
- **Temporary profiles are cleaned up in `finally`.** If cleanup cannot confirm disconnection, later VPN dials are paused to avoid contaminating results.
- **Only confirmed servers are installed.** New profiles are added only for `WORKING_TUNNEL_AND_INTERNET` results.
- **No silent success.** After adding a profile, the tool verifies the stored address, port, tunnel type, and `RememberCredential` flag.

## Output files

All files are written next to the script unless `-OutputCsv` is supplied. Timestamps use `yyyyMMdd_HHmmss`.

| File | Columns | When |
|---|---:|---|
| `sstp_server_list_<ts>.csv` | 8 | Normal run, after port filter/sort/Priority, before `MaxServers` |
| `sstp_test_results_<ts>.csv` | 43 | End of the new-server run |
| `sstp_existing_profile_check_<ts>.csv` | 45 | End of the existing-profile phase |
| `sstp_existing_profiles_<ts>.csv` | 7 | `-ListExisting` |

The exact column names and order are part of the compatibility contract. See [docs/SPECIFICATION.md](docs/SPECIFICATION.md#9-ranking-profile-creation-and-csv-schemas).

New Windows profiles are named `<country> - <server host>`; non-443 endpoints keep the `-p<port>` suffix. If the source provides no country, the prefix is `Unknown`.

> The CSV files can contain public IP addresses observed during testing. Review them before sharing.

## Common commands

```powershell
# Fetch and save a snapshot without testing anything.
.\Test-FreeSstpServers_v16_1.ps1 -UseClipboard -ListOnly

# Re-test a saved snapshot without downloading the list again.
.\Test-FreeSstpServers_v16_1.ps1 -ServerListCsv .\sstp_server_list_20261105_065304.csv -MaxServers 5 -AddBestVpnCount 0

# Test only VPN Gate endpoints.
.\Test-FreeSstpServers_v16_1.ps1 -ExtraSourceOnly -PortMode Non443 -MaxServers 30

# Test only the plain Delta-Kronecker host list.
.\Test-FreeSstpServers_v16_1.ps1 -FinalFallbackOnly -PortMode All -MaxServers 30

# Longer run: three download samples, speed-first ranking, add five profiles.
.\Test-FreeSstpServers_v16_1.ps1 -UseClipboard -PortMode Non443 -MaxServers 10 -RankMode Speed -SpeedSamples 3 -AddBestVpnCount 5

# Try SSTP even when the TCP probe times out (but not when it is refused).
.\Test-FreeSstpServers_v16_1.ps1 -UseClipboard -TrySstpAfterTcpTimeout -MaxServers 10

# Existing-profile maintenance with the conservative removal policy.
.\Test-FreeSstpServers_v16_1.ps1 -VerifyExisting -ExistingRemovalMode Conservative
```

## Important parameters

| Parameter | Default | Purpose |
|---|---|---|
| `-Url` | `https://ipspeed.info/free-sstp.php` | Primary list page |
| `-ExtraSourceUrl` | VPN Gate mirror | One or more supplementary sources |
| `-UseClipboard` | off | Read the list from the clipboard |
| `-ServerListCsv` | empty | Reuse a saved snapshot; no web fetch |
| `-PortMode` / `-PortFilter` | `All` | `All`, `443`, or `Non443` |
| `-MaxServers` | `0` (all) | Test only the first N candidates after sorting |
| `-PriorityServer` | empty | Move one `host[:port]` to the front |
| `-ConnectTimeoutSec` | `150` | Maximum time for one SSTP dial |
| `-SpeedSamples` | `1` | Download samples per server (1–5) |
| `-SpeedDownloadBytes` | `10000000` | Bytes requested per sample |
| `-RankMode` | `Balanced` | `Speed`, `Balanced` (70/30), or `Latency` |
| `-AddBestVpnCount` | `3` | Number of confirmed servers to install; `0` disables |
| `-VerifyExisting` | off | Standalone existing-profile verification |
| `-PruneFirst` | off | Verify existing profiles, then run normally |
| `-ReportOnly` | off | Never delete during the existing-profile phase |
| `-ListExisting` | off | Inventory only |
| `-ExistingRemovalMode` | `Balanced` | `Balanced` or `Conservative` |
| `-Help` | off | Show help and exit |

All 41 parameters, their ranges, defaults, and validation rules are documented in [docs/SPECIFICATION.md](docs/SPECIFICATION.md#5-command-line-interface).

## Limitations and privacy

- **Windows only.** The tool depends on the Windows `VpnClient` module, `rasdial.exe`, and the RAS phonebook.
- **Free servers are untrusted.** A working tunnel does not make the operator trustworthy. Do not send sensitive traffic through a free VPN.
- **Measurements are point-in-time.** Speed and latency are observed during this run, not guaranteed long-term values.
- **One VPN at a time.** Do not run two instances of the tool concurrently.
- **Default credentials.** `-Username` and `-Password` default to `vpn` / `vpn`, the public test credentials used by VPN Gate. Change them if your provider requires different credentials. Credentials are stored in the per-user RAS phonebook for profiles the tool creates; they are never written to CSV files.
- **Network endpoints contacted.** The tool may contact the configured server-list sources, `r.jina.ai` (readable-text mirror), `api.ipify.org`, `checkip.amazonaws.com`, `icanhazip.com`, `ifconfig.me`, `ident.me`, `api64.ipify.org`, `speed.cloudflare.com`, Google connectivity endpoints, Microsoft connectivity endpoints, and `example.com`. See [SECURITY.md](SECURITY.md).
- **No warranty.** Use at your own risk and only with authorization on the machine you are testing.

## Repository layout

```text
.
├── Test-FreeSstpServers_v16_1.ps1   Reference implementation
├── Run-Normal.cmd                   Elevated normal-run launcher
├── Run-ListExisting.cmd             Elevated inventory launcher
├── Run-ReportOnly.cmd               Elevated report-only launcher
├── Run-ApplyRemovals.cmd            Elevated removal launcher
├── docs/
│   ├── SPECIFICATION.md             Normative reimplementation specification
│   ├── PORTING.md                   Porting guide and API mapping
│   ├── PORTING-PROMPT.md            Ready-to-use AI prompt for ports
│   └── TESTING.md                   Test strategy and acceptance criteria
├── CONTRIBUTING.md
├── SECURITY.md
├── CHANGELOG.md
├── LICENSE
└── README.md
```

## Documentation

- [Specification](docs/SPECIFICATION.md) — behavior contract, status matrices, CSV schemas, safety rules.
- [Porting guide](docs/PORTING.md) — C#, Go, Rust, and Python options; PowerShell-to-Win32 mapping.
- [AI porting prompt](docs/PORTING-PROMPT.md) — copy-paste brief and phase plan for generating a port in another language.
- [Testing guide](docs/TESTING.md) — unit, integration, fault-injection, and golden-CSV tests.
- [Security policy](SECURITY.md) — reporting and operational risks.
- [Changelog](CHANGELOG.md) — release history.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first. Changes that alter status strings, CSV columns, safety rules, or default behavior need an explicit compatibility discussion. Please do not include real credentials, public IP addresses, or personal profile names in issues or test fixtures.

## License

MIT. See [LICENSE](LICENSE).

---

**Disclaimer:** This project is not affiliated with ipspeed.info, VPN Gate, Cloudflare, or any VPN provider. It is an automation and measurement tool, not a VPN service. Respect the terms of service of every source you query and every network you use.
