# Godot AI Android

This fork starts at `4.7.2-stable` (`ed1daf0bf001b61586d9930840f2f1394092c079`).
The Android application ID is `com.jdscript.godotai` (debug builds append `.debug`).
It installs alongside upstream Godot. Engine and third-party license notices are retained.

## Configuration

Open **Editor Settings → General → AI Assistant**, or select the **AI Assistant**
tab at the top right of the editor, next to **Asset Store**. Its **Setări** button
opens the same global configuration window.

- **Furnizori:** select an issuer or paste a distinctive API key. Generic keys such
  as `sk-...` require an issuer selection. OpenCode Zen uses one API key and its
  model catalog declares whether each model uses chat, Responses, Anthropic
  messages or Gemini generation; the harness routes the selected model automatically.
  OpenCode can restrict free-tier models to its own client, so another MCP/API
  client may receive HTTP 403 even with a valid key; paid models are not affected.
  The current source queries models automatically after saving and can refresh an empty catalog from chat. The delivered APK still requires the separate test/list-models action. Manual model
  IDs remain available for servers without a listing endpoint. Cloud and local/self-hosted
  services/profiles have separate headings. Advanced hosting overrides support a
  self-hosted server behind a public HTTPS domain.
- **Abonamente:** use **Continue with ChatGPT** for the native SIWC flow. Claude,
  Copilot and Kimi use the optional companion on your own computer/server.
- **Generare:** choose Runware, Meshy, Tripo, OpenAI Images or an existing ComfyUI
  server. Import a workflow exported in API format, bind its prompt/reference fields
  and output node, then validate the server. PNG and self-contained GLB 2.0 are supported.
  See [native generation adapters](AI_GENERATION.md) for direct-provider capabilities.
  Runware's public catalog lists model IDs; it does not validate your credentials.
  Its image form supports text-to-image. For 3D, TRELLIS.2 requires a reference image;
  Rodin, Meshy, Tripo and Hunyuan accept text or the supported reference binding.
  Models requiring extra inputs, such as a segmentation mask, need a configured
  ComfyUI workflow. A cancelled wait retains the remote job for later retrieval.
- **MCP:** add a Streamable HTTP endpoint and optional Bearer token. For stdio,
  configure the process in the companion and connect to its `/mcp/<name>` URL.
- **General:** YOLO, center/left/right chat placement and completion sounds.
- **Integrări:** GitHub cu token personal și selecție de repository, Blender CLI desktop și [configurare Blender prin Termux pe Android](AI_TERMUX_BLENDER.md) inclusă în APK; validarea fizică a Intent-ului este separată.
  Skills și Sarcini au pagini principale proprii. Configurarea GitHub este descrisă în
  [integrations](AI_INTEGRATIONS.md).
- **AGENT.MD:** edit project memory in `AGENT.md`; existing `AGENTS.md` is preserved.

The current APK is `a23d260`, including control/integrations/generation and
[chat files, previews, editor control, Store and real diff](AI_CHAT_FILES_AND_EDITOR_CONTROL.md).
It also includes the subsequent harness/local-connection fixes, activity drawer,
3D preview controls, image-purpose rules and optional Termux/Blender setup.
The Android Blender card has one install action, automatic verification and agent
activation, then a compact **Blender Active** status and **Uninstall Blender**.
Diagnostics and worker output are in Journal; package removal preserves containers
and user files. Terminal-only Termux variants still require pasting the private
bootstrap before setup continues automatically.
Delivery evidence is recorded in [the project progress document](../PROGRES_SI_PLAN.md).

HTTP is opt-in per local connection. `127.0.0.1` means this Android device; a server
on your computer needs its reachable LAN address or authenticated HTTPS endpoint.
No inference runtime or generation model is installed automatically.

## Local servers over Wi-Fi

The following simplified flow is included in the current APK;
see [behavior and connection checks](AI_BEHAVIOR_TESTS.md) for its evidence.
Select LM Studio, Ollama or llama.cpp, enter the computer's Wi-Fi IP and press
**Conectează**. A bare IP such as `192.168.1.20` adds the service's usual port
(1234, 11434 or 8080) and `/v1` automatically. The same action saves the profile,
checks the catalog and selects an available loaded model when reported.
The token field is optional for an unauthenticated local server; advanced settings
are not needed for this flow. An explicit `http://` URL uses its specified port,
or standard port 80 when omitted, rather than guessing a service port.

Use the computer's LAN IP, not `127.0.0.1`, which means the current device.
A custom port/path or authenticated HTTPS address can be entered manually.
Local/self-hosted hosting can be selected explicitly for custom public domains.
The model list reports loaded state and active context when the native server
metadata is available. Ollama uses `/api/tags` and `/api/ps`; LM Studio adds its
model metadata to the OpenAI-compatible catalog. Catalog connectivity and the
speed/quality of a loaded model are separate checks. Slow active streams can
continue within a bounded inference budget; a stalled model does not trigger
automatic duplicate inference after a response timeout.

**Caută servere în rețea…** runs an explicit native discovery, never on startup:
up to two private IPv4 /24 segments derived from local interfaces, ports
11434/1234/8080, 48 concurrent TCP probes with bounded timeouts, then at most
24 `/v1/models` checks. It sends no API keys and saves/connects to no server until
you select and save it. Auth-protected endpoints, other subnets/ports, IPv6,
VPN/interface ordering or unsupported interface enumeration may require a manual
address. An empty model catalog can still identify a reachable server. This is
bounded probing, not guaranteed mDNS discovery or detection of every local host.
The dialog can stop discovery; no Termux, shell or external runtime is involved.

On the computer, enable LM Studio's **Serve on Local Network** or configure
Ollama's `OLLAMA_HOST=0.0.0.0:11434` and restart its server. Restrict access to your
trusted network, use server authentication where available, and configure the
host firewall. Client isolation/guest Wi-Fi can block peers even on the same SSID.
The editor does not alter the computer's server/firewall settings.
The full cloud/local service selector stays visible for existing profiles; local
profiles show their API/LAN address directly. Discovery prioritizes the device's
own private IPv4 address and falls back to the local address list when interface
enumeration omits it. If scanning fails, paste the exact API URL shown by LM
Studio and use **Conectează**. Both peers may use a phone's hotspot; mobile data
itself is not required for local model requests. Peer access and the current LAN
IP still matter, and reconnecting can change that IP. A model loaded in LM
Studio does not by itself enable LAN serving. The editor does not silently scan
or reconnect to a different discovered host using a saved token.

Sources: [LM Studio LAN hosting](https://lmstudio.ai/docs/developer/core/server/serve-on-network),
[Ollama network binding](https://docs.ollama.com/faq#how-do-i-configure-ollama-server),
[Ollama model catalog](https://docs.ollama.com/api/tags),
[Ollama loaded models](https://docs.ollama.com/api/ps).

## Execution and recovery

The chat exposes **Auto / Default / Plan**. Default is initially selected for
new configurations; existing Plan conversations retain read-only access. Auto
requires a concise executing plan before modifying/external operations. Default
works directly for simple tasks and plans complex ones. The mode menu contains
only those three choices. General's **YOLO · editări automate** defaults
to off: Auto and Default ask for each modifying/external operation. Enabling YOLO permits
automatic operations; Plan remains read-only regardless of YOLO. Applying a plan
switches to Auto and retains the permission preference. Preferences save immediately.

For complex work the model publishes structured task steps through `task_update`.
Planning is read-only; the model must publish the executing phase before writes.
Auto and Default continue unfinished execution plans without a total step ceiling. Stop,
actual blockers and repeated attempts without progress still stop execution. A plan-only
request remains a proposal. This is model-directed task planning, not a local
complexity classifier or a guarantee of a provider's coding quality.

Scene/property edits use Godot Undo where supported. File replacements retain
recovery copies and journal indices. Generic method calls may have effects that
Godot cannot undo; they are always treated as modifications. Internal/native
methods that are not reflected require dedicated adapters; this release does not
claim every private engine function has a tested AI wrapper.

Stopping cancels native HTTP calls and asks companion runtimes to interrupt.
Remote generation may continue at the provider; generation jobs retain their IDs
and can be refreshed after an Android suspend/restart. A workflow running on a
shared ComfyUI server is never globally interrupted on behalf of another job.

## Architecture

The Romanian [project progress record](../PROGRES_SI_PLAN.md) tracks implemented
work, verification, the delivered APK, and the remaining plan. It is updated at
each substantial AI development/build/delivery milestone.

The [built-in agent harness](AI_HARNESS.md) runs direct-provider turns inside
Godot, including independent child sessions. Its model/tool loop does not require
Termux, a console, an external agent SDK, or the optional companion. It owns
streaming events, bounded model retries, cancellation, result deduplication, and
checkpoint handling. The model endpoint itself remains a separately configured
cloud or local service. Companion-backed subscriptions and MCP stdio retain their
existing optional external hosts.

Direct runs discover specialized tools through `tool_search`/`tool_describe`.
Coding tools include bounded line reads/search, version-checked exact patches
with preview/recovery, and a native GDScript diagnostics bridge. MCP results
preserve structured data and model images and expose execution errors. See the
[harness contract](AI_HARNESS.md) for supported schemas and bridge requirements.

`modules/ai_assistant` contains the C++ editor plugin, global settings inspector,
secret-store bridge and embedded GDScript services. Scripts are injected into the
editor in dependency order and are not installed into `res://` on disk. No project
addon, hosted gateway, API key or token is embedded in the APK or game exports.

Android credentials are encrypted with AES-GCM under a non-exportable Android
Keystore key. Desktop development builds use encrypted files and an owner-only
local key. Public profiles hold IDs, endpoints, model metadata and workflow
configuration. Histories, generation artifacts and operation journals are local
and separated by project. Normal context and logs redact stored credentials.

The companion's selected upstream files and hashes are recorded in
`tools/ai-companion/PROVENANCE.json`; copied MIT notices remain beside them.
Original Godot Agent/Hydra-Go-3D worktrees were not edited.

## Verification

The 2026-10-23 harness source is included in the APK listed below. See
[the harness contract and verification scope](AI_HARNESS.md).

Run the embedded-runtime tests with an upstream or forked 4.7.2 editor binary:

```sh
python modules/ai_assistant/tests/run.py --godot /absolute/path/to/godot
# Requires xvfb-run and a working OpenGL software driver on headless Linux:
python modules/ai_assistant/tests/render.py --godot /absolute/path/to/godot
cd tools/ai-companion
npm ci
npm test
npm run build
```

On Termux with a Debian proot installation, add `--proot` to the Python commands
and use the official Linux arm64 editor path. Rendered evidence is saved under
`.ai-qa/rendered/{desktop,narrow,wide,phone_landscape,phone_compact}` with screenshots, reports and editor logs.

The `Godot AI Android` GitHub workflow also compiles the native Android arm64
editor and verifies the APK signature, package metadata, ABI and SHA-256 hash.
Only the phone/tablet APK `android_editor-android-debug.apk` is delivered.
The personal fork uses the Actions secret `GODOT_AI_DEBUG_KEYSTORE` to preserve
the debug signing identity across updates. Other forks may configure their own
base64-encoded development keystore, or receive an ephemeral runner debug key.
For local builds, `GODOT_AI_DEBUG_KEYSTORE_FILE` selects a development keystore
with the standard `androiddebugkey` alias and `android` debug passwords. CI also
compares the APK certificate with that keystore before uploading an artifact.
This is a development build; no production signing key is included in source.

Evidence below describes delivered APK `a23d260`. Full history and local paths
are in [the progress record](../PROGRES_SI_PLAN.md).

| Area | Current verification |
| --- | --- |
| Runtime, protocol adapters, file revisions, diff and model capability policies | 427 assertions locally; 422 in CI, which omits the five optional local Blender checks. HTTP providers use deterministic fixtures |
| Upstream editor | 371 CI checks in each of five configurations: desktop, narrow, wide, phone landscape and phone compact |
| Compiled native fork | 381 CI checks in each configuration, including actual mouse input, GLB pixels, offscreen rendering, native addon installation/activation/removal, Undo, diagnostics and editor-specific Blender verification recovery |
| Blender backend | 26 backend/HTTP/bootstrap tests passed in CI, including a real pasted command starting an authenticated worker; 22 local Godot-to-real-Blender assertions passed in manual mode with the Android boundary substituted |
| Blender setup UI | 67 checks at phone scaling in CI, including the single install action, persistent setup intent, editor import verification, automatic agent activation, scoped uninstall, old worker upgrade, permission/manual fallback and visible pairing hints |
| Companion | Nine deterministic tests and TypeScript build passed |
| APK | ARM64, package and persistent certificate verified; all 27 embedded scripts, the Blender worker and bootstrap match the compiled commit byte for byte; Termux permission, receiver, Android classes, JNI entry and Play Store destinations present |
| Device and live services | Physical Android UI/touch/Keystore/microphone/suspend and real vision/subscription/generation providers remain separate checks. The public Store request returned HTTP 403 locally; Store execution was tested with a fixture addon |

[All three CI jobs passed](https://github.com/JDscript1/godot-ai-android/actions/runs/40173817612).
Native export/provider/integration settings and dock screenshots were inspected
in earlier deliveries, including compact left placement and 3D workspace overlap.
This iteration's simplified Blender card was inspected locally at desktop and
phone scaling; the current compiled native fork passed the rendered checks above.
Image/3D viewer, references and diff screenshot inspection is also recorded in
the earlier delivery history.
Godot may enforce a larger editor window than the narrow virtual display.
Desktop rendering does not establish physical Android behavior.
The user's Android logs confirm manual Termux pairing and Blender 4.3.2 export/render
in the previous APK. The resulting valid cube GLB reproduced a validator bug:
editor imports contain `ImporterMeshInstance3D`, which the previous check ignored.
This APK accepts both editor and runtime mesh instances with actual surfaces and
can recover the completed verification. That recovery still requires checking
in the newly installed Android APK.

On 2026-10-21, the public Runware catalog was also fetched successfully through
the module's real Godot HTTP transport (six 3D choices after filtering the
mask-dependent model). This establishes catalog access only; no account or
credit-consuming generation was used for that check.

The verified APK source is `a23d26033c4553621540bdfd32312ccb71617846`.
Download its [ARM64 artifact](https://github.com/JDscript1/godot-ai-android/actions/runs/40173817612/artifacts/12591950511).
The APK is 145,350,402 bytes; its SHA-256 is
`b230284b1bf6b07a998e540baebcb36c20cde68a8efe04cf816f808efe5e640f`.
The delivered phone copy is `Download/Godot-AI-Android-arm64-debug.apk`,
with a matching `.sha256` file, updated on 25 October 2026 at 08:48:52 CET.
Its checksum, package, ABI, persistent signature and all embedded sources were
checked locally. It atomically replaced `cd1acda`; Download contains one fork
installer. Unrelated downloads remain untouched.
The persistent development certificate SHA-256 is
`2e0a80969c099f7ff72bfe0c0cd33d98ebdd0e64bbf9729294df0b11665fcab5`.
Later documentation-only commits do not change the APK's tested source.

Native desktop verification runs under Xvfb/Mesa. Nonfatal Vulkan-probe and X11
window warnings can occur in this virtual display; this is not physical-device
rendering proof. The test fails on embedded-script execution/save errors.
Playtest checks use a small fixture scene and direct bridge calls. Actual model-led
playtests, subscription authentication and hardware microphone recording require
configured live services/device checks.

The native tool layer exposes scene and script editing, files with recovery,
resources/materials, project/editor settings, animation players, run/stop,
Output/Debugger text and semantic editor controls. Reflection supplies methods,
properties and signals for classes and discovered object handles. This provides
general editor access, while unreflected/private C++ operations need explicit
adapters. The test counts above cover the exercised paths, not every engine method.

## Official protocol references

- [Godot Android builds](https://docs.godotengine.org/en/stable/engine_details/development/compiling/compiling_for_android.html)
- [Sign in with ChatGPT](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [ChatGPT plan inference limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
- [ComfyUI routes](https://docs.comfy.org/development/comfyui-server/comms_routes)
- [Runware task polling](https://runware.ai/docs/models-api/task-polling)
- [Runware TRELLIS.2](https://runware.ai/docs/models/microsoft-trellis-2)
- [Runware Rodin Gen-2](https://runware.ai/docs/models/hyper3d-rodin-gen-2)
- [MCP transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)

## Native chat workspace

The current source also adds an Agent tab to the project manager, before a
project is opened. It reuses the native chat, provider settings and credential
vault in a separate host. Project editing tools stay unavailable until a project
opens. A single-project launch can carry the active start-screen conversation
into a new project conversation while preserving existing project history.
This addition has local script/render and C++ syntax checks; it is not yet in
the delivered APK. Evidence is in [the progress document](../PROGRES_SI_PLAN.md).

The AI main screen is registered immediately after Asset Store. Scene,
FileSystem and Inspector docks stay available. The native chat uses a graphite
surface and violet/blue gradient; history collapses when the available workspace
is narrower than 900 logical pixels. The message column is limited to 760 logical
pixels. There are no embedded web pages.

Conversations are stored per project, with search, favorites, archive, rename,
fork, confirmed deletion and Markdown export through a save-file dialog. Deletion
does not require archiving first; cancel preserves the transcript. History opens
as a separate page in narrow docks. Session drafts are scoped to conversations.
See [UI audit](AI_UI_AUDIT.md) for behavior checks and validation limits.
Existing `history.json` is imported
once and preserved. Images are cached as separate private files. Switching the
provider/model keeps the conversation and labels responses with their origin;
provider-specific signed/reasoning blocks are retained only for their originating
profile and model. Model selection groups API, subscription and local profiles.

The searchable settings window has General, Providers, Subscriptions, Generation,
MCP, Integrations, Journal, AGENT.MD, Voice and Playtesting pages. `@` opens project
file/folder references, `$` opens scene-node references and `/` lists commands.
Images can be attached to supported multimodal providers. Context counters use
provider-reported usage when available. `/compact` writes a continuation summary
while preserving the original conversation.

Plan mode permits inspection and presents an Apply plan button, which switches
to Auto. The YOLO/confirmation preference remains in effect.
Messages sent during a turn enter a queue with their own provider/model/reasoning
and Auto/Default/Plan selection; the active turn keeps its original mode. Stop pauses the queue; `/resume` continues it and
`/steer <instructions>` interrupts the current turn before using the new request.
AGENTS.md guidance and editable project memories are included in context.

Explore and General children inspect independently and return proposed changes;
the parent applies project writes. Cloud profiles allow two children; local and
companion profiles allow one. Companion protocol 2 creates a separate SDK object
and session for each child, so a parent waiting for a tool can receive its result.
Authentication remains shared through the existing local account stores.

The Changes/Undo action shows before/after file contents and offers restoration.
It refuses restoration when file hashes or native scene Undo history changed
subsequently. Generic method calls, external operations and arbitrary setting
changes are not reversible checkpoints.

The compact header contains the conversation title, history, new conversation,
expanded workspace and settings. Model selection lives beside the message input.
It opens a bottom drawer inside the chat: provider groups → that provider's
models → reasoning. Search filters providers or the selected provider's models.
The choice is applied only after selecting reasoning; Back, outside click and
Escape allow cancellation. A separate reasoning chip reopens the current model's
levels. Only catalog-declared levels are offered, with automatic as the default;
models without declared levels offer automatic alone. Selection stays attached
to queued messages. Wide composers place the chips inline; narrow ones give
them their own row above the action buttons.

User messages form small right-aligned bubbles;
assistant messages use the main reading column. The composer starts at one line
and grows to a bounded height. Image and project references appear as removable
chips, with image thumbnails. Empty task/reference rows reserve no space.
Stop appears only while working. The mode menu contains Auto/Default/Plan only. Context filling has its own ring and
percentage in the bottom toolbar; details appear on hover. Empty conversations show one welcome prompt.

Assistant messages have compact provider identities and native Markdown for
headings, emphasis, inline code, lists, quotes, tables and validated HTTP(S) links.
Model text is never interpreted as BBCode or HTML. Fenced code sits in a rounded
panel with a compact copy action. Message actions use 32-unit controls. Structured
plans appear as collapsible cards in the conversation, showing pending/current/
completed steps and distinct proposal, verification, blocked or paused states.
A completed proposal does not falsely mark implementation steps as completed.

Streaming updates the existing message blocks at a bounded rate. Fenced code has
syntax colors, its language and a copy action during streaming as well as after
completion. Finishing a response preserves its widgets and layout. Message actions
use compact icons and a secondary menu. The Changes view highlights actual old
and new file contents in red and green and retains conflict-aware restoration.
Operations appear in expandable activity groups with details hidden initially.
Graphite surfaces, violet accents and vector icons are shared across chat and
settings. Provider identities use downloaded brand marks from Lobe Icons and the
upstream llama.cpp repository; action icons use Lucide. All 61 SVGs, pinned URLs,
hashes and full licenses are kept in `modules/ai_assistant/icons/`. The artwork
is embedded in the native module, rendered at editor scale and cached offline.
Qwen regions share their brand mark; custom endpoints have a generic code icon.
Composer controls use 32 logical pixels in height, 16 pixel icons, 12 pixel text
and reduced padding. Model/reasoning chips fit their labels, bounded at 150/104
logical pixels, instead of stretching across the composer. New live messages use
a short opacity transition; the earlier reduce-motion preference remains supported
in stored configuration. History loading does not animate each old message.

For each verified delivery, `misc/scripts/deliver_ai_android.py` installs
`Download/Godot-AI-Android-arm64-debug.apk` atomically and removes superseded
Godot AI installers and their checksum files from that folder. It verifies the
workflow revision/result, artifact checksum, signature, package, ABI and every
embedded script before delivery. Other apps/downloads are preserved. Delivery uses this stable-name policy; the previous installer remains usable
until a new artifact has passed verification. Three delivery tests cover failed
copy protection, verified replacement and scoped cleanup names.

Settings navigation measures category names using the actual font size. Narrow
windows use a category dropdown instead of shortening the left-side labels.
Provider profiles use a compact selector, provider emblem and connection badge. A saved
profile or manual model is shown as unverified until a catalog request succeeds;
the last successful verification is stored with the profile. API keys, Save and
Verify actions stay in the basic form. Profile name, URL, HTTP and manual model
are in an advanced section, opened for local/custom endpoints. Saved keys stay
masked and can be retained by leaving the field empty. Other saved lists size to
their item count, and empty lists are hidden. Voice and generation show fields
for the selected backend. Settings feedback is separate from chat progress.
Subscription settings show one service at a time:
ChatGPT has its native login view; Claude, Copilot and Kimi have their companion
view with connection details collapsed. The service name is selected rather than
typed manually. Render verification includes 2048x922 and 1280x900 at 150% editor
scale to cover the Android screenshots that revealed clipped navigation.
Verification also renders populated conversations, streamed code, activity,
actual file differences and settings with a saved provider, instead of relying
on an empty chat. Live account/model, hardware voice, Android keyboard, rotation
and device touch checks remain separate from these deterministic desktop cases.

## Playtest and voice boundaries

Playtest uses the fork's native debugger bridge to inspect the running scene,
capture its actual viewport and send bounded InputMap/key/mouse/touch events.
It never substitutes an editor screenshot for a game frame. The default budget
is 30 steps / 180 seconds. Held input is released on Stop and after a native
2.2-second watchdog; each requested hold is limited to two seconds. Screenshots
and child reports are retained in the project's private AI data directory.
Use a vision-capable model in Playtesting settings or a model whose live catalog
declares image input. A disconnected debugger or unsupported model is reported
as blocked rather than a successful playtest.

Voice supports Android SpeechRecognizer, preferring an installed on-device
service, and a separately configured Whisper-compatible transcription endpoint.
Endpoint recording is capped at 60 seconds and encoded as mono 16 kHz PCM WAV.
The transcription key is stored separately from chat credentials. Transcripts
are inserted into the composer for editing and require an explicit send action.
Stopping or suspending cancels microphone capture. Android permissions, the
installed recognition service, hardware audio and live endpoints still require
physical-device validation; desktop rendering does not establish those results.
