---
name: finalize
description: Run post-merge finalization steps (archive change, complete task, sync wiki/domains, commit docs).
---

# finalize Skill

Provides a callable shell entrypoint for finalization in CI and interactive workflows.

## Responsibilities

1. Archive active OpenSpec change when present
2. Complete task tracking (move task to Done / close issue) when configured
3. Sync documentation (`wiki-update` and `domains-update`) when available
4. Commit generated documentation updates with `docs(finalize):` prefix
5. Push Copilot session token usage to Prometheus Pushgateway (`push-session-metrics`)

## Step 1 — OpenSpec Archival

The script auto-detects the active change by matching `openspec/changes/task-<TASK_ID>-*/`
(or branch slug fallback), then archives it via the CLI when available:

```bash
# Preferred (openspec CLI installed)
openspec archive --yes --skip-specs "<change-name>"
# Archives to: openspec/changes/archive/<YYYY-MM-DD>-<change-name>/

# Fallback (CLI not available)
mv openspec/changes/<change-name>/ openspec/changes/archive/<YYYY-MM-DD>-<change-name>/
```

`--yes` bypasses all interactive prompts. `--skip-specs` omits delta-spec sync, which
is safe for CI contexts (the spec content is already committed on the feature branch).
To include spec sync on local runs, omit `--skip-specs`.

## Session metrics (Step 6) — agent-native token push

The agent executes two pushes as part of every finalize run:

### 6a — Retroactive push for the PREVIOUS completed session

> **Token data reality:** `session-store.db` has NO `events` table and NO token columns.
> The SQL approach previously documented here was wrong — **do not query session_store_sql**.
>
> Token data is available exclusively from `events.jsonl` files on disk:
> - `outputTokens` → sum of `assistant.message.outputTokens` events ✅ accurate
> - `inputTokens` → NOT in events.jsonl (in-memory only) — use `--input-tokens` from UI if available
> - `inputTokens` (proxy) → `session.compaction_complete.compactionTokensUsed.inputTokens` ⚠️ partial
> - `cacheReadTokens` (proxy) → same compaction events ⚠️ partial

Find the previous session ID via `session_store_sql` (only for ID lookup, not tokens):
```sql
SELECT id FROM sessions
WHERE id != '<CURRENT_SESSION_ID>'
ORDER BY created_at DESC
LIMIT 1
```

Then push — the script reads the session's `events.jsonl` automatically:
```bash
PREV_ID=<prev-session-id>
MARKER=~/.copilot/session-state/${PREV_ID}/.metrics_pushed
if [[ ! -f "$MARKER" ]]; then
  bash .github/skills/push-session-metrics/scripts/push-session-metrics.sh \
    --session-id "$PREV_ID"
  # Optionally add --input-tokens <N> if you read the exact value from the UI
  touch "$MARKER"
fi
```

### 6b — Live push for the CURRENT active session

The current session is still running. Set env vars and call the script.  
The script auto-reads `outputTokens` (and compaction-proxy `inputTokens`) from `events.jsonl`:

```bash
# Pass --input-tokens only if you know the exact value from the `usage` command
export COPILOT_SESSION_ID=<current-session-uuid>
# INPUT_TOKENS: read from `usage` UI if available; 0 is correct when unknown
export COPILOT_INPUT_TOKENS=<N_or_0>
export COPILOT_MODEL=<model-name>              # auto-detected from events.jsonl
export COPILOT_USER=<github-handle>            # auto-resolved if omitted
export COPILOT_REASON="issue:#<N>"             # auto-resolved from task-id if omitted
export COPILOT_CREDITS=<N>                     # optional
```

Then call the script:

```bash
export COPILOT_SESSION_ID=<current-session-uuid>
export COPILOT_INPUT_TOKENS=<N_or_0>           # 0 when not yet synced — correct
export COPILOT_OUTPUT_TOKENS=<N_or_0>          # script also auto-reads from events.jsonl
export COPILOT_MODEL=<model-name>              # auto-detected from events.jsonl
export COPILOT_USER=<github-handle>            # auto-resolved if omitted
export COPILOT_REASON="issue:#<N>"             # auto-resolved from task-id if omitted
export COPILOT_CREDITS=<N>                     # optional
.github/skills/finalize/scripts/finalize.sh --task-id <x.y>
```

> **Why inputTokens is 0 for live sessions:** The Copilot CLI only writes
> `inputTokens` to the cloud store after the session ends and syncs. This is expected
> behaviour — the retroactive step (6a) fills the gap with accurate data once synced.

See `.github/skills/push-session-metrics/SKILL.md` for full details on all metrics and labels.

## Script Interface

```bash
.github/skills/finalize/scripts/finalize.sh
```

## Behavior

- Uses `set -euo pipefail` and fails fast on errors.
- Skips optional steps if prerequisites are not available.
- Creates a docs commit only when there are staged changes.
- Requires `openspec` CLI on `$PATH` for the preferred archive path; falls back gracefully.

## Integration

- Called by `.github/workflows/agent-run.yml` post-merge job.
- The `agent-run.yml` finalize job installs the `openspec` CLI via `npm install -g openspec`
  before calling this script, so the preferred path is always active in CI.
- Referenced by `.github/prompts/finalize.prompt.md` as thin wrapper.
