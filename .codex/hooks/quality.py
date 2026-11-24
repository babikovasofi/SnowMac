#!/usr/bin/env python3
"""Translate Codex tool events into per-file checks and turn-local test evidence."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

HOOKS = Path(__file__).resolve().parent
EXTENSIONS = set("py ts tsx js jsx mjs cjs go rs rb java kt kts swift dart cs php scala c cc cpp h hpp tf sh".split())


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.DEVNULL)


def snapshot(root):
    names = git(root, "ls-files", "-z", "--cached", "--others", "--exclude-standard")
    result = {}
    for name in set(names.split(b"\0")) - {b""}:
        relative = Path(os.fsdecode(name))
        if relative.suffix[1:].lower() not in EXTENSIONS:
            continue
        if any(part.startswith(".env") or part == ".git" for part in relative.parts):
            continue
        if relative.parts[0] == ".codex" and relative.parts[1] not in {"hooks", "scripts"}:
            continue
        path = root / relative
        if path.resolve() == path and path.is_file():
            try:
                result[str(relative)] = hashlib.sha256(path.read_bytes()).hexdigest()
            except FileNotFoundError:
                continue
    return result


def read_state(path):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return {}


def save_state(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as handle:
        json.dump(value, handle)
    os.replace(handle.name, path)


def shell_hook(name, payload, root):
    run = subprocess.run(
        ["bash", str(HOOKS / name)], input=json.dumps(payload), text=True,
        capture_output=True, cwd=root, env={**os.environ, "HARNESS_ROOT": str(root)},
    )
    if run.returncode != 0:
        return {"reason": f"Hook {name} failed: {run.stderr.strip()}"}
    return json.loads(run.stdout) if run.stdout.strip() else {}


def test_command(root):
    run = subprocess.run(
        ["bash", "-c", '. "$1"; detect_test_cmd "$ROOT"', "quality", str(HOOKS / "lib/quality.sh")],
        cwd=root, env={**os.environ, "ROOT": str(root)}, text=True, capture_output=True,
    )
    return run.stdout.strip()


def emit(context, decision=None):
    result = {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": context}}
    if decision:
        result.update(decision="block", reason=context)
    print(json.dumps(result))


def main():
    event = json.load(sys.stdin)
    phase = sys.argv[1]
    root = Path(os.fsdecode(git(event["cwd"], "rev-parse", "--show-toplevel").strip())).resolve()
    state_dir = root / ".codex/sessions"
    turn = hashlib.sha256(f'{event["session_id"]}:{event["turn_id"]}'.encode()).hexdigest()
    turn_path = state_dir / f"{turn}.json"
    if phase == "stop":
        if event.get("stop_hook_active") or not turn_path.exists():
            print("{}")
            return
        state = read_state(turn_path)
        command = test_command(root)
        current = snapshot(root)
        turn_path.unlink(missing_ok=True)
        if command and state.get("tested") != current:
            print(json.dumps({"decision": "block", "reason":
                f"Run the project tests after the latest code edit: {command}. "
                "Cite the outcome, or give the reason testing is blocked."}))
        else:
            print("{}")
        return

    call = hashlib.sha256(f'{turn}:{event["tool_use_id"]}'.encode()).hexdigest()
    call_path = state_dir / f"{call}.pre.json"
    if phase == "before":
        save_state(call_path, snapshot(root))
        return
    if not call_path.exists():
        return
    before = read_state(call_path)
    call_path.unlink()
    after = snapshot(root)
    edited = sorted(path for path in before.keys() | after.keys() if before.get(path) != after.get(path))
    if not edited:
        if turn_path.exists() and event.get("tool_input", {}).get("command", "").strip() == test_command(root):
            response = str(event.get("tool_response", ""))
            if re.search(r"(?:Process exited with code|Exit code:)\s*0\b", response):
                save_state(turn_path, {"tested": after})
        return

    save_state(turn_path, {})
    payload = {**event, "session_id": call}
    reports = []
    failed = False
    for path in edited:
        payload["tool_input"] = {"file_path": str(root / path)}
        if path in after:
            result = shell_hook("lint-gate.sh", payload, root)
            if result.get("reason"):
                reports.append(result["reason"])
                failed = True

    # One test run per editing tool call, including deletions.
    payload["tool_input"] = {"file_path": str(root / edited[0])}
    result = shell_hook("verify.sh", payload, root)
    result_text = result.get("reason") or result.get("hookSpecificOutput", {}).get("additionalContext")
    if result_text:
        reports.append(result_text)
    receipt = state_dir / f"{call}.verify"
    if receipt.exists():
        if receipt.read_text().startswith("pass ") and snapshot(root) == after:
            save_state(turn_path, {"tested": after})
        receipt.unlink()
    if reports:
        emit("\n\n".join(reports), failed or result.get("decision") == "block")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError):
        if sys.argv[1] == "stop":
            print("{}")
