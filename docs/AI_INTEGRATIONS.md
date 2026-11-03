# Control, integrations and project skills

Current source, compiled-package and delivery evidence are recorded in
[PROGRES_SI_PLAN.md](../PROGRES_SI_PLAN.md). GitHub uses a personal access token.

## Control

The work mode menu contains Auto, Default and Plan only. General contains YOLO, chat
placement (center/left/right), and completion sounds with a preview action.
Preferences save immediately. YOLO defaults to off: Auto and Default ask before each
modifying/external operation. Enabling YOLO permits automatic operations;
Plan remains read-only. Applying a plan never changes the YOLO preference.
Execution and history budgets remain internal, outside General.

The native plugin moves the existing panel through Godot's `EditorDock` manager;
it does not create another conversation or another agent. Returning to center
restores the main tab. Docked chat stays available beside the editor, and opening
its tab restores the prior workspace. Moving it is refused during active work or
voice capture. The top expand action temporarily centers docked chat and restores
its prior dock on collapse, retaining the saved position. Docked expansion also
waits for active work to finish. Preferences survive restart. The C++ bridge compiled and ran in the native fork editor fixture: 324 checks
in each of five display configurations, including real dock moves. Physical
Android interaction and sound output remain unverified.

A small ring and percentage stay visible in the bottom toolbar. Input usage is
compared with a known model capacity; estimated values are marked and unknown
capacity displays a dash. Hovering gives token details. Zero-valued catalog
capacity does not overwrite an actual capacity supplied by the provider. Usage
from a different selected model/conversation is not reused as current context.

The completion chime is generated as a short native PCM stream. Sounds default
to off and play on successful final completion, once the message queue is empty;
failed/cancelled/unfinished execution does not play the completion sound. The
preview action works independently of the preference. Hardware playback needs
separate device verification.

## Integrations

Integrations contains GitHub and desktop Blender CLI. Skills and saved tasks
have separate main settings pages immediately below Integrations.
MCP servers and image/3D generation have their own settings pages. The duplicate
Services card and its shortcuts have been removed in source after APK `db5343b`.

GitHub and Blender configuration is stored per project in the editor's private
`projects/<hash>/integrations.json`. GitHub tokens use the existing encrypted
vault/Android Keystore and never enter that JSON, model instructions or logs.
Changing repositories in one project does not configure another project.

- GitHub uses native HTTP, without `git`, `gh` or a shell. Enter a personal access
  token, choose a repository from the paginated account list or enter
  `owner/repository`, then press **Verifică**. Verification checks `/user` and, when
  selected, the repository. **Deconectează** removes the token from the local vault.
  Choose token permissions for the repositories you intend to access; creating
  an issue requires write permission. No OAuth app or Client ID is needed.
- Saving a token enables the GitHub integration. A token is required even for
  public-repository reads through the agent. Repository selection alone does not
  grant the agent permission to publish.
- `github_read` inspects repository metadata, branches, issues, pull requests and
  file/directory contents. Lists are paginated and bounded; file content includes
  its revision. `github_create_issue` publishes only for an explicit request under
  Auto/Default/Plan and YOLO/confirmation rules. Git clone, commits, push and PR
  creation are not implemented by these adapters.
- On Windows/Linux, Blender CLI appears when Blender is already installed.
  Select its executable and verify the version. `blender_run` starts Blender
  directly with an argument array, no shell, using background/factory mode,
  disabled automatic file scripts and an explicit project Python script.
  Optional `.blend` input is project-scoped. A nonblocking process loop captures
  bounded output, supports Stop/timeout and reports nonzero/Python exit status
  as failure. Scripts have Blender's desktop filesystem access.
- On Android, Blender 4.3.2 ARM64 and its Debian dependencies are signed into
  the APK. **Integrări → Blender** extracts them from the offline repository;
  Termux and package downloads are not used. `blender_status` reports the
  measured version, `blender_prepare` performs the local preparation, and
  `blender_run` executes project Python with `/workspace` mounted and
  `GODOT_AI_OUTPUT_DIR` scoped to the project. Process output, timeout,
  cancellation, generated paths and exit status are returned to the agent.
- Existing manually launched saved tasks remain on the Sarcini page.
  This adds no autonomous scheduler.

Authentication uses [GitHub personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).
The adapters follow [GitHub repository contents](https://docs.github.com/en/rest/repos/contents),
[GitHub issues](https://docs.github.com/en/rest/issues/issues) and
[Blender CLI arguments](https://docs.blender.org/manual/en/5.4/advanced/command_line/arguments.html).

## Skills and memory

The Skills page lists portable project instructions in
`res://.godot_ai/skills/<id>/SKILL.md`. The manager creates, edits, enables,
disables and deletes skills; deletion uses native file recovery. Revisions are
checked before updates/removal, and project-path/symlink rules still apply.
Enable flags are local per project. Disabled skills are absent from agent context
and agent reads. Skills are text instructions; they never execute automatically
or grant additional tool permissions.

The agent receives the enabled catalog and uses `skill_list`, `skill_read` and
`skill_save` through normal discovery and permission checks. It can save a concise
reusable workflow after checking actual results. It cannot save a skill in Plan
mode or bypass confirmation when YOLO is off. Learning quality remains dependent
on the configured model; tool tests do not establish that every self-written
procedure is correct.

AGENT.MD edits `res://AGENT.md`, included alongside existing `AGENTS.md` guidance.
Legacy private memories prefill the editor when the project file is absent;
the file is created only on explicit Save or an authorized memory tool call.
Save checks the original revision and preserves recovery; Reload refreshes an
externally edited file. Existing `AGENTS.md` is preserved.

Jurnal is a read-only console with chronological request/tool/result/settlement
entries, live follow, search and copy. Stored entries are redacted. The display
is bounded to prevent large tool results from freezing the editor; the project
journal retains its existing 1,000-entry limit.

## Verification boundary

Local runtime checks include a deterministic GitHub HTTP fixture and a real
Blender 4.3.2 process on Debian ARM64: Python → GLB → Godot import, Python errors,
cancellation and timeout. A separate unauthenticated request through the native
adapter read the public `godotengine/godot` repository. Personal-token tests use
local HTTP fixtures for missing/invalid tokens, account verification and repository listing.
No live issue was created and no private GitHub account was connected. Rendered editor fixtures cover
permissions, skills/recovery, memory conflicts, context, settings and dock moves.
Exact counts and evidence are recorded in [PROGRES_SI_PLAN.md](../PROGRES_SI_PLAN.md).
Windows execution, physical Android and actual audio playback remain unverified. The current source/build/delivery status is recorded in the progress document.
