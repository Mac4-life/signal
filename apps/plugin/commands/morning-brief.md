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

> Last night's brief couldn't be generated — Signal couldn't read your Gmail (Google rejected the saved token). Reconnect Signal's Gmail authorization here: [Reconnect Gmail]({{failure.reconnectUrl}}). After reconnecting, click "Run cron now" on your Signal dashboard to regenerate today's brief, or wait for tonight's overnight tick.

Use the `failure.reconnectUrl` from the brief verbatim — it is Signal's own Google OAuth start URL on Vercel (`/api/gmail/oauth/start`). Do NOT direct the user to Claude Desktop settings, the Connectors menu, or any other Claude-side surface — those are different OAuth flows that have no effect on Signal's worker token. If `failure.reconnectUrl` is somehow missing from the brief, point the user at `/dashboard` directly and tell them to click the Gmail "Reconnect" button there.

Continue to step 3 only for `agent` (partial-but-usable). For `gmail_fetch` and `brief_write`, stop here.

**If `brief.proposalIds.length === 0 && brief.summary.nonMemberSignals.length === 0`:**

Print:

> No updates extracted last night. The cron read your Gmail but didn't find any signals worth proposing. Mailchimp is still in sync.

Stop here.

### Step 3 — fetch the proposal records

Construct the brief reference: `briefId = "${brief.uid}/${brief.date}"`.

Call `list_proposals` with `{ briefId, status: "pending" }`. This returns the full `Proposal` records for the IDs in `brief.proposalIds`. (The cron stamps `Proposal.briefId` in the same shape; the filter is exact-match.)

If the returned list is shorter than `brief.proposalIds.length`, some proposals expired (cron-staged proposals live 6 hours). Note the count discrepancy in the output.

### Step 4 — render the proposals table

Print a markdown table with these columns:

| Column         | Source                                                                                                |
| -------------- | ----------------------------------------------------------------------------------------------------- |
| Contact        | `proposal.contactEmail`                                                                               |
| Field          | First key in `proposal.after` (most proposals are single-field; if multi-field, list comma-separated) |
| Before → After | `proposal.before[field] → proposal.after[field]`                                                      |
| Source         | `proposal.source`                                                                                     |

Rows: one per proposal, newest-first (the list comes back sorted by `createdAt` DESC already).

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

Print:

> **Apply all proposals?** Reply `yes` to apply, or call out specific proposals to apply selectively.

If the user replies `yes` (or affirmative variant):

- Call `apply_proposals` with `{ proposalIds: brief.proposalIds }`.
- Confirm the result: number applied, number skipped, any errors. Mention the `batchId` if returned (the user can `reverse_batch <batchId>` within 30 days to undo).

If the user wants selective apply:

- Take their selection (by row number, contact email, or natural language).
- Call `apply_proposals` with the filtered subset.

## Failure modes to handle gracefully

- `get_brief` returns 5xx — print the storage-error message verbatim; tell user to retry.
- `list_proposals` returns fewer records than `brief.proposalIds.length` — proposals expired; render what's available + note the count.
- `apply_proposals` returns drift_detected on some entries — those contacts changed since the brief was generated; show which ones skipped and why.
- User says `apply` then changes mind — confirm before calling `apply_proposals`. The tool runs sequentially for ≤3 ops and via `POST /batches` for >3; either way, applied changes are real.

## Recovery

If the user wants to undo, ask them for the `batchId` from the previous apply confirmation, then call `reverse_batch`. Reverses are idempotent and live for 30 days.
