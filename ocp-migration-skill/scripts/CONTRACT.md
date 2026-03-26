# OCP Migration Script Contract (Production)

This document defines the runtime contract between orchestration (AI or human operator) and executable migration scripts.

## Design Goals

- Deterministic, idempotent, non-interactive phase execution
- Structured logs suitable for CI/CD and audit trails
- Strict exit-code taxonomy for automated recovery and retry
- Clear separation between orchestration logic and privileged command execution

## Entrypoints

- Bash: `scripts/run-phase.sh`
- PowerShell wrapper: `scripts/run-phase.ps1`

## Invocation

```bash
bash scripts/run-phase.sh --phase 0 --env-file ./.env --state-file ./workspace/.migration-state.json --workspace-root .
bash scripts/run-phase.sh --phase all --resume --env-file ./.env --state-file ./workspace/.migration-state.json --workspace-root .
```

```powershell
./scripts/run-phase.ps1 -Phase 0 -EnvFile ./.env -StateFile ./workspace/.migration-state.json -WorkspaceRoot .
./scripts/run-phase.ps1 -Phase all -Resume -EnvFile ./.env -StateFile ./workspace/.migration-state.json -WorkspaceRoot .
```

## Phase Handler Contract

Each phase is implemented in `scripts/phases/phase-XX-*.sh` and must:

1. Source `scripts/lib/common.sh`
2. Validate required env vars
3. Execute a non-interactive command from `.env` (`PHASE_<N>_CMD`)
4. Return one of the standardized exit codes

## Required `.env` Runtime Variables

Global:

- `APP_NAME`, `DC`
- `MAX_RETRY` (default: `3`)

Per phase command (non-interactive shell command string):

- `PHASE_0_CMD` ... `PHASE_10_CMD`

Each command should be idempotent and safe to rerun.

## Exit Code Taxonomy

- `0` success
- `10` dependency missing (`jq`, `git`, `oc`, etc.)
- `11` invalid argument / CLI misuse
- `12` environment/config invalid (`.env` missing keys)
- `13` state file invalid/corrupt
- `20` external API failure (Jira/Bitbucket/Jenkins/XLR)
- `21` OpenShift failure
- `22` git operation failure
- `23` validation/smoke failure
- `30` manual action required
- `40` phase implementation missing
- `50` transient/retryable error
- `99` unexpected internal error

## Logging Contract

All scripts print line-oriented logs. Important lines:

- `[PHASE N START]`
- `[PHASE N COMPLETE]`
- `[PHASE N FAILED -> error handler]`
- `[MANUAL REQUIRED] ...`
- `[BLOCKER] ...`

Machine-readable event lines should use:

```text
EVENT|<timestamp>|<level>|<phase>|<code>|<message>
```

## Retry & Error Handling

- Retry policy is enforced in `run-phase.sh`
- Retries run only for exit codes `20`, `21`, `22`, `50`
- Max attempts controlled by `MAX_RETRY` (default `3`)
- After final failure, blocker is appended to state (`state.blockers[]`)

## Security Requirements

- Never echo secrets or token values
- Never commit `.env`, credentials, `sec-*.properties`, `*.jks`
- Keep privileged commands in scripts, not in prompts

## Phase-to-Reference Mapping

- `0` -> `references/PHASE-0-bootstrap.md`
- `1-2` -> `references/PHASE-1-2-jira-bitbucket.md`
- `3` -> `references/PHASE-3-migration.md`
- `4-5` -> `references/PHASE-4-5-secrets-certs.md`
- `6` -> `references/PHASE-6-xlr.md`
- `7` -> `references/PHASE-7-local.md`
- `8` -> `references/PHASE-8-jenkins.md`
- `9-10` -> `references/PHASE-9-10-ocp-smoke.md`
