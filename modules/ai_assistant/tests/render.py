"""Render and exercise the AI panel in isolated desktop and narrow editor projects."""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--proot", action="store_true")
    parser.add_argument("--scenario", choices=["all", "engineering", "harness", "dock", "files", "terrain", "activity", "preview", "blender", "providers", "startup", "linux", "ziva", "panels", "generation", "approval", "todo", "compact", "workflow", "chat", "presentation", "inspections", "scene_paths", "planning", "intelligence", "changesets", "debugger", "panel_access", "chat_lifecycle"], default="all")
    parser.add_argument("--output", default=".ai-qa/rendered")
    parser.add_argument("--only", choices=["desktop", "narrow", "wide", "phone_landscape", "phone_compact"])
    parser.add_argument("--timeout-seconds", type=float, default=180,
                        help="Wall-clock budget per isolated editor run, independent of agent execution")
    args = parser.parse_args()
    if args.timeout_seconds <= 0:
        parser.error("--timeout-seconds must be positive")
    source = Path(__file__).resolve().parent.parent
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    for name, resolution in (("desktop", "1280x900"), ("narrow", "480x900"), ("wide", "1920x1080"), ("phone_landscape", "2048x922"), ("phone_compact", "1280x900")):
        if args.only and name != args.only:
            continue
        destination = output / name
        destination.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="godot-ai-render-") as directory:
            fixture = Path(directory) / "project"
            shutil.copytree(source / "tests/fixture", fixture,
                            ignore=shutil.ignore_patterns(".godot", "ai_test_*"))
            if name.startswith("phone_"):
                config = Path(directory) / "config/godot"
                config.mkdir(parents=True)
                (config / "editor_settings-4.7.tres").write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\ninterface/editor/appearance/display_scale = 4\n')
            environment = {
                "GODOT_AI_QA_SOURCE": str(source),
                "GODOT_AI_QA_SCENARIO": args.scenario,
                "GODOT_AI_QA_OUTPUT": str(destination),
                "XDG_CONFIG_HOME": str(Path(directory) / "config"),
                "XDG_DATA_HOME": str(Path(directory) / "data"),
            }
            if args.scenario == "terrain" and os.environ.get("GODOT_AI_TERRAIN3D_ZIP"):
                environment["GODOT_AI_TERRAIN3D_ZIP"] = os.environ["GODOT_AI_TERRAIN3D_ZIP"]
            command = ["xvfb-run", "-a", "-s", f"-screen 0 {resolution}x24 -ac",
                       args.godot, "--editor", "--rendering-method", "gl_compatibility",
                       "--audio-driver", "Dummy", "--resolution", resolution,
                       "--path", str(fixture)]
            if args.proot:
                command = ["proot-distro", "login", "--shared-home", "debian", "--", "env",
                           *(f"{key}={value}" for key, value in environment.items()), *command]
            report_path = destination / "editor-report.json"
            report_path.unlink(missing_ok=True)
            log_path = destination / "editor.log"
            try:
                with log_path.open("w") as stream:
                    process = subprocess.Popen(command, env={**os.environ, **environment},
                                               stdout=stream, stderr=subprocess.STDOUT,
                                               start_new_session=True)
                    try:
                        process.wait(timeout=args.timeout_seconds)
                    except subprocess.TimeoutExpired:
                        try:
                            os.killpg(process.pid, signal.SIGTERM)
                            process.wait(timeout=5)
                        except (ProcessLookupError, subprocess.TimeoutExpired):
                            try:
                                os.killpg(process.pid, signal.SIGKILL)
                            except ProcessLookupError:
                                pass
                            process.wait()
                        raise
                    result = process
            except subprocess.TimeoutExpired:
                print(log_path.read_text())
                raise SystemExit(f"{name}: editor verification timed out")
            log = log_path.read_text()
            if "SCRIPT ERROR:" in log or "ERROR: Cannot save GDScript file" in log:
                print(log)
                raise SystemExit(f"{name}: embedded script or save regression")
            if result.returncode or not report_path.exists():
                print(log)
                raise SystemExit(f"{name}: editor verification failed ({result.returncode})")
            report = json.loads(report_path.read_text())
            print(f"{name}: {report['checks']} checks, {len(report['failures'])} failures")
            if not report["checks"] or report["failures"]:
                raise SystemExit(1)


if __name__ == "__main__":
    main()
