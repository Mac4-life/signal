---
description: Read the user's overnight Mailchimp contact-update brief, print the pre-formatted summary the worker provides verbatim, and offer a one-confirmation apply CTA.
---

# /morning-brief

Reads today's overnight contact-update brief and prints it. Run any time after the user's scheduled delivery hour.

## What to do when the user invokes this command

### Step 1 — fetch the rendered brief

Call `render_brief` with no arguments. The worker partitions the brief, translates merge-field tags, resolves the audience name, and formats the markdown — there is no Claude-side rendering work left to do. The tool returns a `structuredContent.result` shape:

- `markdown` (string): the fully-formatted brief.
- `pendingProposalIds` (string[]): the apply set in display order.
- `pendingByContact` (array of `{ proposalId, contactEmail }`): same order as `pendingProposalIds`. Use for selective apply by row number or email.
- `hasPending` (boolean): whether to expect an Apply confirmation.
- `failureStep` / `reconnectUrl`: only set on Gmail-failure briefs.

### Step 2 — print `result.markdown` verbatim

Print `result.markdown` exactly as returned. Do NOT reformat, summarize, paraphrase, annotate, or add a preface. The worker has already applied every rendering rule (tag → human name, audience by name, status partition, plural/singular CTA, diagnosis copy, no-op suppression). Re-formatting risks reintroducing bugs the worker already fixed.

If `result.failureStep` is set, the markdown already contains the user-facing copy (the Gmail reconnect link, the partial-brief banner, or the storage-error explainer). You don't need a separate branch — just print the markdown.

### Step 3 — handle the user's reply (only when `result.hasPending === true`)

When the user replies `yes` (or affirmative variant: "apply", "go ahead", "do it"):

- Call `apply_proposals` with `{ proposalIds: result.pendingProposalIds }`.
- Render the outcome in plain English: count of successes / skips / errors. If at least one succeeded, append the recovery footer: `_If you need to undo, ask me to reverse batch {batchId} — reversal stays available for 30 days._`

When the user names specific rows (by row number, contact email, or natural language):

- Resolve their selection to a subset of `result.pendingByContact`.
- Call `apply_proposals` with the filtered subset of `proposalIds`.
- Render the outcome the same way.

When `result.hasPending === false`, there is nothing to apply. Do not offer an Apply CTA, do not call `apply_proposals` — the markdown already explains the state.

### Step 4 — if the user asks to regenerate

If the user replies `run brief now` (or "regenerate", "rerun") — typically after reconnecting Gmail on a `failureStep === "gmail_fetch"` brief — call `run_brief_now` with no arguments, then re-invoke this command from Step 1 to print the fresh brief. Do NOT call `run_brief_now` proactively on every invocation; the cron handles the routine case.

## Recovery

If the user wants to undo a previous apply, call `reverse_batch` with the batch ID from the apply confirmation. Reversals stay available for 30 days.
