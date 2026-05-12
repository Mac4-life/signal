---
description: Read the user's overnight brief of proposed Mailchimp contact updates extracted from last night's Gmail signals, render the proposals as a markdown table, surface any "Not in audience" non-member signals, and offer a one-confirmation apply CTA.
---

# /morning-brief

Reads today's overnight brief — proposals the cron pipeline staged from the user's Gmail signals — and renders a table the user can apply with one confirmation. Run any time after the user's local delivery hour.

## What to do when the user invokes this command

### Step 1 — fetch the brief

Call `get_brief` with no arguments. The tool resolves the user's local date from their `users/{uid}.scheduleConfig.tzOffset` (set during `/signal-setup` and the dashboard schedule picker).

Outcome shape: `{ brief: Brief | null }`.

### Step 2 — handle the empty / failed cases first

**If `brief === null`:**

Print:

> No brief yet today. The overnight pipeline runs around your scheduled delivery hour. If you've just connected Signal, the first brief lands tomorrow morning.

Stop here.

**If `brief.summary.failure` is set**, render tailored copy per `failure.step`:

| `failure.step` | Copy to print                                                                                                                                                                                                                                 |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `gmail_fetch`  | See "Gmail-fetch failure rendering" below — the brief carries a structured `failure.reconnectUrl` you must render as a clickable link to **Signal's** dashboard. Never paraphrase this as Claude Desktop's "Connectors" menu — wrong surface. |
| `agent`        | `Last night's brief is partial — the enrichment agent hit an error mid-run. ` + `Staged proposals from before the failure are below. Details: ${failure.error}`                                                                               |
| `brief_write`  | `Last night's brief generated but couldn't be saved. This is a Signal infrastructure issue we'll need to investigate. ${failure.error}`                                                                                                       |

**Gmail-fetch failure rendering.** When `failure.step === "gmail_fetch"`, render exactly:

> Last night's brief couldn't be generated — Signal couldn't read your Gmail (Google rejected the saved token). Reconnect Signal's Gmail authorization here: [Reconnect Gmail]({{failure.reconnectUrl}}). After reconnecting, reply `run brief now` and I'll regenerate today's brief on demand.

Use the `failure.reconnectUrl` from the brief verbatim — it is Signal's own Google OAuth start URL on Vercel (`/api/gmail/oauth/start`). Do NOT direct the user to Claude Desktop settings, the Connectors menu, or any other Claude-side surface — those are different OAuth flows that have no effect on Signal's worker token. If `failure.reconnectUrl` is somehow missing from the brief, point the user at `/dashboard` directly and tell them to click the Gmail "Reconnect" button there.

**Handling the user's `run brief now` reply.** When the user replies `run brief now` (or an affirmative variant like "yes, regenerate", "rerun it", "do it now") after the Gmail-reconnect prompt above, call the `run_brief_now` MCP tool with no arguments. Render the result by `structuredContent`:

- If `ok === true && failure === null` → success. Continue with the regenerated brief from step 3 below (the new brief is already written; re-call `get_brief` to pick it up, or render directly off the `proposalCount`/`nonMemberSignalCount` summary the tool returns and skip ahead to step 7's apply CTA after step 3 fetches the proposals).
- If `ok === true && failure.step === "gmail_fetch"` → the reconnect didn't take. Surface the same Reconnect Gmail link from `failure.reconnectUrl` and ask the user to confirm they completed the OAuth flow in their browser before retrying.
- If `ok === true && failure.step === "agent"` or `"brief_write"` → render the matching row from the failure-step table above with the new `failure.error`.
- If `ok === true && briefRead === "kv_failed" | "missing" | "parse_drift"` → tell the user the pipeline ran but the brief couldn't be read back; ask them to refresh `/dashboard` or re-run `/morning-brief` in a moment.
- If `ok === false` → render the error message from `content[0].text` verbatim. Common shapes: `error === "no_schedule"` (user hasn't picked a delivery hour yet), `error === "not_found"` (no Signal account record).

Do NOT call `run_brief_now` proactively or routinely — only when the user explicitly asks to regenerate after a Gmail reconnect. The tool deletes today's brief and re-runs the full pipeline; firing it on every `/morning-brief` invocation would burn Anthropic + Gmail budget for no reason. The default read path is `get_brief` (already invoked at step 1).

Continue to step 3 only for `agent` (partial-but-usable). For `gmail_fetch` and `brief_write`, stop here unless the user replies `run brief now`.

**If `brief.proposalIds.length === 0 && brief.summary.nonMemberSignals.length === 0`:**

Print:

> No updates extracted last night. The cron read your Gmail but didn't find any signals worth proposing. Mailchimp is still in sync.

Stop here.

### Step 3 — fetch the proposal records

Construct the brief reference: `briefId = "${brief.uid}/${brief.date}"`.

Call `list_proposals` with `{ briefId, status: "all" }`. This returns every `Proposal` record currently in KV for this brief — pending, applied, AND reversed — so you can give the user an accurate picture of what's actionable vs. what's already done.

**Critical: do NOT default to `status: "pending"` here.** That filter silently drops applied/reversed proposals, making the returned list shorter than `brief.proposalIds.length` — which would mislead you into reporting "some proposals expired" when in fact they were already applied (via the `/dashboard` or an earlier chat turn). Cron-staged proposals live 6 hours in KV; chat-staged ones live 30 minutes. Within those windows, a "missing" record almost always means "applied," not "expired."

Partition the returned records by `proposal.status`:

- `pending` → the actionable set; render in step 4 as the "Pending" table and offer to apply in step 7.
- `applied` → already done; render as a short "Already applied this brief" summary line so the user sees the math (no apply CTA on these).
- `reversed` → render only if non-empty; one-line "N reversed via reverse_batch" note.

If `pending.length + applied.length + reversed.length < brief.proposalIds.length`, the gap is **genuinely** TTL-expired records (KV `get` returned null). Only THEN note "N proposals expired before review — re-run `run brief now` if you need them back." Be precise: don't conflate applied with expired.

### Step 4 — render the proposals table

Use ONLY the `pending` partition from step 3 as the table rows. Skip applied/reversed proposals here — they get a separate one-line summary below the table.

Print a markdown table with these columns:

| Column         | Source                                                                                                |
| -------------- | ----------------------------------------------------------------------------------------------------- |
| Contact        | `proposal.contactEmail`                                                                               |
| Field          | First key in `proposal.after` (most proposals are single-field; if multi-field, list comma-separated) |
| Before → After | `proposal.before[field] → proposal.after[field]`                                                      |
| Source         | `proposal.source`                                                                                     |

Rows: one per pending proposal, newest-first (the list comes back sorted by `createdAt` DESC already).

After the table, if `applied.length > 0`, print one line:

> _N proposals already applied earlier (via this chat or the dashboard) — not re-listed above._

If `reversed.length > 0`, print one line:

> _N proposals were reversed via `reverse_batch` — not re-listed above._

If `pending.length === 0` but `applied.length > 0`, the brief is fully resolved — say so explicitly so the user doesn't think the brief is broken:

> All proposals from this brief have been applied. Nothing pending for review. Run `run brief now` if you want a fresh pass over your Gmail.

Stop here in that case — no apply CTA, the work is done.

### Step 5 — render "Not in audience" section

If `brief.summary.nonMemberSignals.length > 0`, print:

> **Not in audience — skipped:**

Then a bullet list, one per signal:

```
- {signal.email} — {signal.signal}  (from {signal.source})
```

These are signals the cron extracted for people who aren't members of any of the user's audiences. Signal never creates contacts, so they're surfaced for awareness only — the user can manually add them through their Mailchimp signup form if they want.

### Step 5.5 — render rescue sections (PR Bounce-C)

The cron's pre-loop populates three optional brief dimensions. Render any that are non-empty.

**Bounced contacts — possible new addresses.** Filter `proposals` (already loaded in step 3) to those where `proposal.source.briefSection === "alternate_address"`. These are pre-staged rescue proposals — they already appear in the main proposals table from step 4. If you want to call them out separately, note the count under that table:

> _N of the proposals above are bounce-rescue candidates (alternate addresses we found in your Gmail). Source citations are in their `source.alternateAddressCandidate.sourceMessageId`._

**At-risk soft-bouncers — signals worth investigating.** If `brief.summary.atRiskSoftBouncers?.length > 0`, print:

> **At-risk soft-bouncers — signals worth investigating:**

Then one row per entry:

```
- {entry.contactEmail} — {entry.consecutiveSoftBounces} consecutive soft bounces
  Possible new address: {candidate.candidateEmail} ({candidate.confidence})
  Source: {candidate.strategy} → {candidate.sourceDeepLink}
```

These are still-subscribed contacts, no proposal staged. The user can ask you to rescue specific ones manually — when they do, you re-run the on-demand chain (`find_alternate_addresses` → `propose_update`).

**Bounced contacts with no signal — consider sunsetting.** If `brief.summary.cleanedNoSignal?.length > 0`, print:

> **Bounced contacts — no signal found ({N}). Consider sunsetting these from active segments:**

Followed by a bullet list of the emails (cap to 10 with a "and N more" tail if longer). Then offer the ack:

> Want me to mark these as reviewed? They won't reappear in tomorrow's brief unless they re-bounce.

If the user agrees, call `mark_bounces_reviewed({ audienceId: brief.uid → user.scheduleConfig.audienceId, contactEmails: [...] })`. The audienceId comes from the user's `scheduleConfig`, which `get_brief` already resolved. Confirm the ack count back to the user.

### Step 6 — render partial / truncation notes

If `brief.summary.partial === true`:

> ⚠ Partial brief: the cron didn't process every email last night.

If `brief.summary.truncatedAfter` is set:

> The agent stopped after `${truncatedAfter}` emails (step cap reached). Older emails weren't processed.

### Step 7 — offer the apply CTA

Only fire this step when `pending.length > 0` (step 4 already short-circuits the all-applied case). The apply set is the pending partition from step 3 — NOT `brief.proposalIds` verbatim, which would re-run already-applied entries (idempotent but noisy in the output).

Print:

> **Apply the {pending.length} pending proposals above?** Reply `yes` to apply all, or call out specific rows / contact emails to apply selectively.

If the user replies `yes` (or affirmative variant):

- Call `apply_proposals` with `{ proposalIds: pending.map(p => p.id) }`.
- Confirm the result: number applied, number skipped, any errors. Mention the `batchId` if returned (the user can `reverse_batch <batchId>` within 30 days to undo).

If the user wants selective apply:

- Take their selection (by row number, contact email, or natural language).
- Call `apply_proposals` with the filtered subset (still drawn from `pending`, not from `brief.proposalIds`).

## Failure modes to handle gracefully

- `get_brief` returns 5xx — print the storage-error message verbatim; tell user to retry.
- `list_proposals` (with `status: "all"`) returns fewer records than `brief.proposalIds.length` — those records are genuinely expired (KV TTL). Render what's available + note the count. **Do not** assume expiry when the count is short under any other condition; if you called `list_proposals` with a status filter (`pending`, `applied`, etc.), shortness reflects the filter, not expiry.
- `apply_proposals` returns drift_detected on some entries — those contacts changed since the brief was generated; show which ones skipped and why.
- User says `apply` then changes mind — confirm before calling `apply_proposals`. The tool runs sequentially for ≤3 ops and via `POST /batches` for >3; either way, applied changes are real.

## Recovery

If the user wants to undo, ask them for the `batchId` from the previous apply confirmation, then call `reverse_batch`. Reverses are idempotent and live for 30 days.
