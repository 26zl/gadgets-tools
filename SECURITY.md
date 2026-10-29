# Security Policy

## Scope

This repository is a personal collection of pentest-gadget tooling, one folder per
device. It mixes **first-party code** — the Feberis Pro firmware and `geotag` tool
(`flipper/flipper-feberis/`), the Galaxy S10 provisioning scripts
(`galaxy-s10-nethunter/scripts/`), the flash helpers, and the CI — with several
**third-party submodules** that keep their own upstream security policies.

Report against the right project:

| Area | Where to report |
| --- | --- |
| First-party code in this repo | Here — see below |
| `netsec-auditor`, `cybersec-toolkit` (first-party submodules) | Their own repositories' security policies |
| `Momentum-Firmware`, `GhostESP`, `ESP32Marauder`, Bruce, USBArmyKnife, IRDB, payload/portal libraries | The respective upstream projects |

## Reporting a vulnerability

Please report privately — **do not open a public issue** for a security problem.

- Preferred: GitHub private vulnerability reporting on this repository
  (**Security → Report a vulnerability**). If it is not available, enable it under
  *Settings → Code security → Private vulnerability reporting*.
- Include the affected file or path, the device or component, how to reproduce, and
  the impact you observed. Redact any real credentials or captured data.

This is a personal project with no formal response SLA; expect a best-effort
acknowledgement.

## Supported versions

Only the current `main` branch is maintained — fixes land there, with no long-term
support branches. Submodules track their pinned upstream releases, bumped via
Dependabot.

## Authorized use

Everything here is intended for security testing on devices and networks you own or
are explicitly permitted to assess. A vulnerability report is not an invitation to
test against systems you do not control.
