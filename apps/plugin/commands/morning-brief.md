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

### Step 3 — load the data Signal already prepared

Two MCP calls (both fast, results inform every later step). Don't surface tool names in your user-facing output — they're internal plumbing.

1. **Fetch the staged updates for this brief.** Construct `briefId = "${brief.uid}/${brief.date}"`, then call `list_proposals` with `{ briefId, status: "all" }`. This returns every record currently in KV for this brief — pending, applied, AND reversed — so you can describe what's actionable vs. what's already done.

   **Critical: do NOT default to `status: "pending"` here.** The default filter silently drops applied/reversed records, making the returned list shorter than `brief.proposalIds.length` — which would mislead you into reporting "some updates expired" when in fact they'd already been applied (via `/dashboard` or an earlier chat turn). Cron-staged records live 6 hours in KV; chat-staged ones live 30 minutes. Within those windows, a "missing" record almost always means **applied** or **superseded by a fresh scan** (`run_brief_now` deletes the brief and re-stages under new IDs), not "TTL expired."

2. **Fetch the audience info** so you can render merge-field tags as human names AND show the audience's human name (not its raw ID).
   - Call `list_audiences` (no args). The response includes every audience with `id`, `name`, and `memberCount`. Find the audience whose `id` is the first segment of `proposals` you got back: any pending/applied record has `proposal.audienceId`, so pick `audienceName = audiences.find(a => a.id === proposals[0]?.audienceId)?.name ?? "your audience"`. (Single-audience users will just see one entry.)
   - Call `get_audience_schema` with `{ audienceId: proposals[0]?.audienceId }` (if there are no records to derive the audience from, skip the schema call — the all-applied / all-superseded path won't render any tags anyway). Build a quick lookup: `tagToName = Object.fromEntries(schema.mergeFields.map(f => [f.tag, f.name]))`. Every time you'd otherwise show a tag like `LASTCONT` in user-facing prose, render `tagToName[tag] ?? tag` so the user sees "Last contacted" instead.

Partition the staged-updates response by `proposal.status`:

- `pending` → still actionable; renders in step 4 as the main table and gets the Apply offer in step 7.
- `applied` → already done; one-line summary in step 4 (no Apply CTA on these — they're history).
- `reversed` → render only if non-empty; one-line "N undone from this brief" note.

**Diagnosing missing records.** If `pending.length + applied.length + reversed.length < brief.proposalIds.length`, decide between two cases (use the brief's `generatedAt` to break the tie):

| Time elapsed since `brief.generatedAt`                      | Likely cause                                                                                                                 | What to say                                                                                         |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| < 6 hours, brief is original (not regenerated this session) | Some records purged early (rare — KV TTL is 6h on cron-staged)                                                               | "N updates aged out of the staging window before review"                                            |
| < 6 hours, but `run_brief_now` was called this session      | **Superseded by a fresh scan** — old IDs were dropped when the brief was regenerated under new IDs. This is the common case. | "N earlier suggestions were replaced when we re-scanned. The current list above is the latest set." |
| > 6 hours                                                   | Genuine TTL expiry                                                                                                           | "N updates aged out of the staging window. Re-scan your inbox to bring back the latest."            |

Never use "30-minute TTL" in user-facing copy for cron-staged briefs — that's the chat-side number and doesn't apply. **Don't conflate applied with expired.** Don't conflate superseded with expired.

### Step 4 — render the suggested updates

Use ONLY the `pending` partition from step 3. Skip applied/reversed records here — they get summary lines below the table.

Open with a one-sentence framing the user can read at a glance. Use the audience name from step 3's schema lookup (never the raw audience ID, never the literal phrase "proposals generated"):

> Last night's scan of your inbox found **{pending.length} suggested update{s}** for {audienceName}.

Then print a markdown table:

| Column          | What goes in it                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| #               | Row number, 1-based, so the user can refer to a row by number in selective apply.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Contact         | `proposal.contactEmail`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| What's changing | A human-readable summary of `proposal.before` → `proposal.after`. For each key in `proposal.after`: render `{tagToName[key] ?? humanizedKey}: "{before}" → "{after}"` (use em-dash for `null`/`""` before-values: `—`). If multi-field, one bullet per field within the cell. **Do NOT print the raw tag** (like `LASTCONT` or `ICOUNT90D`) — always translate via the `tagToName` map from step 3. **Do NOT print arrow notation against dates without context** — e.g. `LASTCONT → 2026-05-12` is unreadable; render `Last contacted: 2026-05-12` instead. For `schema_mutation` records (which add new merge fields rather than update a contact), the cell renders `New audience field: {mergeFields.map(f => f.name).join(", ")}` — those don't have a meaningful Contact column, so use the audience name as the Contact cell for those rows. |
| Why             | A one-line citation pulled from `proposal.source.text` if present, else the briefSection (translate: `templated` → "Templated signal", `alternate_address` → "Bounce-rescue candidate", `general` / `cron` → "Email content"). For relationship-signals proposals (those with `source.text` like "Relationship signals (last 90 days)"), render "Relationship signals — last 90 days".                                                                                                                                                                                                                                                                                                                                                                                                                                                              |

Rows: one per pending record, newest-first.

After the table, render concise summary lines (each only if its count > 0):

- `applied.length > 0` → `_{N} more update{s} already applied (this chat or the dashboard) — not re-listed above._`
- `reversed.length > 0` → `_{N} update{s} from this brief were undone earlier — not re-listed above._`
- "missing" gap from step 3 → use the prose from step 3's diagnosis table (superseded / aged-out / TTL-expired wording, chosen by the elapsed-time + run_brief_now check).

**All-applied short-circuit.** If `pending.length === 0 && applied.length > 0`, the brief is fully resolved. Render explicit success copy and stop — no apply CTA, no follow-up question, the work is done:

> ✅ Every suggested update from this brief has been applied. Nothing left pending. Ask me to scan your inbox again whenever you want a fresh batch.

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

### Step 7 — offer to apply

Only fire when `pending.length > 0` (step 4 short-circuits the all-applied case). The apply set is the pending partition from step 3 — NOT `brief.proposalIds` verbatim, which would re-fire already-applied entries (idempotent but noisy).

Print exactly one of these two prompts:

- If `pending.length === 1`:
  > **Apply this update to Mailchimp?** Reply `yes` to apply, or `skip` to leave it for now.
- If `pending.length > 1`:
  > **Apply all {pending.length} updates to Mailchimp?** Reply `yes` to apply everything, or call out specific rows (e.g. "row 2" or the contact email) to apply a subset.

If the user replies `yes` (or affirmative variant):

- Call `apply_proposals` with `{ proposalIds: pending.map(p => p.id) }`.
- Render the result in plain English. Count successes, count skips, count errors. Mention the batch ID **only** if there were ≥1 successes, in the recovery-friendly phrasing: `_If you need to undo, ask me to "reverse batch {batchId}" — reversal stays available for 30 days._`. Don't lead with the batch ID — it's plumbing.

If the user wants selective apply:

- Take their selection (by row number, contact email, or natural language). Resolve to a subset of `pending`.
- Call `apply_proposals` with the filtered subset (still drawn from `pending`, not from `brief.proposalIds`).
- Render the result in the same English-first style.

**Lexicon discipline through this whole flow:** in user-facing output, talk about **suggested updates** or **updates**, not "proposals." Talk about **applying** an update, not "staging" it. Talk about **scanning your inbox**, not "re-running the cron pipeline." Talk about **audience name** (from step 3's schema), not raw audience IDs. Never expose MCP tool names (`apply_proposals`, `list_proposals`, `run_brief_now`) in prose to the user — when prompting for an action, use English ("ask me to scan again", "regenerate this brief"). Tool names are fine inside fenced code blocks if the user explicitly asks how to do something themselves.

## Failure modes to handle gracefully

- `get_brief` returns 5xx — print the storage-error message verbatim; tell user to retry. Don't paraphrase the error in technical terms — say "Signal couldn't load today's brief; try again in a moment."
- `list_proposals` (with `status: "all"`) returns fewer records than `brief.proposalIds.length` — use the **diagnosis table from Step 3** to pick the right user-facing wording: "superseded by a fresh scan" if `run_brief_now` was called this session, "aged out of the staging window" if more than 6 hours have passed since `brief.generatedAt`, and **never** "30-minute TTL" for cron-staged briefs. Don't assume expiry when the count is short under any other condition.
- `apply_proposals` returns drift_detected on some entries — those contacts changed in Mailchimp since the brief was generated; render plainly: "{N} update{s} skipped because {contact}'s record changed since this brief was written. Re-scan to bring in the latest." Don't say "drift detected" verbatim.
- User says `apply` then changes mind — confirm before calling `apply_proposals`. Either way, applied changes are real and reach Mailchimp immediately on success.

## Recovery

If the user wants to undo, ask them for the batch ID from the previous apply (it appears in the success-prose from step 7), then call `reverse_batch`. Reversals stay available for 30 days. In user-facing copy, talk about "undoing the batch" — not "calling reverse_batch."
