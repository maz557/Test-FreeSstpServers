# Security policy

## Supported versions

| Version | Supported |
|---|---|
| 16.1.x | Yes |
| 16.0.x | No |
| 17.x | Out of scope for this repository |

## Reporting a vulnerability

Please do not open a public issue for a security problem. Use the repository's
**Security** tab to open a private security advisory, or contact the maintainer
through the GitHub account that owns the repository. Include:

- A description of the issue and its impact.
- Steps to reproduce, preferably on an isolated Windows VM.
- The affected version and command line (redact credentials).
- Any suggested mitigation.

You can expect an initial response within a reasonable time. Please allow a fix
to be prepared before public disclosure.

## Threat model

This tool is an automation layer around Windows RAS and several public network
services. The main risks are:

### Untrusted server lists

The primary list, VPN Gate mirror, plain host list, HTML capture, and clipboard
content are all untrusted input. The parser accepts only host and port values
that pass validation, and it never executes content from a source. A malicious
list can still point the tool at attacker-controlled VPN endpoints; that is
inherent to testing free servers.

### Untrusted VPN endpoints

A server that completes an SSTP tunnel can observe or modify traffic that uses
that tunnel. A successful connection is not a security endorsement. Do not send
sensitive traffic through free VPN servers.

### Credential handling

- `rasdial` receives the username and password as process arguments. On Windows
  this can be visible to other processes running as the same user or an
  administrator. This is an inherent limitation of the reference behavior.
- For profiles the tool creates, credentials are stored in the per-user RAS
  phonebook through `RasSetCredentials`. They are not written to CSV files or
  console logs.
- The default credentials `vpn` / `vpn` are public VPN Gate test credentials.
  Do not reuse a personal password.

### Local system changes

The tool creates and removes per-user VPN profiles, dials and disconnects
connections, and can remove existing profiles after explicit confirmation.
Run it only on a machine you are authorized to modify. Keep a VM snapshot when
testing destructive paths.

### Command execution

External tools are invoked with argument arrays (`ProcessStartInfo.ArgumentList`
in the reference implementation), which reduces argument-injection risk. Profile
names are sanitized before use. Do not replace this with shell string
concatenation.

### CSV and log privacy

Result files can contain public IP addresses, server addresses, and VPN profile
names. Review and sanitize them before sharing. The repository's `.gitignore`
excludes generated reports, but it is not a substitute for reviewing what you
commit.

### Network endpoints

Depending on the selected mode, the tool may contact:

- Configured server-list sources and `r.jina.ai`.
- `api.ipify.org`, `checkip.amazonaws.com`, `icanhazip.com`,
  `ifconfig.me`, `ident.me`, and `api64.ipify.org` for public-IP discovery.
- `speed.cloudflare.com` for download measurements.
- Google, Microsoft, and `example.com` connectivity endpoints.

All requests are outbound HTTPS/HTTP requests. No telemetry is sent to the
project maintainer.

## Operational guidance

- Run `-VerifyExisting -ReportOnly` before any removal run.
- Use `-ExistingRemovalMode Conservative` when in doubt.
- Do not run two instances concurrently.
- Disconnect other VPNs before starting a test run.
- Keep PowerShell and Windows updated.
- Treat generated CSV files as potentially sensitive.
