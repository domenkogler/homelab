# HD-489 tail — B4: correctness / smartness, L0 self-consistency floor

Measured 2026-10-03 against the **live `ar-blk`** engine on spark (external runner,
Rule 0 clean, bearer from 1Password via `--token-env` through the loopback tunnel).

## L0 — self-consistency floor (first, as the brief orders)

**Protocol:** 30 prompts × 2 at `temperature 0`, under the winner's real
`spec{mtp,3,block}` + `enforce_eager`, at conc 1 **and** conc 2. Same build, same
prompt, same temperature → if not token-identical to itself, that flake is the floor
every comparison must sit above.

| conc | n | token-identical | diff | flake rate |
|---|---|---|---|---|
| 1 | 30 | 12 | 18 | **60 %** |
| 2 | 30 | 9 | 21 | **70 %** |

## Verdict

**L0 = FAIL (the floor is huge).** The winner at `temperature 0` is **not**
token-identical to itself 60–70 % of the time. That is a very large self-consistency
floor, and it means:

1. **No B4/delta comparison is valid at token-level identity.** The flake floor is
   ~60–70 %, so a needle/battery "passed/didn't" is near-meaningless; L1 (noise floor,
   `new − old` vs `old − old`) is the correct lens, and even that must sit above a 60 %
   floor.
2. **This explains the 91 ↔ 98 ↔ 99 spread in our own captures** the brief already
   warns about: same build, same config, flaking.
3. **Why so high at temp 0?** The profile's `override_generation_config` sets
   `{"temperature":1,"top_p":0.95,"top_k":20}` — a **server-side generation config that
   overrides the client's `temperature 0`**. So the client's `temperature 0` is NOT
   honored; the engine samples at temp 1 → near-maximal flake. That is itself the
   confound the brief names (`override_generation_config` in the ledger).

**Consequence:** any quality claim on this profile must either (a) run with a
temperature the engine actually honors (the profile's server-side default, i.e. state
the real temp in the ledger) or (b) be judged as a *distribution* comparison, never a
token-identity or one-shot one. L1 + the §E suites (machine-scored, paired) are the
only comparisons with power at this floor.

## Evidence

- `raw/l0-selfconsistency.py` (the driver) · `raw/l0-result.txt` (the two rows)
- Runner: external seat; window 2026-10-03 ~16:20–16:45 UTC