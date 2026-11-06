# AI Porting Prompt

> **Purpose.** This file is a ready-to-use brief for an AI coding assistant that will reimplement `Test-FreeSstpServers v16.1` in another programming language. It does not replace the normative specification; it tells the assistant how to read and apply it. The result must behave like v16.1, not merely compile.

---

## 1. How to use this file

1. Open the repository in an AI coding tool that can read local files.
2. Copy the prompt in [Section 3](#3-copy-paste-prompt).
3. Replace every `<PLACEHOLDER>` with your choices.
4. Attach or open the four reference files listed in the prompt.
5. Ask the assistant to work phase by phase and to stop after each phase for review.

The prompt assumes the assistant can read the repository. If your tool cannot read files, paste the relevant sections of `docs/SPECIFICATION.md` into the conversation instead.

---

## 2. What the assistant must know first

- The tool is **Windows-only** because it uses `VpnClient`, `rasdial.exe`, the RAS phonebook, and Windows public-IP behavior. A non-Windows port can reuse the parsers, scorer, CSV writer, and CLI, but cannot provide the VPN workflows without a Windows host or a Windows VM.
- `docs/SPECIFICATION.md` is the **normative contract**. If the reference script and the specification ever disagree, stop and report the conflict; do not guess.
- The reference script is **behavior to match**, not code to translate line by line. A port may use different modules, classes, or idioms.
- The published v16.1 engine accepts a download sample when curl receives **real bytes over HTTP 2xx**, even if the full 10 MB transfer is cut short. `DownloadComplete=False` must not reject the server.
- Existing-profile deletion is a destructive operation. It requires an exact uppercase `YES`, and `-ReportOnly` must never delete.

---

## 3. Copy-paste prompt

```text
You are implementing a behavior-compatible port of Test-FreeSstpServers v16.1.

Target language: <TARGET_LANGUAGE>
Target runtime and OS: <TARGET_RUNTIME_AND_OS>
Packaging/distribution: <PACKAGING>
Repository path: <REPOSITORY_PATH>
Preferred UI: <CONSOLE_OR_GUI>
Anything else: <EXTRA_CONSTRAINTS>

Read these files completely before writing code:
1. docs/SPECIFICATION.md — the normative behavior contract. It wins over every other source.
2. Test-FreeSstpServers_v16_1.ps1 — the reference implementation. Match its observable behavior.
3. docs/PORTING.md — language guidance, Windows API mapping, and migration phases.
4. docs/TESTING.md — unit, integration, fault-injection, and golden-CSV tests.

Your task:
- Implement the same observable behavior in <TARGET_LANGUAGE>.
- Keep the tool Windows-only unless I explicitly ask for a non-Windows variant.
- Work in phases P0 through P6. After each phase, run the relevant tests and report:
  what is complete, what is not, what differs from the reference, and what you need from me.
- Do not change the public behavior to make the implementation easier.
- Do not modify the reference PowerShell script.
- Do not invent new parameters, statuses, CSV columns, or messages.

Non-negotiable contract:
- All 41 parameters, their aliases, defaults, and ranges. The alias `PortFilter` must work.
- Validation rules V1 through V10, in the same order, with the same messages.
- Exact status, verdict, planned-action, and action-taken strings. Do not translate or rename them.
- CSV schemas and column order: 43 columns for new-server results, 45 for existing-profile checks, 8 for snapshots, 7 for inventory. Use invariant culture, CRLF, and True/False booleans.
- Partial downloads count when curl receives real bytes over HTTP 2xx, even when DownloadComplete=False. Do not require a complete 10 MB transfer.
- Existing profiles are removed only after a summary and an exact uppercase YES. -ReportOnly never deletes. INCONCLUSIVE always maps to KEEP.
- Only one VPN connection may be active at a time. Clean up temporary profiles in a finally block. Pause later dials after an uncertain RAS state.
- Install only WORKING_TUNNEL_AND_INTERNET servers. Deduplicate by host:port. Never overwrite an existing profile.
- Never write credentials to CSV files or logs. Sanitize profile names. Use argument arrays, not shell string concatenation.
- -Help must work before the Administrator check. Every other mode requires the documented environment checks.

Phases:
- P0: domain model, parsers, merger, scorer, CSV writers, and unit tests. No VPN required.
- P1: CLI, V1-V10 validation, mode precedence, and console reporting. -Help and -ListExisting must work.
- P2: TCP probe, temporary profile creation and verification, rasdial, and cleanup.
- P3: route verification, latency, download, status classification, and ranking.
- P4: existing-profile inventory, verification, report-only, and controlled removal.
- P5: top-N installation, credential storage, and duplicate detection.
- P6: parity tests, packaging, and user documentation.

Definition of done:
- The project builds and starts on the target runtime.
- Unit tests cover parsers, host validation, ping/uptime parsing, merging, scoring, V1-V10, CSV serialization, and the state machine.
- CSV headers match the reference exactly. A header mismatch is a hard failure.
- The safety tests pass: -ReportOnly never deletes; Enter, yes, Yes, and Y never delete; only YES deletes; INCONCLUSIVE is kept; a partial download is accepted.
- The golden CSV comparison passes for the same input snapshot and parameters.
- Packaging and usage instructions are complete for the target platform.

Start with P0 only. Show me the proposed project structure and the test plan before writing production code.
```

---

## 4. Phase prompts

If you prefer to review each phase separately, send these follow-ups after the main prompt.

| Phase | Follow-up prompt |
|---|---|
| P0 | "Implement P0 only: domain model, parsers, merger, scorer, CSV writers, and unit tests. Do not call Windows APIs yet. Show the test results." |
| P1 | "Implement P1: CLI, V1-V10 validation, mode precedence, and console reporting. `-Help` must work without Administrator rights. Do not dial yet." |
| P2 | "Implement P2: TCP probe, temporary profile creation and verification, `rasdial`, and cleanup. Use mocks for tests; do not require a real VPN in CI." |
| P3 | "Implement P3: route verification, latency, download, status classification, and ranking. Preserve the partial-download rule." |
| P4 | "Implement P4: existing-profile inventory, verification, report-only, and controlled removal. Preserve the exact-YES rule and scope fidelity." |
| P5 | "Implement P5: top-N installation, `RasSetCredentials`, duplicate detection, and profile naming. Never overwrite an existing profile." |
| P6 | "Implement P6: golden CSV comparison, safety tests, packaging, and documentation. Produce the release checklist." |

---

## 5. Non-negotiable checklist

Use this list during review. Every item must be confirmed by a test or a code review.

### 5.1. CLI and validation

- [ ] 41 parameters, exact names, aliases, defaults, and ranges.
- [ ] `-PortFilter` alias for `-PortMode`.
- [ ] `-Help` before the Administrator check.
- [ ] `V1`–`V10` in the documented order, with the documented messages.
- [ ] Mode precedence: Help → validation → environment → ListExisting → Verify/Prune → normal.
- [ ] `-ListExisting` and `-ListOnly` still pass the environment checks.

### 5.2. Data and reports

- [ ] New-server CSV: 43 columns in the exact order.
- [ ] Existing-profile CSV: 45 columns in the exact order.
- [ ] Snapshot CSV: 8 columns.
- [ ] Inventory CSV: 7 columns.
- [ ] `$null` becomes an empty field; booleans are `True`/`False`; decimals use a dot; lines end with CRLF.
- [ ] Sorting: results by `DownloadMbps` descending, null last, independent of `RankMode`.
- [ ] Scores: speed normalized to the fastest, latency normalized to the lowest, `Balanced = 0.7 * Speed + 0.3 * Latency`.

### 5.3. New-server workflow

- [ ] TCP probe, temporary profile, stored host/port verification.
- [ ] RAS 633 retry, 638 classification, network timeout, and other dial failures.
- [ ] Route check, tunnel latency, and partial-download acceptance.
- [ ] Cleanup in `finally`; pause later dials after an uncertain RAS state.
- [ ] Only `WORKING_TUNNEL_AND_INTERNET` servers are eligible for installation.

### 5.4. Existing-profile workflow

- [ ] Inventory both phonebooks; detect name collisions and split tunneling.
- [ ] Skip non-SSTP profiles with `NOT_SSTP_SKIPPED`.
- [ ] Multi-attempt TCP, stored-credential dial, fallback credentials, and transient retries.
- [ ] `ACCEPT` → `KEEP`, `REJECT` → `DELETE`, `INCONCLUSIVE` → `KEEP`.
- [ ] `-ReportOnly` never deletes.
- [ ] Only exact uppercase `YES` deletes.
- [ ] Remove only the tested scope; verify removal afterward.

### 5.5. Safety and privacy

- [ ] One VPN connection at a time.
- [ ] No credentials in CSV or logs.
- [ ] Profile names sanitized.
- [ ] Argument arrays, not shell strings.
- [ ] No command execution from source content.
- [ ] Timeouts on every external operation.

---

## 6. Definition of done

A port is ready for review only when all of the following are true:

1. The build is reproducible from a clean checkout.
2. Unit tests pass without a VPN or Administrator rights.
3. CSV headers are byte-for-byte identical to the reference for all four schemas.
4. The golden CSV comparison passes for at least one saved snapshot.
5. The safety tests pass:
   - `-VerifyExisting -ReportOnly` makes no changes.
   - Enter, `yes`, `Yes`, and `Y` keep every profile.
   - Exact `YES` removes only rejected profiles in the tested scope.
   - `INCONCLUSIVE` is always kept.
   - A partial download with real bytes is accepted.
6. `-Help` works without elevation.
7. Packaging and usage instructions are complete.
8. Known differences are documented; there are no silent differences.

---

## 7. Common mistakes to reject

| Mistake | Why it is wrong |
|---|---|
| Requiring a complete 10 MB download | This is v17 behavior; v16.1 accepts real partial bytes. |
| Translating status strings or CSV headers | Breaks compatibility and golden tests. |
| Treating `INCONCLUSIVE` as removable | Violates the safety contract. |
| Accepting `yes`, `Yes`, or `Y` for deletion | Only exact uppercase `YES` is allowed. |
| Deleting from the other phonebook scope | The tested scope is the only valid scope. |
| Running VPN dials in parallel | Corrupts public-IP and RAS results. |
| Writing credentials to CSV or logs | A privacy and security defect. |
| Replacing argument arrays with shell strings | Increases injection risk. |
| Skipping `finally` cleanup | Leaves temporary profiles and uncertain RAS state. |
| "Improving" behavior without a version bump | Breaks behavioral parity. |

---

## 8. Suggested first message to the assistant

If you want a short start instead of the full prompt, send this first:

```text
Read docs/SPECIFICATION.md, docs/PORTING.md, docs/TESTING.md, and
Test-FreeSstpServers_v16_1.ps1 completely. Then propose a project structure
and a P0 test plan for a <TARGET_LANGUAGE> port. Do not write production code
yet. Treat the specification as normative and preserve all 41 parameters,
V1-V10, status strings, CSV schemas, and safety rules.
```

After the assistant responds, send the full prompt in [Section 3](#3-copy-paste-prompt) with your choices filled in.

---

## 9. Hand-off checklist

- [ ] Target language, runtime, and packaging are recorded.
- [ ] The four reference files were read completely.
- [ ] Phase plan is agreed.
- [ ] Unit tests exist before Windows integration.
- [ ] CSV header comparison is automated.
- [ ] Safety tests are automated or documented as manual VM tests.
- [ ] Known differences are listed in the port's README.
- [ ] The port's documentation states that it is based on v16.1 behavior.
- [ ] The port does not claim to be an official release unless the maintainer says so.

---

*This prompt is a tool for implementers. It does not grant permission to change the v16.1 behavior contract.*
