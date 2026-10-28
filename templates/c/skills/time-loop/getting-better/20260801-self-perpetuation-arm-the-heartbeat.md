# Self-perpetuation: the loop must arm its own heartbeat (the 6-hour-idle relapse)

**Date:** 2026-08-01
**Classification:** coherent-and-wrong — MECHANISM relapse (distinct from the stop-and-propose PHRASING relapse)

## What happened

The Linux-7.1.3 LSM Frama-C/WP campaign ran cycles 669–671 back-to-back (11:33–11:40),
each ending with a correctly-phrased "the loop carries forward on <next seam>" report —
no stop-and-propose, no resume-invitation, scouting done for the next cycle. Then the turn
ended (context/compaction) and **nothing re-invoked the loop.** It sat completely idle from
11:40 until the human re-engaged manually at ~17:39 — **~6 hours dead.**

The user asked "When was the last time you were working?" and then "How come you have been
not active 6 hours ago. Fix the skills so that it never happens again."

## Why it was wrong (and why it slipped past the existing stabilizers)

The skill already had strong anti-stop-and-propose and CHAIN-WITHIN-TURN stabilizers — and
they were being *followed*: the cycle reports genuinely ended by starting the next cycle
(scouting it), with no hand-back phrasing. **But those stabilizers only govern behavior
WHILE A TURN IS LIVE.** They say nothing about what re-invokes the loop once a turn ENDS
(compaction, context-limit, a completed cycle).

The Invocation section *mentioned* a "fallback heartbeat" and said to "arrange the schedule
via /loop / ScheduleWakeup / cron" — but it was phrased as advisory, **never mandated,
never gated, never verified.** So the agent simply never armed one, and relied entirely on
the human's manual `/time-loop` heartbeats and "continue" messages to advance. When the
human stepped away, the "autonomous N-hour campaign" silently degraded into "advances one
step each time a human pokes it." `CronList` at diagnosis time showed **zero jobs** — the
heartbeat had never been set.

This is a MECHANISM relapse, orthogonal to the PHRASING relapse the loop was already guarding
against: a perfectly-phrased "the loop carries forward" is still a **silent death** if no
wakeup is armed to actually carry it.

## The fix (mechanism)

A **cron job fires its prompt only while the REPL is IDLE** — i.e. exactly when a turn has
ended and the loop would otherwise sit dead. So a recurring `CronCreate` re-invocation is a
precise *restart-after-idle watchdog*: it does nothing while a turn is live (CHAIN-WITHIN-TURN
drives that), and restarts the chain the instant the turn ends.

Armed at diagnosis: `CronCreate("6,16,26,36,46,56 * * * *", <continue-the-loop prompt>)` —
every 10 min at off-minutes. (`ScheduleWakeup delaySeconds=120` is the equivalent inside a
`/loop` dynamic session.)

## The fix (skill — so it never happens again)

Made self-perpetuation **MANDATORY and GATED** in SKILL.md:
- **Invocation heartbeat bullet** rewritten: the loop arms its OWN re-invocation on activation
  (`CronCreate`), and **`CronList`-verifies it at the START of every cycle**, re-arming if
  absent (cron is session-only + 7-day-expiring, so re-arm proactively). "ARMING ONE IS NOT
  OPTIONAL."
- **Activation clause** rewritten: "The FIRST action on activation is to ARM a self-re-invoking
  heartbeat ... a turn that ends while no heartbeat is armed is a SILENT DEATH." Tripwire:
  sensing the turn is about to end without a confirmed-live heartbeat this turn IS the relapse —
  `CronList`/arm before the turn ends.
- **§7 stabilizer** added: "SELF-PERPETUATION — the loop arms its own heartbeat; it never waits
  to be poked," explicitly distinguishing the MECHANISM relapse from the PHRASING (stop-and-
  propose) relapse.

## Tripwire (one line)

Before any turn ends — and at the start of every cycle — run `CronList`; if there is no live
loop-heartbeat job, `CronCreate` one NOW. A campaign with no armed wakeup is not autonomous.
