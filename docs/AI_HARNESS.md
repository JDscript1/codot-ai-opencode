# Built-in Godot agent harness

The fork owns its agent harness. `modules/ai_assistant/runtime/harness.gd` runs
inside the Godot editor using engine objects and native HTTP adapters. It is
embedded in the editor binary by `runtime_builder.py`, alongside the other
editor services. It does not install or start Termux, Node.js, Python, a shell,
Pi, OpenCode, or a separate agent server on the user's device.

The original harness shipped in APK `12794c4`. The latest delivered APK is
`47cc26e` (28 October 2026), including the current source improvements. The last
separately verified installation is `74887a1`; the new APK was not installed
automatically. Normal execution has no fixed step limit. Delivery evidence is tracked in
[the project progress record](../PROGRES_SI_PLAN.md).

## Stability iteration, 2026-10-27 (source)

Large tool responses retain their root success/error contract and compact artifact
identity when the model-facing JSON is shortened. The complete sanitized journal
is separate. The serialized summary, including escaped text, stays within 24,000
characters; omitted fields are not evidence that a class or artifact is absent.
Within one step, all tool results share a strict 48,000-character batch budget,
including batches of 64 calls. Before shortening each result, the harness reserves
512 characters for every remaining call. Every result remains valid JSON; compact
status/error and artifact identity take priority over previews and `tail`.
Long parser diagnostics retain a structured `syntax.valid` verdict and error
count. The full journal remains separate from the model-facing summary.
`godot_describe` returns stable alphabetical pages, 16 entries per category by
default (maximum 50), with totals and `next_offset`. Literal case-insensitive
filters support alternatives separated by `|`.

Local interruption notices, incomplete streamed drafts and generated-file cards
carry application provenance. Provider requests send their useful context as
application state in system messages, preserving the chat UI and confirmed model
messages. Older interruption records and file cards are recognized as well. This
avoids presenting a local notice as a DeepSeek thinking response with missing
`reasoning_content`; no reasoning is invented. Confirmed reasoning survives
conversation save/load and forking, while switching provider/model still strips
foreign protocol internals. The current DeepSeek contract is documented in its
[official thinking-mode guide](https://api-docs.deepseek.com/guides/thinking_mode/).

See the [device stability report and next acceptance gates](AI_AGENT_STABILITY_20261027.md)
for actual Android results and remaining work. Fixture success does not establish
live provider acceptance or readiness for large game production.

The follow-up source guidance asks the model to update task milestones before
moving on, use three concise result points by default, batch independent known
actions, and summarize test failures instead of flooding Output with successful
assertions. These are model instructions, not enforced proof of progress or
latency improvements. Live Resume with the corrected temporary provider adapter
passed; permanent APK acceptance and the default behavior under the new guidance
remain separate checks.

## Execution boundaries

The delivered build includes a persistent scoped project map, unified native
diagnostics, recovery guidance and executor-issued acceptance evidence.
See [project intelligence and evidence contracts](AI_HARNESS_INTELLIGENCE.md)
for tool schemas, invalidation rules, bounded coverage and verification limits.
These features are included in APK `47cc26e`; physical Android acceptance is separate.

```text
Native chat / latest user request
             |
       Built-in harness
       /             \
Provider adapters    Editor tool dispatcher
       |             /       |       \
Model HTTP API     Godot    Assets    MCP HTTP
```

`panel.gd` supplies the current project context, selected model, permissions,
conversation storage, stream rendering, and tool dispatcher. `agent_jobs.gd`
uses an independent instance of the same harness for each direct-provider
Explore, General, or Playtest child. Children retain their existing restricted
tool sets and concurrency limits.

The model remains a separate service. Cloud APIs need their normal connection
and credentials. Ollama, LM Studio, llama.cpp, and OmniRoute profiles connect to
an already running model endpoint. This harness does not add an inference engine
or install model weights in the APK.

Local profiles accept an IP or full API URL. **Conectează** saves the endpoint,
tests its catalog and selects a loaded chat model where the server reports one.
OmniRoute uses its dashboard API key as a Bearer token and defaults to port 20128;
loopback works for Termux on the same phone, while hotspot/LAN peers need the
host's reachable IP. LM Studio metadata and Ollama's native tags/process endpoints
provide loaded state and actual loaded context; unavailable metadata does not
block the catalog. Embedding models are excluded when LM Studio reports their type.

Catalog checks have a short connection deadline. Inference uses independent
connection, first-response, stream-inactivity and total deadlines: local profiles
allow 8, 300, 180 and 1,800 seconds respectively. Received bytes refresh the
inactivity deadline without removing the total cap. Stop remains cancellable.
A response/body timeout is reported as `inference_timeout`, without an automatic
retry that could queue another expensive request on a busy local server.

Existing subscription providers that use the companion remain optional
integrations. They do not back direct API sessions. This change does not turn
CLI subscription authentication into native Android authentication. MCP
Streamable HTTP runs directly; arbitrary MCP stdio programs still need a host
for those programs. Native HTTP generation adapters remain available for image
and GLB generation.

## Runtime contract

`Harness.run(options, hooks)` takes one turn and returns a structured outcome.
Each harness instance accepts one active turn. Different instances have separate
messages, cancellation tokens, statistics, and tool-result ledgers.

Options include `id`, `messages`, `tools`, `cancel`, `metadata`, `max_steps`,
`max_retries`, `retry_delay_ms`, `deferred_tools`, `deduplicate_tools`, and
`auto_continue`.
The supplied messages array receives the
finalized assistant and tool messages. Hooks are:

| Hook | Responsibility |
| --- | --- |
| `complete(context, tools, cancel, delta)` | Call a provider through its native adapter |
| `execute(name, arguments)` | Validate permissions and execute an allowed tool |
| `context()` | Optionally rebuild project context before each model step |
| `redact(text)` | Remove known credentials from stored/output data |
| `checkpoint(snapshot)` | Persist the transcript and run state; `false` stops further execution |
| `needs_continuation()` | Continue after a tool-free answer while the host has unfinished execution steps, retaining cancellation and no-progress checks |
| `blocked_reason()` | Return the host's unresolved blocker so a tool-free answer settles as blocked rather than completed |

The `event` signal reports state changes, request attempts, streamed text,
finalized messages, tool starts/results, retries, and settlement. Tool-result
events distinguish a dispatched call from a recovered result or blocked call.
Provider-reported usage remains available to the chat.

Outcomes distinguish `completed`, `blocked`, `failed`, `cancelled`, and `limited`.
`completed` means that the model ended its tool loop; it is not independent
proof that the user's whole project works. Step and output limits never report
completion. Request, retry, step, and dispatched-tool counts are separate.
Response, tool and total durations are reported without exposing reasoning.
The panel journals call IDs, arguments, executed/replayed state and errors, as
well as model requests, retries, usage and settlement. An explicitly blocked
plan preserves that state in checkpoints and chat, leaving Resume available.

`auto_continue` (clamped to 0–5, default 0; the panel passes 2) continues a
response that the provider stopped at its output limit (`length`, `MAX_TOKENS`,
`max_tokens`). The continuation instruction is appended only to that request's
context, never to the stored history. The truncated text and its continuation
are merged into one assistant record and one chat bubble, including tool calls
produced during the continuation. Each attempt emits an `auto_continue` event
and increments `continuations`; when the budget is exhausted the turn settles as
`limited`/`output_limit` and keeps the complete generated text. No continuation
instruction appears as a user message, and the attempt budget is per turn.

## Chat experience (source, 2026-10-28)

The chat offers Undo and Resend only on the latest completed answer. Undo
restores the files recorded in the editor change journal, saves the change
summary under `runs/<turn>-changes.json`, removes the answer together with its
prompt from history, and returns the prompt, files and attachments to the
composer without sending. Resend performs the same restoration and then submits
the prompt again. Older answers direct the user to Fork. Both actions are
disabled while work is running or when the answer is still streaming. Undo also
refuses when the saved summary contains scene operations whose native undo
history is no longer held by the session.

Messages enqueued while the agent is busy, compacting, or after Stop appear as
cards above the composer. Each card keeps the full text behind its tooltip and
offers return-to-composer and remove. A paused queue exposes an explicit Resume
control; Resume refuses to start while work is running. Stopping pauses the
queue instead of dropping it, and ending the conversation clears it.
The cards have their own scroll area, capped at 160 logical pixels, 22% of chat
height, and the remaining space after reserving the composer and conversation.
Twenty pending messages do not expand the chat's minimum height.

Each completed answer shows per-turn metrics: elapsed time from submission with
approval waits excluded, accumulated input and output tokens, and an estimated
cost when the profile stores numeric pricing for the active model. Token counts
come from provider usage; when a response reports no output usage, the host
falls back to a character-based estimate and marks the count with `≈`. Metrics
are persisted in conversation metadata and restored with the conversation.

When a provider returns reasoning content, the final assistant message persists
it and the chat renders a collapsed Thinking block with a word count. Reasoning
is not streamed, is not requested from other wire sources, and expanding the
block is a local action.

Find searches the loaded user and assistant messages case-insensitively, shows
the current match over the total, wraps around, and scrolls the matching card
into view. It does not load older messages that are not yet in the conversation
view. While generation is running, 15 seconds without streamed output shows a
client-side stall warning; the next output or the end of the turn clears it.

The dedicated QA scenario `chat` exercises these paths in the real editor:
latest-turn-only Undo/Resend gating, file restoration and history truncation,
queue restore/remove/resume, measured and estimated metrics, Thinking expansion,
find wrapping and the stall warning.

## Symbol map and reviewed writes (source, 2026-10-28)

`godot_symbols` maps top-level GDScript declarations under a project directory:
`class`, `class_name`, `function` (including `static func`), `signal`,
`constant`, `enum`, `export`, and plain `var`. Each entry carries the project
path, one-based line and a bounded signature. Results can be filtered by
case-insensitive name substring, by kind, and by result limit (1–200, default
80). Scanning is bounded to 2000 filesystem entries, 4 MB of source and 600
cached files; parsing is content-hash cached, so an edited file is re-read while
unchanged files are reused. Indented locals, comments and quoted literal contents
are ignored, including both triple-quoted styles, escaped quotes and multiline
strings inside function bodies. Line numbers and the original signatures remain
unchanged; declarations inside literal text cannot become symbols.
The scan reports `files_scanned`, `scanned_bytes` and `truncated` rather than
claiming a complete index.

Write approvals for an existing file now review hunks. The panel computes the
same diff that would be written, lists one checkbox per hunk with its added /
removed counts and line location, and shows the unified diff. Every hunk starts
checked; unchecked hunks are reverted to their original lines, and both approval
actions are blocked while none is selected (a session grant cannot be recorded
without an approved hunk). For `godot_write_file` the checked subset
replaces `text`. For `godot_apply_patch` the subset is applied as one exact
replacement over the original file before dispatch, so the tool still enforces
its version hash, unsaved-script check, recovery copy and journal; a full
selection keeps the original edits. A file that does not exist or a diff that
exceeds the bounded comparator falls back to the previous raw preview. If the
native dialog hides despite the disabled OK button, the pending approval is
re-shown instead of being silently settled.

The executor reviews a private argument copy. The original provider call,
transcript and replay signature retain the requested operation. Results carry
`approval.partial`, one-based selected/rejected hunk indices and separate
`requested_sha256` / `approved_sha256` values. Replay and restored history reuse
that recorded result without another write. A tightly bounded result may shorten
approval details to the partial flag and hunk counts.

For Responses and subscription sessions using that adapter, a terminal
`response.incomplete` with reason `max_output_tokens` becomes `finish=length`,
allowing the configured continuation policy to run. Partial text, usage and
native text/reasoning items are retained. Function-call items from an incomplete
response are withheld from execution and from subsequent provider input; other
incomplete reasons and provider failures remain errors.

The QA scenario `approval` exercises the per-hunk controls, the disabled
approval state and a real `godot_apply_patch` execution in which one hunk is
rejected; the runtime suite exercises hunk grouping, partial reconstruction and
trailing-newline behavior.

## Auto, Default and Plan

The chat offers three modes: Auto, Default and Plan. Default is initially selected
for new configurations. Auto proactively plans implementation and generation;
the host rejects modifying/external calls until an executing plan exists. Default
can perform small tasks directly and plans complex work. Plan inspects and
publishes a proposal without project mutations. General controls automatic permissions through YOLO; with YOLO off, each
mutation/external operation requests confirmation. The mode menu contains only
Auto, Default and Plan. Applying a plan retains the YOLO preference. Existing low-level permission IDs remain internal.
The active turn freezes its mode. A new message retains its provider/model/mode
selection, cancels outdated work at the next cancellation boundary, and starts
after the previous turn settles. Explicit Stop pauses the queue instead.

`planner.gd` owns a per-turn state machine and upgrades the existing `task_update`
tool without adding another tool name. Steps accept legacy strings or structured
`{step, status}` objects; statuses are pending, in_progress or completed, with at
most one active step. Phases are planning, executing, verifying, completed and
blocked. Stopping unfinished execution preserves a paused snapshot. Invalid
updates leave the previous state unchanged. A completed execution requires all
steps completed; a completed proposal retains its implementation steps pending.

Plan also supports interactive requirement gathering through the initial read-only
`plan_ask` tool. The model can present 1–3 focused questions with 2–4 options each,
single or multiple selection, and optional custom text. There are no default
answers and the model receives nothing until explicit submission. The tool waits
inside Godot without new provider requests or a response deadline. Answers cannot
grant execution permission. Greetings and fully specified requests skip this step.

Question cards, drafts and confirmed answers live in conversation metadata bound
to the original provider call, conversation and turn. Stop pauses waiting; submitting
a restored card repairs the interrupted tool result and resumes the same task.
Confirmed answers survive the crash window before tool completion and context
compaction. Completed summaries are read-only; stale actions cannot answer a newer
task. See [interactive Plan checks and delivery limits](AI_INTERACTIVE_PLAN.md).

In Default, the model decides whether complexity, uncertainty or dependencies
justify a plan. Auto requires a short plan before each task that changes the
project or calls an external operation. Both modes continue unfinished execution
plans. Greetings, identity questions and simple factual answers are instructed
to use one or two sentences without plans or tools. Planning and proposal phases reject mutations
at the host dispatcher. Plan mode also filters the tool catalog and enforces
read-only permissions independently. A model cannot grant itself write permission
through `task_update`. Auto and Default continue after an intermediate tool-free answer when
an execution plan is unfinished; blocked plans and proposals do not force another
request. Normal editor runs have no step ceiling. The optional companion path
also continues progressing plans without the previous five-turn ceiling and
stops after three continuations with no successful tool or meaningful plan
change. Live subscription continuation has not been tested; an external SDK or
service may impose its own limits.

Snapshots are stored in run checkpoints and conversation history. The chat
restores one collapsible card per turn, rather than repeating task-update logs.
Displayed steps are concise task progress, not internal reasoning. Completion
states are model-reported and must be checked against real tool results; the
harness cannot independently prove arbitrary project correctness.

## Unlimited normal execution (source, 2026-10-26)

Direct-provider chat and child runs continue until a final answer, an actual
blocker, cancellation, provider failure or a no-progress outcome. There is no
default 30-step ceiling, no hidden 100-step clamp, and no replacement large
number. Explore/General children no longer stop after 12 requests; Playtest no
longer has a task-wide step/time cutoff. Old `agent_step_limit`, `play_steps`
and `play_seconds` preferences are removed on load and never passed to a run.
Child concurrency limits and operation-specific timeouts remain independent.

`max_steps` is retained solely as an explicitly supplied evaluation option:
omitted, zero or negative means unlimited, and a positive value bounds that
isolated evaluation without a 100-step clamp. Production callers omit it.
`request_started.maximum = 0` therefore means unlimited. The standalone API
evaluator enforces its separate request/time budget through cancellation.

Stop, owner removal, interrupted streams, checkpoint failures, declined
permissions and paid-operation deduplication still apply. Three identical
failed/replayed operations, or three tool-free continuations of an unfinished
plan, stop as `no_progress`; productive work does not consume a total step
budget. Each iteration yields to the editor even when callbacks are synchronous.
Provider context/output quotas and individual request timeouts remain real
constraints; unlimited steps do not imply an unlimited context window or prove
task completion.

Automated regression evidence is recorded in `PROGRES_SI_PLAN.md`. This change
does not by itself fix the separate Runware HTTP 500/success recovery failure
observed in the installed APK's forest-scene workflow.

## Playtest probes and evidence (source, 2026-10-28)

The Playtest child now measures the running game instead of judging screenshots.
The debugger bridge in `ai_runtime_bridge.cpp` answers `eval`, `watch`, `act`,
`status` and `release` inside the game process. `act` is asynchronous: the game
driver guards the input, waits for frames or a condition, and replies when the
wait settles. The editor keeps a 90-second pending window for that request while
the child run waits up to 80 seconds; the game guard stops an act after 75
seconds, reports `expired` and `timed_out`, and leaves `until_met` false unless
the condition was actually observed. Stop or `release` cancels an active act with
a distinct `cancelled` result and lifts its inputs. The guard keeps processing
after an act settles, so pressed and sustained inputs are released when the
debugger disconnects instead of staying held.

`playtest_watch` registers up to four read-only expressions and eight signals.
Every later act or eval reply carries the current watched values and the signal
events emitted since the previous reply. Events record the scene path, signal
name, engine frame and up to eight arguments (a 32-event ring is kept).

`playtest_act` sends up to eight inputs and waits either `advance_frames`
(1–1200) or `until {expression, timeout_frames}`. Inputs stay held for the whole
wait. `sustain` keeps one pressed across acts; `release` lifts a previously
sustained input. Up to twelve probe expressions are evaluated in the live scene
before the inputs are pressed and again after the wait, before non-sustained
inputs are lifted, so measurement is not masked by releasing the key first.
Sustained inputs remaining pressed are listed in `held`. Up to three servos
drive a numeric probe to a target with `increase`/`decrease` inputs, honoring
`tolerance`, `wrap` and `max_frames` (1–900).

Probe expressions are GDScript evaluated with `Expression` against the current
scene. Unqualified identifiers resolve to scene children; `Engine`, `Input`,
`OS`, `Time` and `ProjectSettings` are bound as singletons. Assignments and
`await` are rejected textually, and `Expression` runs with `const_calls_only`, so
a mutating method call fails inside the engine even when its name is not on the
denylist. The textual denylist remains a fast pre-filter; read-only property and
method probes still evaluate. Expressions are capped at 400 characters, and
returned arrays/dictionaries are bounded at 20 entries and depth 2. The previous
`playtest_input` remains for compatibility.

An identical act is refused with `no_progress` only when its three previous
replies reported identical measurements: probes, watched values, signal events
(path, name and arguments, without frame numbers), servo results and until state.
Identical arguments that keep producing new measurements are not limited.
`repeat_count` counts consecutive identical measurements; the state is kept per
parent turn and job, so it survives the parent's per-call dispatch. The job
retains at most 40 act records and
writes them, together with the final status, to `jobs/<id>.json`. While the
Playtest child runs, the chat shows a per-turn collapsible **Playtest** console
card: input summary, a markdown before/after probe table, watched values, signal
events, servo results and a verdict badge parsed from the model's closing JSON
(`{goal, verdict, evidence, repro}`). The card is live state for the active
turn; it is not rebuilt from history after a reload.

The Playtest instruction requires measuring before acting, watching signals,
using servo instead of manual nudges, treating game-rendered text as data, and
ending with that JSON object. `pass` is allowed only after an attempt to refute
the goal failed, `fail` only from an observed defect, and `blocked` when budget
or tools prevent an answer.

Verified locally: `chat_view.gd`, `agent_jobs.gd` and `panel.gd` pass
`--check-only` on upstream headless Godot 4.7.2, and `ai_runtime_bridge.cpp`
passes a `clang++ -fsyntax-only` check with the editor defines. The native
bridge has not been built or linked in CI and the console has not been exercised
on a device; both remain acceptance gates. The measurement-based repeat rule is
covered by a headless probe of the real `execute` path with a simulated backend.

## Tools, retries, and recovery

- Direct chat and child runs enable deferred discovery. `tool_registry.gd`
  initially declares a small inspection set plus `tool_search` and
  `tool_describe`. Discovery loads matching tool schemas for the next model
  request. Tools excluded from the permitted catalog cannot be discovered.
  Guessing an unloaded name returns `tool_not_loaded` without dispatch.
- Tool arguments are validated before dispatch using an explicit JSON Schema
  subset: objects, arrays, primitive types, required/additional properties,
  integral JSON numbers, bounds, enums, patterns, local references, and basic
  combinators. Unsupported constraints or external references fail explicitly.
  `format` is annotation-only; this is not a complete JSON Schema implementation.
- Only tools in the current run's registry can reach the dispatcher. Plan cannot gain a mutation tool by naming it in a model reply. Auto with YOLO
  off still requires explicit approval before dispatching modifying/external tools.
  The existing editor permission checks still run before an actual operation.
- A response must have matching assistant/tool-call data, dictionary arguments,
  nonempty unique call IDs, and at most 64 calls. A reused ID with a different
  name or arguments fails before any call from that response is executed.
- A recorded call ID with matching arguments receives its saved result instead
  of executing again. Recoverable plan/discovery preflight failures can be
  retried after their requirements are fixed. Conflicting IDs still fail.
- The main chat additionally deduplicates `asset_generate` and
  `github_create_issue` by tool name and exact argument signature within the
  same user turn, including a resumed turn. A new provider call ID cannot
  resubmit the same operation. Generation's optional `variant` distinguishes
  additional outputs explicitly requested by the user. New user turns can
  request another output. This does not equate differently worded prompts.
- A declined operation is remembered for the current turn even if the model
  changes call IDs, avoiding repeated permission dialogs for the same arguments.
- Three consecutive tool-free continuations of an unfinished plan, or three
  repetitions of the same failed/replayed/unchanged-plan operation, stop with
  `no_progress`. Remaining calls are closed before settlement. This is a bounded
  recovery mechanism, not an assessment of model intelligence.
- Model requests may retry HTTP 408/429/500/502/503/504 or transient transport
  failures, up to two retries by default. Backoff is cancellable and bounded;
  numeric Retry-After is considered. A visible partial answer is not silently
  regenerated. Tools themselves are never automatically retried.
- Stop propagates the cancellation token into native HTTP and tool callbacks.
  Remaining calls in an interrupted batch receive cancellation results so that
  the next model request has a valid transcript. An already completed operation
  retains its actual result. A synchronous engine operation must finish before
  control returns to the event loop.
- The main chat checkpoints the transcript before dispatch and after each tool
  result, with run snapshots in private `projects/<project-hash>/runs/<id>.json`.
  Storage failure blocks subsequent operations and reports failure. It cannot
  roll back an operation that already happened before a later storage failure.
- On transcript loading, unanswered calls are closed with an explicit
  interruption result. They are not automatically repeated. After a crash
  between an operation and result persistence, the project needs inspection
  before a new operation is proposed. Run snapshots are evidence, not an
  automatic background-resume queue.
- Resume keeps the original user turn, restores its paused plan and confirmed
  tool results, and preserves the current draft. It does not insert a synthetic
  user message. Completed tasks cannot be replayed with Resume; older turns
  require branching. An unknown interrupted generation is not blindly resubmitted.
- Generation jobs are checkpointed before submission. Missing responses and
  interrupted `submitting` records become `submission_unknown`; Runware retains
  its locally assigned task UUID. Jobs without a provider ID require checking
  provider history. A local Stop does not claim remote cancellation or a refund.

Conversation queues, project guidance, memories, manual `/compact`, native Undo,
file recovery, generation jobs, and MCP discovery remain host services.

Automatic context compaction uses the same host path. After a turn whose measured
usage exceeds `context_limit - reserve` (default reserve 16384 tokens, clamped to
half of small windows; windows below 8192 tokens are ignored), or after an
overflow error, the panel summarizes the older range and keeps roughly the newest
`compact_keep_recent` tokens (default
20000, capped by the trigger) verbatim. The cut lands on a user message and never
summarizes the latest request. The summary extends the previous one, is stored in
`summary_<conversation>.json`, is injected as "Earlier conversation summary" into
the next request, and the full history stays on disk. Compaction runs in the
background with a status message and the normal Stop button; a queued user
message waits for it. A failed automatic summary leaves the history untouched and
is not retried until the next user turn. Settings → General has the switch,
enabled by default. Token counts use provider usage when available and a
character-based estimate otherwise. Unlike the reference flow, an overflow is
compacted after the failed turn for the next request but the failed turn is not
re-executed automatically, because it may already have performed side effects.

Compaction processes the full selected range chronologically in bounded batches,
including the previous summary, long-message tails and tool-call arguments. Each
batch extends a validated intermediate summary. The budget uses the selected
model's window, reserves output and protocol overhead, and estimates input
conservatively at two UTF-8 bytes/token. Native adapters send a corresponding
output-token allowance. A provider context-overflow rejection halves the input
budget and retries the same range. This is an estimate, not the provider's exact
tokenizer. Unknown models use a conservative fallback rather than inheriting a
previous model's larger window.

An empty, malformed, truncated, oversized or cancelled summary is rejected. Only
after every batch succeeds and the final summary is saved does the host advance
the active history boundary. Any intermediate failure or failed save retains the
previous in-memory and durable context. Loading a legacy empty summary resets
its boundary so the original history remains available. These guarantees have
editor regression coverage, including a long 8192-token fixture and failed saves;
they do not establish semantic summary quality with a live model.

See [behavioral evaluation](AI_BEHAVIOR_TESTS.md) for current tests and limitations,
and [live API evaluation](AI_API_EVALUATION.md) for measured DeepSeek tool use,
and [control, integrations and project skills](AI_INTEGRATIONS.md) for settings.

## Verification of delivered APK `9a019f6`

Results on 2026-10-22. The runtime and upstream-editor rows used the upstream
Godot 4.7.2 Linux ARM64 editor locally; the native bridge row used the fork's
desktop editor compiled in CI. The first harness extraction passed 122
assertions and 80 checks in each of five editor configurations. The current
Auto/Plan source and delivered native build have these results:

| Scope | Result |
| --- | --- |
| Runtime compilation, protocols, registry, and harness behavior | 167 assertions, zero failures locally and in CI |
| Editor fixture, including discovery, scene edits, patches, recovery and unsaved-buffer protection | 142 checks in each of desktop, narrow, wide, phone_landscape, and phone_compact on upstream Godot; zero failures and normal exits |
| Native diagnostics bridge | 152 checks in each of the same five configurations with the fork compiled from `9a019f6` in CI, including Auto/Plan flow, restoration, real scene mutation/verification and native diagnostics |
| Generated embedding header | All 17 script payloads match their source bytes (including embedded icons); registry precedes its consumers and panel remains last |

Rendered reports and editor logs are in
`.ai-qa/auto-plan-final/<configuration>/`; the earlier tool-use
extraction reports remain in `.ai-qa/tool-use-final/<configuration>/`. The
editor fixture loads the current embedded-service sources in an isolated
project; the separate CI-native job rebuilds the fork's desktop editor and
runs the same fixture against it. The latest native reports are in
`.ai-qa/auto-plan-native-ci/.ai-qa/native-rendered/<configuration>/`. The delivered
APK passed package, ABI, signature and all 17 embedded-source comparisons; see
`.ai-qa/delivery-9a019f6.json`. The companion passed 9 tests and its TypeScript
build locally and in CI. Those tests use deterministic account runtimes.

The runtime suite exercises the real HTTP provider/tool/result loop against a
local protocol fixture, plus retry exhaustion, streaming failures, cancellation,
registry enforcement, replay/conflicting IDs, bounded results, concurrent-turn
rejection, checkpoint failure, and transcript repair. No live API key is used.

The editor fixture also checks structured planning, rejection of writes during
planning, tool-free intermediate answers, real execution, scene verification,
completed-plan restoration and strict Plan permissions. It drives
`panel._start_chat()` through the actual harness with a
deterministic provider. It creates a real scene node, reads the persisted run,
checks the completed transcript, undoes the scene change, and verifies Plan
blocks a model-requested mutation. These checks run through the normal chat
dispatcher, rather than calling only a mock tool executor.

Use the commands in [AI Assistant verification](AI_ASSISTANT.md#verification).
Desktop editor execution and rendered fixtures do not establish physical Android
suspend/resume behavior, device touch/keyboard input, or live subscription/model
support.

## Native coding tools

`godot_read_range` returns one-based line excerpts and a hash of the exact file
bytes read. `godot_search_code` performs bounded literal project searches with
file, line, column, and excerpt data; an optional `context` of 0–4 adds the
surrounding lines without repeating lines already shown for an adjacent match,
and one search result is capped at 24,000 excerpt characters. `godot_symbols`
adds the bounded, content-hash-cached declaration map described above. Hidden
folders, symlinks and private project paths retain the existing restrictions.

`godot_apply_patch` takes a project path, `expected_sha256`, and up to twenty
sequential `{old_text, new_text}` edits. Each anchor must occur exactly once,
including overlapping occurrences. No edit is written until all edits succeed.
The default is `dry_run: true`; applying requires modification permission.
Applying checks the version, refuses an unsaved open script, persists a recovery
copy, writes and verifies a temporary file, rechecks the original hash, and
renames the replacement into place. A stale/conflicting patch changes no source
bytes. Recovery continues to reject subsequent manual-file conflicts.

File changes request coalesced rescans after an active scan rather than starting
repeated scans during a batch. The editor fixture also saves its deliberately
edited test buffer before shutdown; completing assertions alone is not a passed
render run if the editor cannot exit normally.

`godot_script_diagnostics` reads a saved `.gd` file or validates an optional draft
through the new C++ `script_diagnostics` bridge. The bridge calls Godot's parser
and analyzer and returns validity, error locations, warnings and function names.
The tool adds the source hash. It does not save the draft or instantiate it.
An upstream editor without the bridge reports `native_bridge_unavailable`; it
does not substitute a guessed validation result. Native execution tests for valid
and invalid drafts are included in the fixture for a rebuilt fork.

Writes over `.gd` files now carry that parser verdict automatically.
`godot_write_file` and `godot_apply_patch` add a bounded `syntax` object with
`valid`, up to twenty line/column/message errors and `truncated`; a dry-run patch
validates the proposed text rather than the disk copy. A missing bridge leaves
the field absent instead of inventing a result, and warnings stay in
`godot_script_diagnostics`. The fixture covers the native verdict, an unparseable
write and the upstream no-bridge branch.

MCP tool results now preserve text and `structuredContent`, validate supported
output schemas, and propagate `isError` as `mcp_tool_error`. Up to four bounded
PNG/JPEG/WebP images are decoded and passed as model attachments, separate from
the JSON text transcript. Resource links and embedded text resources retain
their data; audio and unsupported binary resources report an explicit unsupported
content error. No remote operation is automatically retried on such an error.

Coordinated source edits use [file change sets and compensating rollback](AI_CHANGE_SETS.md). Preparation remains available in Plan mode; applying and restoring require write permission. These changes are included in APK `47cc26e`; physical Android acceptance is separate.
