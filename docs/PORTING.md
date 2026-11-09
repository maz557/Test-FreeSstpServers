# Porting Guide

> **Purpose.** This guide describes how to reimplement `Test-FreeSstpServers v16.1.1` in another language without breaking behavioral parity. The normative contract is [SPECIFICATION.md](SPECIFICATION.md); this document covers language choices, architecture, Windows API mapping, migration phases, and risks.

> **AI-assisted porting.** If you want an AI coding assistant to generate the port, use [PORTING-PROMPT.md](PORTING-PROMPT.md). It contains a copy-paste brief, phase prompts, and a definition-of-done checklist.

---

## 1. What "porting" means here

A port is successful when the observable behavior matches the reference script:

- the same command-line parameters, aliases, defaults, and validation errors;
- the same status, verdict, planned-action, and action-taken strings;
- the same CSV file names, columns, column order, and serialization;
- the same safety rules, including exact-`YES` deletion and `-ReportOnly` behavior;
- the same ranking and top-N selection.

Internal structure, concurrency for non-VPN work, and UI styling are free to change. The reference implementation is a single 4,251-line PowerShell script; a port SHOULD split it into modules.

### 1.1. Reference environment

| Item | Value |
|---|---|
| OS | Windows 10/11 |
| Shell | PowerShell 7.6.9 |
| Privileges | Administrator |
| Required tools | `rasdial.exe`, `curl.exe`, `VpnClient` module |
| Reference script | `Test-FreeSstpServers_v16_1.ps1` |

---

## 2. Recommended target: C#/.NET 8

C# offers the best balance between behavioral parity and maintainability:

- Native access to Win32/RAS APIs and P/Invoke.
- Mature `System.Net.Http`, `System.Net.Sockets`, and `System.Diagnostics.Process`.
- `System.Text.Json` and `CsvHelper` for configuration and CSV.
- Ability to host a PowerShell runspace for `VpnClient` cmdlets.
- Single-file executable for simple distribution.

### 2.1. Suggested solution layout

```text
SstpTool.sln
├── SstpTool.Cli                 // argument parsing, mode selection, console UI
├── SstpTool.Core
│   ├── Sources                  // HTTP, HTML, clipboard, CSV, plain list
│   ├── Parsing                  // server-list parser, address parser
│   ├── Testing                  // TCP probe, RAS dial, route, latency, download
│   ├── Existing                 // inventory, tester, removal guard
│   ├── Ranking                  // scorer
│   └── Reporting                // CSV writers, console tables
├── SstpTool.Windows             // P/Invoke, VpnClient host, RAS wrappers
└── SstpTool.Tests               // unit and integration tests
```

### 2.2. C# implementation notes

1. **CLI:** `System.CommandLine` is suitable, but parameter names and the `PortFilter` alias MUST be preserved. Model switches as `bool` with a default of `false`.
2. **Validation:** keep the exact `V1`–`V10` order and messages. Use a dedicated `ConfigurationException`.
3. **VpnClient:** two options:
   - Host `Microsoft.PowerShell.SDK` and run cmdlets in a runspace; this is closest to the reference.
   - P/Invoke directly to `rasapi32.dll` (`RasSetEntryProperties`, `RasDial`, `RasHangUp`, `RasGetEntryProperties`); more control, more complexity.
   - For a first port, the runspace option carries the lowest behavioral risk.
4. **RAS credentials:** P/Invoke `RasSetCredentials` with a `RASCREDENTIALS` structure (Unicode, `Pack=4`).
5. **Process timeouts:** `ProcessStartInfo.ArgumentList` plus `WaitForExitAsync` and `CancellationTokenSource`; on timeout call `Kill(entireProcessTree: true)`.
6. **CSV:** `CsvHelper` with `CultureInfo.InvariantCulture`, `NewLine = "\r\n"`, and standard quoting. Define column order explicitly with a `ClassMap`; do not rely on property order.
7. **HTML:** `AngleSharp` or `HtmlAgilityPack` are fine, but the extracted values MUST match the reference regexes. Recommended: keep the reference regexes for parity, then optionally add a DOM parser as a fallback.
8. **Clipboard:** `System.Windows.Forms.Clipboard` on an STA thread, with a fallback to PowerShell's clipboard cmdlets.
9. **Console:** `Spectre.Console` can improve tables, but the columns and key text MUST stay the same.
10. **Packaging:** `dotnet publish -r win-x64 -p:PublishSingleFile=true --self-contained false` (requires the .NET runtime), or self-contained for end users.

---

## 3. Alternative targets

### 3.1. Go

**Advantages:** standalone binary, easy cross-compilation, good concurrency.

**Disadvantages:** no official `VpnClient` access; must shell out to `pwsh`/`rasdial`; P/Invoke for RAS is harder.

Suggested mapping:

- `os/exec` for `curl.exe`, `rasdial.exe`, and `pwsh.exe`.
- `net/http` for sources.
- `encoding/csv` for CSV.
- `golang.org/x/sys/windows` for P/Invoke when needed.
- For `Add-VpnConnection`, use `pwsh -NoProfile -Command` with a generated script; be careful with quoting and injection.
- Package layout similar to the C# layout.

**Risk:** `VpnClient` behavior through `pwsh` may differ slightly from an in-process runspace (output formatting, error handling).

### 3.2. Rust

**Advantages:** standalone binary, memory safety, precise control.

**Disadvantages:** P/Invoke and COM complexity; longer development time.

Suggested mapping:

- `reqwest` for HTTP.
- `scraper`/`regex` for HTML.
- `csv` for CSV.
- `std::process::Command` for curl/rasdial/pwsh.
- `windows` crate for `RasSetCredentials`, `RasDial`, `RasHangUp`.
- `clap` for CLI with exact names.

### 3.3. Python

**Advantages:** fastest prototyping, abundant libraries.

**Disadvantages:** distribution, interpreter dependency, process/timeout handling; the GIL matters little because testing is sequential.

Suggested mapping:

- `argparse` or `click` for CLI.
- `requests`/`httpx` for HTTP.
- `BeautifulSoup`/`lxml` for HTML.
- `subprocess.run(timeout=...)` for curl/rasdial/pwsh.
- `pywin32` for clipboard and some APIs.
- `csv` with `lineterminator='\r\n'`.
- `pyinstaller` for distribution.

---

## 4. PowerShell-to-Windows API mapping

| PowerShell | Win32/API | C# | Go | Rust | Python |
|---|---|---|---|---|---|
| `Get-VpnConnection` | `RasEnumEntries` / VpnClient | `RasEnumEntries` or runspace | pwsh | windows crate | pywin32/pwsh |
| `Get-VpnConnection -AllUserConnection` | `RasEnumEntries` with the AllUser phonebook | Same | pwsh | Same | Same |
| `Add-VpnConnection` | `RasSetEntryProperties` | P/Invoke or runspace | pwsh | windows crate | pwsh |
| `Set-VpnConnection` | `RasSetEntryProperties` | P/Invoke | pwsh | windows crate | pwsh |
| `Remove-VpnConnection` | `RasDeleteEntry` | P/Invoke | pwsh | windows crate | pwsh |
| `Set-VpnConnectionCredentials` | `RasSetCredentials` | P/Invoke | syscall | windows crate | ctypes/pywin32 |
| `rasdial` | `RasDial` | process or P/Invoke | process | process | subprocess |
| `rasdial /disconnect` | `RasHangUp` | process or P/Invoke | process | process | subprocess |
| `Get-Clipboard` | WinForms/OpenClipboard | WinForms | pwsh | windows crate | pywin32 |
| `Invoke-WebRequest` | WinHTTP/.NET HttpClient | HttpClient | net/http | reqwest | requests |
| `curl.exe` | process | Process | exec | Command | subprocess |
| `Get-PnpDevice` | SetupAPI/WMI | WMI | pwsh | wmi | wmi |
| `Get-CimInstance` | WMI | System.Management | wmi | wmi | wmi |
| `Get-WinEvent` | Event Log API | EventLogReader | wevtutil | windows crate | pywin32 |

**Recommendation:** for the first port, call `VpnClient` through a PowerShell runspace or `pwsh`, and P/Invoke only `RasSetCredentials`. This combination has the lowest behavioral risk. A later phase can replace `VpnClient` with direct RAS APIs.

---

## 5. Suggested migration phases

| Phase | Work | Exit criterion |
|---|---|---|
| `P0` | Domain model, parsers, scorer, CSV writers | Unit tests green; no VPN required |
| `P1` | CLI, validation, modes, console reporting | `-Help` and `-ListExisting` work |
| `P2` | TCP, temporary profile, `rasdial`, cleanup | One real server tested |
| `P3` | Route, latency, download, statuses, ranking | Full new-server run works |
| `P4` | Existing-profile phase and controlled removal | `-VerifyExisting -ReportOnly` and apply work |
| `P5` | Top N, country + host naming, credential storage, duplicate detection | Profiles are added correctly |
| `P6` | Parity testing, packaging, documentation | Release candidate |

A realistic estimate for one full-time developer with a Windows VM is 6–9 weeks (roughly 48 person-days). A two-person team can parallelize implementation, but RAS integration tests MUST remain serial.

---

## 6. Porting risks and mitigations

| Risk | Mitigation |
|---|---|
| Different `VpnClient` behavior in a runspace | Golden tests on the same Windows build; compare `Get-VpnConnection` output |
| Quoting/argument differences | Use `ArgumentList`/argument arrays, never a single shell string |
| CSV differences (culture/quoting) | `InvariantCulture`, `\r\n`, explicit `ClassMap` |
| Timeout differences | Implement process timeouts precisely, including process-tree kill |
| Regex differences | Reuse the reference patterns and test with real fixtures |
| Property-order differences | Define column order explicitly in the writer |
| Console differences | Preserve key text and columns; color is optional |
| Clipboard unavailable | Fall back to an HTML file |
| Partial downloads rejected by mistake | Keep the v16.1.1 rule: real bytes are enough; `DownloadComplete=False` does not prevent acceptance |

---

## 7. Recommended decision

- **Lowest risk and closest behavior:** C#/.NET 8, hosting PowerShell for `VpnClient`, with P/Invoke for credentials.
- **Standalone binary and simple distribution:** Go, shelling out to `pwsh`/`rasdial`/`curl`.
- **Fast prototype or learning:** Python.
- **Maximum control and safety:** Rust.

Whatever the target, implement [SPECIFICATION.md](SPECIFICATION.md) as the contract and use [TESTING.md](TESTING.md) as the acceptance gate. The first release of a port MUST pass the CSV header comparison and the safety tests before it is published.
