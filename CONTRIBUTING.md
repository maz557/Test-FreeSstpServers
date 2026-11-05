# Contributing

Thank you for considering a contribution. This project automates changes to
Windows VPN profiles, so correctness and safety matter more than feature count.

## Before you start

- Read [docs/SPECIFICATION.md](docs/SPECIFICATION.md), especially the safety
  rules and the status/CSV contracts.
- Read [docs/TESTING.md](docs/TESTING.md).
- Use an isolated Windows 10/11 virtual machine for manual tests. The tool
  creates and removes VPN profiles and may change RAS state.
- Never commit real credentials, public IP addresses, personal profile names,
  or unsanitized CSV reports.

## Compatibility rules

The following are part of the public behavior contract:

- Parameter names, aliases, defaults, and ranges.
- Validation messages and their order (`V1` through `V10`).
- Status strings, verdicts, planned actions, and action-taken values.
- CSV file names, column names, and column order.
- The `YES` confirmation rule for deletion.
- `INCONCLUSIVE` always mapping to `KEEP`.
- One VPN connection at a time.

A pull request that changes any of these needs an explicit compatibility
discussion in an issue first. Improvements that do not preserve v16.1 behavior
belong in a future major version.

## Development setup

1. Install PowerShell 7.
2. Open an elevated PowerShell session.
3. Confirm that `VpnClient`, `curl.exe`, and `rasdial.exe` are available:

   ```powershell
   Import-Module VpnClient
   Get-Command curl.exe
   Test-Path "$env:WINDIR\System32\rasdial.exe"
   ```

4. Run a parse check before testing:

   ```powershell
   $errors = $null
   [System.Management.Automation.Language.Parser]::ParseFile(
       (Resolve-Path .\Test-FreeSstpServers_v16_1.ps1),
       [ref]$null,
       [ref]$errors
   ) | Out-Null
   $errors.Count
   ```

## Coding guidelines

- Keep user-facing console messages in English, matching the reference script.
- Keep code comments in English.
- Do not translate CSV column names or status strings.
- Use `ProcessStartInfo.ArgumentList` (or an equivalent argument array) rather
  than building shell command strings.
- Give every external operation a timeout.
- Dispose processes, sockets, and temporary profiles in `finally`.
- Add or update tests for parser, scorer, validator, and state-machine changes.
- Keep changes focused. Separate refactoring from behavior changes.

## Testing

At minimum, run the unit tests and a parse check. Manual integration tests must
cover the changed path:

- `-Help` without elevation.
- `-ListExisting` (no dial, no change).
- `-VerifyExisting -ReportOnly` (no deletion).
- The specific status or CSV field affected by your change.

See [docs/TESTING.md](docs/TESTING.md) for the full matrix.

## Commit messages

Use a short imperative subject, optionally with a scope:

```text
parser: reject ports above 65535
existing: keep profiles when disconnect state is unreadable
docs: clarify partial-download scoring
```

## Pull requests

- Describe the behavior change and the tests you ran.
- State explicitly whether CSV headers, status strings, or defaults changed.
- Include sanitized sample output when it helps review.
- Do not include generated CSV files, HTML captures, or logs.

## Reporting bugs

Open an issue with:

- Windows version and PowerShell version.
- The exact command line (redact credentials).
- The relevant status and error text.
- The CSV header line only, not the full data rows.
- Whether the problem reproduces on a clean VM.

Security issues should follow [SECURITY.md](SECURITY.md), not the public issue
tracker.

## License

By contributing, you agree that your contribution is licensed under the MIT
License used by this repository.
