# Godot AI · Android editor fork

Personal Android editor fork based on **Godot 4.7.2**, with an editor-only AI module
and its own built-in agent harness. It supports direct cloud/local providers,
MCP, generation profiles and an optional personal subscription companion.
Open the **AI Assistant** tab next to **Asset Store**, or
**Editor Settings → General → AI Assistant**, to configure it.

[Download the verified Android ARM64 debug APK](https://github.com/JDscript1/godot-ai-android/actions/runs/40764656531/artifacts/12850107387)
(GitHub Actions artifact, source `090b939`, delivered 28 October 2026).

See [AI Assistant setup and verification](docs/AI_ASSISTANT.md). This is an early
development build; live subscription/generation and physical Android validation
are tracked separately from automated checks.

[Implementări, verificări și planul proiectului](PROGRES_SI_PLAN.md) este
documentul de progres actualizat după fiecare etapă importantă.
[Prioritățile următoare](docs/AI_ROADMAP.md) includ validarea pe dispozitiv,
GitHub cu token personal și profilurile de export 3D.
[Auditul interfeței](docs/AI_UI_AUDIT.md) urmărește încadrarea și efectele reale
ale butoanelor din chat și istoric.
[TODO-ul agentului](TODO_AGENT.md) urmărește problemele demonstrate în probe,
prioritățile și criteriile de verificare înaintea închiderii fiecărui punct.
[Suita de 50 de use case-uri](docs/AI_AGENT_USE_CASES.md) oferă cerințe de trimis,
precondiții, criterii și ordinea probelor manuale, cu rezultate urmărite separat.
[Cele 47 de teste rămase](docs/AI_AGENT_REMAINING_TESTS.md) sunt pregătite pentru
copiere în chat, cu mesajele ulterioare și intervențiile utilizatorului separate.

The [built-in harness](docs/AI_HARNESS.md) runs direct API agent sessions inside
Godot without Termux, a console, or an external agent runtime. The linked APK
includes Auto / Default / Plan, structured task progress and the compact composer selector;
its tested source is identified above.

The linked APK includes [project knowledge, unified diagnostics, adaptive
recovery and acceptance evidence](docs/AI_HARNESS_INTELLIGENCE.md), plus
[coordinated file changes and compensating rollback](docs/AI_CHANGE_SETS.md), and
[editor panel access and coverage](docs/AI_PANEL_ACCESS.md).
The compiled native editor passed 732 checks on each of five layouts; physical
Android use and live-provider behavior remain separate verification steps.

The harness now [compacts long sessions automatically](docs/AI_HARNESS.md):
when the sent context nears the model limit or an overflow occurs, it summarizes
the older range, keeps the newest turn verbatim and persists the summary while
the full history stays on disk. The switch is in Settings → General and is
included in the linked APK.

Summaries are validated and saved before replacing active context. Long ranges
are processed in model-sized batches, with output space reserved; failed or
cancelled compaction preserves the previous context.

The chat now exposes the latest turn's recovery directly: **Undo** restores the
files changed by the answer and returns its prompt to the composer, while
**Regenerează** restores the same files and submits the prompt again. Queued
messages render as removable cards above the composer, each completed answer
shows elapsed time, tokens and an estimated cost, persisted reasoning folds into
a collapsed Thinking block, Find searches the loaded conversation, and 15
seconds without output shows a stall warning. These changes are included in the
linked APK.

The queue scrolls within a bounded height so the conversation and composer stay
visible when many messages are pending.

The harness now continues a response that the provider stopped at its output
limit, merging the continuation and any tool calls into one assistant turn
without inserting a user message. The new `godot_symbols` tool maps top-level
GDScript declarations for bounded, content-hash-cached code navigation. Write
approvals for an existing file now show per-hunk checkboxes over a unified diff,
so only the selected changes are applied. Writes over `.gd` files also return an
automatic syntax verdict from the native parser, code search accepts surrounding
context lines, and the tool results of one step share a bounded batch budget with
a tail preview. These changes are included in the linked APK.

Playtest children now probe the running game directly: `playtest_act` measures
probe expressions before and after held inputs, `playtest_watch` tracks
expressions and signals, and a per-turn chat console shows the measured evidence
and verdict. These additions are included in the linked APK.

Approvals add a session-scoped **Permite mereu** grant per tool, revocable from
Settings → General and never bypassing Plan's read-only rule. A completed
proposal card can hand its exact steps to Auto (**Implementează planul**) or back
into Plan for editing (**Ajustează**). An independent audit's six playtest
findings are fixed: the C++ bridge compiled for the native editor and Android, probes run
with `const_calls_only`, Stop cancels an active act with a distinct result, the
input guard keeps releasing held inputs, expiry reports `timed_out` with
`until_met=false`, and identical acts are refused only when their measured
results stop changing. These fixes are included in the linked APK.

[Interactive Plan](docs/AI_INTERACTIVE_PLAN.md) adds selectable clarification
questions, custom answers and conversation recovery in the linked APK.
Automated rendered checks passed; physical touch and live-model choices remain
separate acceptance tests.

[Installed Android workflow testing](docs/AI_DEVICE_WORKFLOW.md) uses a temporary
test-project plugin to submit tasks to the actual APK agent and collect its logs,
without rebuilding or extracting keys. The first physical Runware/Terrain3D probe
reproduced a result-recovery failure and did not complete the map.

[Automatic agent tariffs](docs/AI_MODEL_PRICING.md) are included in the linked APK:
key paste discovers models, with input/output token rates, a six-hour public
price cache, source dates and offline retention.

The start screen and project editor use the same **AI Assistant** tab name.
Missing cloud endpoints recover from the selected provider catalog, including
DeepSeek; explicitly invalid server addresses are shown for correction.
Existing saved keys and model lists survive repairs to a blank endpoint.

[Agent behavior and local connection checks](docs/AI_BEHAVIOR_TESTS.md) document
the changes included in this APK: resumable turns, duplicate-generation protection,
new-message steering and one-action LM Studio/Ollama connection. Source, rendered and live checks are
reported separately.

[Live API behavior evaluation](docs/AI_API_EVALUATION.md) exercises the production
chat and editor tools with a real DeepSeek model in an isolated project, and
records call traces and activity journals. It documents the reproduced reflection
bug, the source fixes and the limits of testing outside the Android APK.

The APK includes a [collapsible activity bar](docs/AI_ACTIVITY_DRAWER.md)
above the chat input, showing plan progress, background tasks and tool outcomes.

The bottom dock has a dedicated minimize arrow. Expanding chat from its header
also collapses Output and the side docks; restoring recovers the previous panel
and chat placement while preserving diagnostics and the message draft.
The compiled editor passed the layout checks; Android touch validation follows installation.

The APK includes a [persistent embedded Linux runtime](docs/AI_LINUX_RUNTIME.md)
with native Android PRoot and a pinned Debian ARM64 filesystem. The base prepares
automatically when the assistant starts, including in the project manager;
Integrations shows **Linux active** after successful verification. Python,
Node.js/npm, Git, ripgrep and Blender remain optional utility installs.
No separate Termux app or pasted setup commands are required for this backend.
The direct-provider harness remains in Godot; third-party CLI harness adapters
and full Blender operation still need separate integration and device validation.

An optional [independent Ziva preview](docs/AI_ZIVA.md) has its own top tab beside
AI Assistant, both in the editor and before project selection.
Its `ziva-preview` Android distribution has a separate application ID and installer;
the current editor stays installed. The preview downloads the complete official
Ziva plugin and an official Godot 4.7.2 Linux ARM64 editor, runs the latter headless
under PRoot beside the Android editor, and shows the official Ziva UI in a WebView
on a discovered loopback port. The two agents keep separate prompts, keys, provider
settings and state; Ziva cannot call our native editor tools. The separate APK
`0fc625a9` passed the Android build and the full runtime/native-editor checks,
and its verified Ziva installer is available in Android Download alongside the standard APK.
The Ziva tab expands the workspace, restores the previous editor layout on exit,
and keeps its compact actions within narrow windows. The official login page
has been observed on Android after repairing the shipped Debian dependencies;
the new layout, authentication and a live model workflow still need device QA.

The Ziva preview APK's complete Linux package, native service, agent, Asset Store
and 37 embedded scripts were verified before replacing the Ziva Download installer.
Python/Node/Git/ripgrep passed real development controls; execution inside the
installed Godot APK for these optional tools still needs device verification.
The [older Termux backend](docs/AI_TERMUX_BLENDER.md) remains in source for
compatibility, and the [runtime history](docs/AI_EMBEDDED_BLENDER_RUNTIME.md)
records the earlier experimental stages.

> **Unofficial integration.** This Android Ziva preview is an independent
> project and is not affiliated with or endorsed by Ziva.sh. The Ziva plugin and
> runtime remain proprietary; they are downloaded from the official release and
> are not redistributed by this repository.

The APK includes [3D preview controls and image-purpose rules](docs/AI_ASSET_RULES.md):
touch/mouse orbit with directional buttons, distinct reconstruction/sprite/texture
prompts, alpha verification and an optional Runware background-removal tool.

In **Generation**, select Images or 3D, then paste the provider key to load a
searchable model catalog before saving. Every model has a price column showing
USD/credits, a starting price, an estimate or an explicitly variable/unpublished
tariff. Runware prices load from live schemas; shared provider keys work across
image and mesh profiles. The compiled catalog UI and all embedded sources were verified.

The APK also includes [control settings, integrations and project skills](docs/AI_INTEGRATIONS.md),
plus [native Meshy, Tripo and image generation](docs/AI_GENERATION.md).
It also includes multi-format 3D export, grouped cloud/local profiles, explicit
LAN discovery and personal-token GitHub integration.
Automated generation/auth checks use HTTP fixtures; paid-provider and physical Android
validation remain separate.

[Chat file previews, visual editor control and Store tools](docs/AI_CHAT_FILES_AND_EDITOR_CONTROL.md)
are included in this APK; build/device evidence is tracked in
the progress document.

Dezvoltare verificată a jocurilor: [instrumente, exemple, dovezi și limite](docs/engineering-workflows.md).

# Godot Engine

<p align="center">
  <a href="https://godotengine.org">
    <img src="misc/logo/logo_outlined.svg" width="400" alt="Godot Engine logo">
  </a>
</p>

## 2D and 3D cross-platform game engine

**[Godot Engine](https://godotengine.org) is a feature-packed, cross-platform
game engine to create 2D and 3D games from a unified interface.** It provides a
comprehensive set of [common tools](https://godotengine.org/features), so that
users can focus on making games without having to reinvent the wheel. Games can
be exported with one click to a number of platforms, including the major desktop
platforms (Linux, macOS, Windows), mobile platforms (Android, iOS), as well as
Web-based platforms and [consoles](https://godotengine.org/consoles).

## Free, open source and community-driven

Godot is completely free and open source under the very permissive [MIT license](https://godotengine.org/license).
No strings attached, no royalties, nothing. The users' games are theirs, down
to the last line of engine code. Godot's development is fully independent and
community-driven, empowering users to help shape their engine to match their
expectations. It is supported by the [Godot Foundation](https://godot.foundation/)
not-for-profit.

Before being open sourced in [February 2014](https://github.com/godotengine/godot/commit/0b806ee0fc9097fa7bda7ac0109191c9c5e0a1ac),
Godot had been developed by [Juan Linietsky](https://github.com/reduz) and
[Ariel Manzur](https://github.com/punto-) for several years as an in-house
engine, used to publish several work-for-hire titles.

![Screenshot of a 3D scene in the Godot Engine editor](https://raw.githubusercontent.com/godotengine/godot-design/master/screenshots/editor_tps_demo_1920x1080.jpg)

## Getting the engine

### Binary downloads

Official binaries for the Godot editor and the export templates can be found
[on the Godot website](https://godotengine.org/download).

### Compiling from source

[See the official docs](https://docs.godotengine.org/en/latest/engine_details/development/compiling)
for compilation instructions for every supported platform.

## Community and contributing

Godot is not only an engine but an ever-growing community of users and engine
developers. The main community channels are listed [on the homepage](https://godotengine.org/community).

The best way to get in touch with the core engine developers is to join the
[Godot Contributors Chat](https://chat.godotengine.org).

To get started contributing to the project, see the [contributing guide](CONTRIBUTING.md).
This document also includes guidelines for reporting bugs.

## Documentation and demos

The official documentation is hosted on [Read the Docs](https://docs.godotengine.org).
It is maintained by the Godot community in its own [GitHub repository](https://github.com/godotengine/godot-docs).

The [class reference](https://docs.godotengine.org/en/latest/classes/)
is also accessible from the Godot editor.

We also maintain official demos in their own [GitHub repository](https://github.com/godotengine/godot-demo-projects)
as well as a list of [awesome Godot community resources](https://github.com/godotengine/awesome-godot).

There are also a number of other
[learning resources](https://docs.godotengine.org/en/latest/community/tutorials.html)
provided by the community, such as text and video tutorials, demos, etc.
Consult the [community channels](https://godotengine.org/community)
for more information.

[![Code Triagers Badge](https://www.codetriage.com/godotengine/godot/badges/users.svg)](https://www.codetriage.com/godotengine/godot)
[![Translate on Weblate](https://hosted.weblate.org/widgets/godot-engine/-/godot/svg-badge.svg)](https://hosted.weblate.org/engage/godot-engine/?utm_source=widget)
