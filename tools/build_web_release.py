"""Deterministic Godot Web release export, stamping, and verification."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GAME_ROOT = ROOT / "web" / "game"
INNER_HTML = GAME_ROOT / "index.html"
OUTER_HTML = ROOT / "web" / "index.html"
MANIFEST_PATH = ROOT / "web" / "build-manifest.json"
GODOT = ROOT / "tools" / "godot-4.7" / "Godot_v4.7-stable_win64_console.exe"
CONFIG_PATTERN = re.compile(r"const GODOT_CONFIG = (\{.*?\});")
HASHED_ASSET_PATTERN = re.compile(
    r"^index\.[0-9a-f]{12}\.(?:pck|wasm|audio\.worklet\.js|audio\.position\.worklet\.js)$"
)
WORKLET_SOURCES = {
    "audio_worklet": "index.audio.worklet.js",
    "audio_position_worklet": "index.audio.position.worklet.js",
}


def project_version() -> str:
    text = (ROOT / "project.godot").read_text(encoding="utf-8")
    match = re.search(r'^config/version="([^"]+)"', text, re.MULTILINE)
    if not match:
        raise RuntimeError("project.godot has no application/config version")
    return match.group(1)


def build_id(version: str) -> str:
    return version.split("-", 1)[1] if "-" in version else version


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def runtime_bundle_digest(wasm_sha: str, worklet_shas: dict[str, str]) -> str:
    descriptor = json.dumps(
        {"wasm": wasm_sha, **worklet_shas},
        separators=(",", ":"),
        sort_keys=True,
    ).encode("ascii")
    return hashlib.sha256(descriptor).hexdigest()


def export_release() -> None:
    subprocess.run(
        [
            str(GODOT),
            "--headless",
            "--path",
            str(ROOT),
            "--export-release",
            "Web",
            str(INNER_HTML),
        ],
        cwd=ROOT,
        check=True,
    )


def install_host_handshake(html: str) -> str:
    if "hostMessageSource = 'riding-dirty-game'" not in html:
        engine_line = "const engine = new Engine(GODOT_CONFIG);"
        handshake = """const engine = new Engine(GODOT_CONFIG);

(function () {
	const hostMessageSource = 'riding-dirty-game';
	function notifyHost(type, detail = {}) {
		if (window.parent !== window) {
			window.parent.postMessage({ source: hostMessageSource, type, ...detail }, window.location.origin);
		}
	}
"""
        if engine_line not in html:
            raise RuntimeError("Godot shell no longer exposes the expected Engine constructor")
        html = html.replace(engine_line + "\n\n(function () {", handshake, 1)

    if "notifyHost('engine-error')" not in html:
        needle = "\t\tconsole.error(err);\n"
        if needle not in html:
            raise RuntimeError("Godot shell failure handler changed")
        html = html.replace(needle, needle + "\t\tnotifyHost('engine-error');\n", 1)

    if "notifyHost('engine-progress'" not in html:
        needle = "\t\t\t'onProgress': function (current, total) {\n"
        if needle not in html:
            raise RuntimeError("Godot shell progress handler changed")
        html = html.replace(
            needle,
            needle + "\t\t\t\tnotifyHost('engine-progress', { current, total });\n",
            1,
        )

    if "notifyHost('engine-ready')" not in html:
        needle = "\t\t\tsetStatusMode('hidden');\n"
        if needle not in html:
            raise RuntimeError("Godot shell success handler changed")
        html = html.replace(needle, needle + "\t\t\tnotifyHost('engine-ready');\n", 1)
    return html


def content_address_assets(html: str) -> tuple[str, dict[str, object]]:
    wasm_source = GAME_ROOT / "index.wasm"
    pck_source = GAME_ROOT / "index.pck"
    worklet_sources = {
        key: GAME_ROOT / filename for key, filename in WORKLET_SOURCES.items()
    }
    required_sources = [wasm_source, pck_source, *worklet_sources.values()]
    missing_sources = [source.name for source in required_sources if not source.is_file()]
    if missing_sources:
        raise RuntimeError(
            "Expected fresh unversioned Godot runtime assets after export: "
            + ", ".join(missing_sources)
        )

    wasm_sha = digest(wasm_source)
    pck_sha = digest(pck_source)
    worklet_shas = {key: digest(source) for key, source in worklet_sources.items()}
    runtime_sha = runtime_bundle_digest(wasm_sha, worklet_shas)
    wasm_name = f"index.{runtime_sha[:12]}.wasm"
    pck_name = f"index.{pck_sha[:12]}.pck"
    executable_name = wasm_name.removesuffix(".wasm")
    worklet_names = {
        key: f"{executable_name}{source.name.removeprefix('index')}"
        for key, source in worklet_sources.items()
    }

    for candidate in GAME_ROOT.iterdir():
        if candidate.is_file() and HASHED_ASSET_PATTERN.fullmatch(candidate.name):
            candidate.unlink()
    wasm_source.replace(GAME_ROOT / wasm_name)
    pck_source.replace(GAME_ROOT / pck_name)
    for key, source in worklet_sources.items():
        source.replace(GAME_ROOT / worklet_names[key])

    config_match = CONFIG_PATTERN.search(html)
    if not config_match:
        raise RuntimeError("Unable to locate GODOT_CONFIG in exported shell")
    config = json.loads(config_match.group(1))
    config["executable"] = executable_name
    config["mainPack"] = pck_name
    config["fileSizes"] = {
        wasm_name: (GAME_ROOT / wasm_name).stat().st_size,
        pck_name: (GAME_ROOT / pck_name).stat().st_size,
    }
    serialized = json.dumps(config, separators=(",", ":"), sort_keys=True)
    html = html[: config_match.start(1)] + serialized + html[config_match.end(1) :]
    manifest: dict[str, object] = {
        "wasm": {
            "file": wasm_name,
            "sha256": wasm_sha,
            "runtime_bundle_sha256": runtime_sha,
            "bytes": config["fileSizes"][wasm_name],
        },
        "pck": {"file": pck_name, "sha256": pck_sha, "bytes": config["fileSizes"][pck_name]},
    }
    for key, filename in worklet_names.items():
        destination = GAME_ROOT / filename
        manifest[key] = {
            "file": filename,
            "sha256": worklet_shas[key],
            "bytes": destination.stat().st_size,
        }
    return html, manifest


def stamp_wrapper(version: str, release_id: str) -> None:
    html = OUTER_HTML.read_text(encoding="utf-8")
    # Replace the prior named release slug while preserving cache-stamp dates
    # such as ``20260715-`` that may prefix it in query strings.
    html = re.sub(r"[a-z][a-z0-9-]*-v\d+", release_id, html, flags=re.IGNORECASE)
    version_number = re.search(r"v(\d+)$", release_id, re.IGNORECASE)
    if version_number:
        html = re.sub(r"V\d+", f"V{version_number.group(1)}", html)
    OUTER_HTML.write_text(html, encoding="utf-8", newline="\n")

    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    manifest["version"] = version
    manifest["build"] = release_id
    MANIFEST_PATH.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def verify_release() -> None:
    html = INNER_HTML.read_text(encoding="utf-8")
    match = CONFIG_PATTERN.search(html)
    if not match:
        raise RuntimeError("Final shell has no GODOT_CONFIG")
    config = json.loads(match.group(1))
    executable_name = str(config["executable"])
    assets = [
        f"{executable_name}.wasm",
        str(config["mainPack"]),
        f"{executable_name}.audio.worklet.js",
        f"{executable_name}.audio.position.worklet.js",
    ]
    for asset in assets:
        if not HASHED_ASSET_PATTERN.fullmatch(asset) or not (GAME_ROOT / asset).is_file():
            raise RuntimeError(f"Release asset is not content-addressed: {asset}")
    if "notifyHost('engine-ready')" not in html or "notifyHost('engine-error')" not in html:
        raise RuntimeError("Host readiness handshake missing from final shell")
    pck_bytes = (GAME_ROOT / str(config["mainPack"])).read_bytes()
    banned_test_markers = (
        b"features/testing",
        b"runtime_smoke_test",
        b"competitive_services_probe",
        b"mesa_mx_smoke",
        b"mesa_mx_visual_probe",
    )
    leaked_markers = [marker.decode("ascii") for marker in banned_test_markers if marker in pck_bytes]
    if leaked_markers:
        raise RuntimeError(f"Test-only resources leaked into the release PCK: {leaked_markers}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip-export", action="store_true", help="Stamp an existing fresh Godot export")
    parser.add_argument("--skip-tests", action="store_true", help="Do not run delivery regression tests")
    args = parser.parse_args()

    if not args.skip_export:
        export_release()
    version = project_version()
    release_id = build_id(version)
    html = INNER_HTML.read_text(encoding="utf-8")
    html, asset_manifest = content_address_assets(html)
    html = install_host_handshake(html)
    INNER_HTML.write_text(html, encoding="utf-8", newline="\n")
    MANIFEST_PATH.write_text(
        json.dumps({"version": version, "build": release_id, "assets": asset_manifest}, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    # stamp_wrapper reads and extends the just-created manifest.
    stamp_wrapper(version, release_id)
    verify_release()
    if not args.skip_tests:
        subprocess.run(
            [sys.executable, "-m", "unittest", "tests.test_web_delivery", "-v"],
            cwd=ROOT,
            check=True,
        )
    print(f"WEB RELEASE READY: {version} ({release_id})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
