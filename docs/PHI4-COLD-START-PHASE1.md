# Phi-4 Cold Start: Phase 1

Phase 1 establishes that Phi-4 can remain stopped by default to recover memory
without disrupting the always-on local inference dependencies. It does not add
a wake helper or automatic wake-aware monitoring.

## Dependency inventory

| Component | Endpoint or state | Phase-1 finding |
|-----------|-------------------|-----------------|
| Phi-4 live owner | `hermes-llama@8082.service` / Phi-4 | Intentionally disabled and stopped by default |
| `mpt-minimax` container | `Created` | Not running; not the live owner of `:8082` |
| Hermes-LCM | `:8080` | Uses the dedicated always-on endpoint, not Phi-4 |
| Always-on inference | `:8080`, `:8081` | Remained healthy during the Phi-4 start/stop tests |
| Endpoint watchdog | `:8080`, `:8081` by default | Excludes intentionally cold `:8082`; `WATCHDOG_PORTS` can explicitly override the scope |

## Measured proof

Measurements were taken on 2026-08-20.

| Check | Result |
|-------|--------|
| Available memory before making Phi-4 cold | About 1.5 GiB |
| Available memory with Phi-4 cold | About 4.7–4.8 GiB |
| First readiness measurement | 77 seconds |
| Corrected readiness measurement | 66 seconds |
| First stop | Hit the old 30-second timeout |
| Corrected stop | Completed successfully with the corrected systemd stop allowance |
| Completion markers | `PHI_COLD_START_OK` and `PHI_COLD_START_V2_OK` |

These results show that the live Phi-4 unit can be started on demand and
stopped cleanly while `:8080` and `:8081` stay healthy, and that keeping it cold
returns roughly 3.2 GiB of available memory. The completion markers above are
the real test-run markers, not illustrative commands.
