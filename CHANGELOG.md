# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
semantic versioning for its public releases.

## [16.1.0] - 2026-11-05

### Added

- Existing-profile maintenance phase:
  - `-ListExisting` inventory of per-user and AllUser VPN profiles.
  - `-VerifyExisting` standalone verification of existing SSTP profiles.
  - `-PruneFirst` verification followed by the normal new-server run.
  - `-ReportOnly` dry-run mode that never deletes.
  - `-ExistingRemovalMode Balanced|Conservative`.
  - `-ExistingTcpAttempts` and `-ExistingTcpRetryDelaySec`.
- Controlled removal after a summary table and an exact uppercase `YES`.
- `RasSetCredentials` integration for storing credentials in the per-user
  RAS phonebook.
- Existing-profile CSV report with 45 columns.
- Connectivity fallback probes (Google, Microsoft, example.com) when the
  download endpoint is unavailable.
- Public-IP fallback services for existing-profile verification.

### Changed

- Existing-profile verification uses the v16 speed-test engine: a sample with
  real bytes over HTTP 2xx is accepted even when the full requested download
  does not finish before the timeout.
- All temporary profiles are removed in a `finally` block, after confirming
  disconnection.
- Later VPN dials are paused when RAS state is uncertain.

### Fixed

- The Windows-stored profile address is parsed and compared with the intended
  host and port before dialing, preventing tests against the wrong endpoint.
- `-ListOnly` saves the snapshot before `-MaxServers` truncation, so the saved
  list is complete.
- CSV column order matches the actual PowerShell 7.6.9 serialization order.

### Documentation

- Added an authorship note: the maintainer designed and tested the program;
  AI wrote the code under the maintainer's direction.
- Added `docs/PORTING-PROMPT.md`, a copy-paste brief for generating a
  behavior-compatible port in another programming language.
- Linked the porting prompt from the README, specification, and porting guide.

### Known limitations

- Windows 10/11 only.
- Free servers are untrusted and can disappear at any time.
- Speed and latency measurements are point-in-time observations.
- The default `vpn` / `vpn` credentials are public VPN Gate test credentials;
  they are not suitable for private providers.

## [16.0.0] - 2026-11-03

- Proven v16 server-testing engine: primary list plus VPN Gate supplementary
  source, merge by host:port, source-PING shortlist, real tunnel latency,
  partial-download speed samples, ranking, and top-N profile installation.

[16.1.0]: https://github.com/maz557/Test-FreeSstpServers/releases/tag/v16.1.0
