# fips-fix.md — fixing the missing per-cycle feedback packets

The deviation, established on 2026-11-07 against the live campaign
(`autowp-c-mbedtls-20261106-151748`, cycle-8 in progress): **zero
`mbedtls-analysis-fips-feedback-NN.md` packets exist** after 8 cycles, at
least 5 of which ended in a verdict delta (cycle-2: the 7-PROVED batch;
cycle-4: hkdf_expand + ctr_drbg Coq; cycle-6: the OBS-2 VIOLATION, reproduced;
cycle-7: SL-MD-1 retired; cycle-8 in flight). Verified three ways: the
project tree, the whole git history (`git log --all --name-only | grep -i
feedback` → nothing), and every checkpoint diff (each commits the overlay —
patches, `verdicts.tsv`, `trusted-base.md`, `formal-tests.tsv` — but never a
packet).

## Why it matters

The packets are not decoration. Per `fips-sl/SKILL.md` §8 and
`frama-c-launch/references/fips-feedback.md`, they are (1) the **typed,
code-free, RQ#/VO#-keyed evidence** that the next code-blind `fips-sl` cycle
consumes — without them the study's F5 never receives requirement evidence and
the Ann. 13 owner has nothing per-cycle to adjudicate; (2) the **revalidation
history** ("the series IS the history"); (3) the artifact the end-of-run
M-checks and the no-blend discipline are defined against. A campaign that
verifies for 96 h and produces no packets has run the forward half without the
return half.

## Root cause (two layers, both real)

1. **The packet duty lives in a document the working agents never load.**
   The emission rule (Phase-0 numbering + the "generate the next-numbered
   packet on a verdict delta" bullet) is written in `commands/fips.md` — the
   `/fips` command prompt. But the campaign is driven by `/time-loop`, whose
   cycles spawn sub-agents executing the **SKILL layer** (`frama-c-launch` →
   `frama-c-monitoring`), and neither of those SKILL.md files contains a
   packet-emission step (`frama-c-monitoring`'s feedback path is §8e, an
   EBIOS-only branch, plus campaign-close). The driver table maps the packet
   *name*, not the *duty*.
2. **The one bullet the loop does read is half-executed.**
   `commands/time-loop.md` / `skills/time-loop/SKILL.md` say "…emit the next
   `XXX-analysis-monitor-feedback-NN.md` on a verdict delta; **commit + push a
   crash-safe checkpoint**". The checkpoints happened every cycle; the packets
   never did. The most plausible reading: the loop treats the checkpoint as
   the cycle's durable artifact and the packet as campaign-close work —
   exactly the conflation `fips-feedback.md` warns against (the packet is the
   per-cycle artifact; the report is the consolidated one).

## The fixes, in execution order

### F1 — remediate the live campaign (needs a go-ahead; queued-message mechanics)

Emit the missed packets **by the loop itself**, not by hand — hand-writing them
would defeat the provenance chain they exist to carry. Send a queued
instruction to the live harness telling the loop to write, now, one packet per
past delta cycle (numbered `01…N` in cycle order), each per the forward half of
`fips-feedback.md`: verdict → requirement evidence keyed to `VO#`/`RQ#`, no TU
names, no proof internals — sourced from its own records (`time-loop.state`
cycle entries + the per-cycle `verdicts.tsv` state + checkpoint messages),
then update `time-loop.state` with the emission.

Mechanics and risks:

- The composer currently holds the queued self-re-invocation
  (`/time-loop mbedtls 96`). Typing appends to queued text — **first clear the
  composer with `Esc`** (safe: the loop's in-session cron re-arms the wake
  itself; the state file already fixed start and deadline), then queue the
  remediation text with `Enter`, then re-queue `/time-loop mbedtls 96`.
- Exact send: `lxc exec autowp-c-mbedtls-20261106-151748 -- sudo -iu ubuntu
  tmux send-keys -t autowp Escape`, then `send-keys -t autowp -l '<text>'`,
  then `send-keys -t autowp Enter`.
- The instruction must scope itself: "emit the missed packets for the delta
  cycles already recorded; do not stop the running verifier; do not touch the
  deadline."
- Fallback (only if the queued instruction destabilizes the session): let the
  campaign run to the deadline, then have the terminus step emit the packets
  from the state log (they would then be loop-authored after the fact — weaker,
  but the history survives; record the delay in each packet).

### F2 — put the packet duty where the working agents read it (durable)

One sentence each, named through the driver table:

- `skills/time-loop/SKILL.md` (cycle bullet, §0 "What the run does" / the
  monitor bullet): "**emit the next feedback packet of the driver table
  (`XXX-analysis-fips-feedback-NN.md` under fips) at every cycle that produced
  a verdict delta — written by the cycle that produced the delta, never
  deferred to campaign close**".
- `commands/time-loop.md`: the same bullet, beside the checkpoint one it
  already half-executes.
- `fips-sl/SKILL.md` §8 (return half): one line stating the packets are the
  driving loop's per-cycle deliverable and the study consumes the **latest
  numbered** one (it already says "consume the latest numbered packet" — make
  explicit who owes it).

### F3 — make the autonomous watcher look for them

The gap stayed invisible to the 30-minute agent checks because the facts never
included the packets. Add to `~/.local/share/auto-wp/agent-check.sh`'s fact
block (and to its prompt's STATUS rules): `ls $PREFIX-fips-feedback-*.md | wc
-l`, and "zero packets while `time-loop.state` records delta cycles =
deviation; STATUS must say so, ACTION = the F1 instruction".

### F4 — pin it in the tests

- `tests/test_templates.py`, T6-style: assert the time-loop cycle bullet names
  the driver-table feedback name and that `commands/fips.md` keeps the
  Phase-0 numbering rule (so a future edit cannot drop the duty again).
- `tests/c/mbed-tls-test.sh`, new **M.12** (end-of-run): the count of
  `$X-analysis-fips-feedback-*.md` must be ≥ the number of delta cycles the
  state log records (a floor of 1 when any delta exists). Documented in
  `spec/tests.md` §5.5-analog for the fips campaign.

### F5 — record it

Append the deviation + fix to `fips-feedback.md` (validation-debt section) so
the next session sees the pattern: *watch items found in a live campaign
become template bullets and test checks, not chat remarks.*

## Recommended order

F3 first (one-line, makes the watcher guard the fix), then **F1** on your
go-ahead (live-session intervention), then F2 + F4 as a template commit with
the level-1 suite, then F5. If you prefer zero interference with the running
campaign, F1 can wait for the deadline — F2/F3/F4/F5 are independent of it and
can land now.
