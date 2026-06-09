# Skill: push-session-metrics

Push Copilot CLI session token/credit usage as Prometheus metrics to the Pushgateway.  
Called automatically at the end of every `finalize` run.  
Gives per-task observability: tokens consumed, model used, credits burned, cache efficiency.

---

## When to invoke

- **Automatically** — Step 6 of `finalize.sh` calls this after every task completion.
- **Manually** — when asked to push metrics for the current or a past session.
- **Retroactively** — at the start of a new session to catch up on the previous session's
  data once the cloud store has synced.

---

## Agent workflow (LLM instructions)

### Step 1 — Gather context

Collect the following values (all optional, fall back to defaults if unavailable):

| Value | Source |
|-------|--------|
| `session_id` | Current session UUID (e.g. from `/Users/<you>/.copilot/session-state/`) |
| `task_id` | Active task file name (e.g. `9.29`) |
| `model` | From `finalize` context or events.jsonl `session.start` event |
| `user` | `GITHUB_ACTOR` → `gh api user --jq .login` → `git config user.name` |
| `reason` | GitHub Issue number linked to task, or task ID |
| `credits` | If known (e.g. read from UI, estimated, or omit → 0) |

---

### Step 2 — What token data is actually available

> **Reality:** `session-store.db` (the `session_store` SQL database) does **NOT** store
> token counts. The `turns` table only has `user_message` and `assistant_response` text.
> There is no `events` table and no `usage_input_tokens` / `usage_output_tokens` columns.
>
> Token data sources (in order of accuracy):
>
> | Token type | Where available | Accuracy |
> |---|---|---|
> | `outputTokens` | `events.jsonl` → `assistant.message.outputTokens` | ✅ per-request, accurate |
> | `inputTokens` | **NOT in events.jsonl** — in-memory only during session | ❌ 0 during live session |
> | `inputTokens` (proxy) | `events.jsonl` → `session.compaction_complete.compactionTokensUsed.inputTokens` | ⚠️ compaction call only, fraction of total |
> | `cacheReadTokens` (proxy) | `events.jsonl` → `session.compaction_complete.compactionTokensUsed.cacheReadTokens` | ⚠️ compaction call only, not per-request |
> | `totalNanoAiu` | same compaction event | ⚠️ proxy |
> | `credits` | in-memory only (`usage` command) | ❌ not on disk |
>
> The script auto-reads all of the above from `events.jsonl` when `--session-id` is set.
> Pass `--input-tokens <N>` to override if you know the actual count (e.g. read from the UI).

**Do NOT attempt to query `session_store_sql` for token data — the table doesn't exist.**  
The retroactive approach for previous sessions works by reading their `events.jsonl` directly:

```bash
# For a previous (completed) session — read its events.jsonl via --session-id:
bash .github/skills/push-session-metrics/scripts/push-session-metrics.sh \
  --session-id "<prev_session_uuid>" \
  --task-id    "<task_id>" \
  --reason     "issue:#N"
# Script reads events.jsonl from ~/.copilot/session-state/<id>/events.jsonl
```

---

### Step 3 — Call the push script

```bash
# Full invocation with session_store_sql data (retroactive or post-sync):
bash .github/skills/push-session-metrics/scripts/push-session-metrics.sh \
  --task-id  "9.29" \
  --input-tokens  <N_from_sql> \
  --output-tokens <N_from_sql> \
  --user     "$(gh api user --jq .login)" \
  --reason   "issue:#42" \
  --credits  <N_if_known> \
  --session-id "<session_uuid>"

# Live invocation (session still active — inputTokens auto-resolved to 0):
bash .github/skills/push-session-metrics/scripts/push-session-metrics.sh \
  --task-id  "9.29" \
  --user     "$(gh api user --jq .login)" \
  --reason   "issue:#42" \
  --session-id "<session_uuid>"
```

The script auto-reads `outputTokens`, `cacheReadTokens`, `totalNanoAiu`, and `model`
from `events.jsonl` when `--session-id` is provided, unless `--output-tokens` is
passed explicitly (the explicit flag wins).

---

### Step 4 — Retroactive push for PREVIOUS session (optional but recommended)

At the start of a new finalize run, the agent can optionally push complete data for
the **previous** session (which has now synced):

1. Find the previous session ID from `session_store_sql`:
   ```sql
   SELECT id, created_at
   FROM sessions
   WHERE created_at < now() - INTERVAL '5 minutes'
   ORDER BY created_at DESC
   LIMIT 1
   ```

2. Check if already pushed (use a local marker file):
   ```bash
   MARKER=~/.copilot/session-state/${PREV_ID}/.metrics_pushed
   [[ -f "$MARKER" ]] && echo "Already pushed, skipping." && exit 0
   ```

3. Query full token data and push, then write the marker:
   ```bash
   touch "$MARKER"
   ```

This pattern ensures every session gets accurate, complete metrics — just with a
one-session delay for input tokens.

---

## Metrics pushed

All metrics carry labels: `task`, `model`, `repo`, `user`, `reason`.

| Metric | Source | Notes |
|--------|--------|-------|
| `copilot_session_output_tokens` | events.jsonl or session_store_sql | token-accurate |
| `copilot_session_input_tokens` | session_store_sql (post-sync) | 0 during active session |
| `copilot_session_total_tokens` | sum of above | |
| `copilot_session_cache_read_tokens` | events.jsonl compaction events | cache efficiency proxy |
| `copilot_session_cost_nano_aiu` | events.jsonl compaction events | cost proxy |
| `copilot_session_credits` | manual / env `COPILOT_CREDITS` | from UI if available |
| `copilot_session_timestamp_seconds` | unix timestamp | when push happened |

---

## Environment variables (set by finalize.sh)

```bash
COPILOT_SESSION_ID     # current session UUID
COPILOT_MODEL          # model name
COPILOT_INPUT_TOKENS   # from session_store_sql query (or 0)
COPILOT_OUTPUT_TOKENS  # from events.jsonl (or session_store_sql)
COPILOT_USER           # github handle
COPILOT_REASON         # issue number or task ID
COPILOT_CREDITS        # from UI reading (or 0)
PUSHGATEWAY_URL        # auto-resolved via `gh variable get PUSHGATEWAY_URL --org Wecoya`
```

---

## Why inputTokens are 0 during live sessions

The Copilot CLI's `events.jsonl` only records `outputTokens` per `assistant.message` event.
`inputTokens` (the context sent to the LLM per turn) live in the Node.js runtime memory
and are only written to the cloud session store (`session_store_sql`) after the session
closes and syncs. This is why a live finalize push shows `input_tokens=0` — it is correct
for the moment, not a bug. Use the retroactive push mechanism above to get complete data.

---

## Pushgateway details

- **URL:** `PUSHGATEWAY_URL` org variable (default: `http://10.43.125.170:9091`)
- **Protocol:** HTTP PUT (idempotent — same job key overwrites previous push)
- **Job key:** `copilot_<repo_slug>`
- **Access:** Requires Tailscale (cluster-internal endpoint)
- **Failure mode:** Script always exits 0 — push failure never blocks finalize
