# Command: Stop Engagement Processes

You are the operator shutting down all background processes for the current engagement only.

## Step 0: Freeze the Queue FIRST

A stop is not a log line. Take the stop lock before anything else, so no fetch can
be served while you are still shutting things down:

```bash
source scripts/lib/engagement.sh
ENG_DIR=$(resolve_engagement_dir "$(pwd)")
./scripts/stop_engagement.sh "$ENG_DIR" --reason manual_stop --detail "operator stop"
```

That single command (a) writes `$ENG_DIR/.stop-lock`, (b) releases every
`processing` case back to `pending` so a later `/resume` can recover it, (c) stops
this engagement's containers, (d) writes `stop_reason=` into `log.md`, and
(e) composes a partial report. While the lock is held,
`./scripts/dispatcher.sh ... fetch` and `fetch-by-stage` exit 3 and hand out nothing —
which is the whole point: on 2026-09-23 the stop was recorded, in-flight subagents
were never cancelled, and three findings were still appended 20 minutes later.

After the stop:
- Do NOT dispatch anything else, not even a "cleanup" task.
- Do NOT resume dispatching because a late subagent result arrived. Record the result,
  then stop again.
- Do NOT clear the lock yourself. Only an explicit operator resume may do it:
  `./scripts/stop_engagement.sh "$ENG_DIR" --clear`.

## Step 1: Locate Active Engagement

```bash
source scripts/lib/engagement.sh
ENG_DIR=$(resolve_engagement_dir "$(pwd)")
echo "Engagement: $ENG_DIR"
```

If no engagement directory exists, inform the user that no active engagement was found.

## Step 2: Stop All Containers

```bash
source scripts/lib/container.sh
stop_all_containers
```

This stops the mitmproxy and Katana Docker containers for the active engagement if running.
It must not stop containers belonging to another engagement.

## Step 3: Show Final Queue Stats

If `cases.db` exists, display final queue statistics:

```bash
./scripts/dispatcher.sh "$ENG_DIR/cases.db" stats
```

## Step 4: Suggest Next Steps

Ask the user if they would like to:
- Generate a final report now with `/report`
- Review findings in `<engagement_dir>/findings.md`
- Resume processing later (containers can be restarted)

## User Arguments

Additional context from the user follows:
