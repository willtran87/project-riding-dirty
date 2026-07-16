#!/usr/bin/env python3
"""Run the deterministic Riding Dirty release-quality gate.

The default gate covers the highest-risk production contracts. ``--full`` runs
every focused ``*_probe.tscn`` in addition to the representative activity
smokes. Commands stream their own evidence and the first failing command stops
the release with a non-zero exit code.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GODOT_CANDIDATES = (
    ROOT / "tools" / "godot-4.7" / "Godot_v4.7-stable_win64_console.exe",
    ROOT / "tools" / "godot-4.7" / "Godot_v4.7-stable_win64.exe",
)
QUICK_PROBES = (
    "persistence_hardening_probe.tscn",
    "production_settings_probe.tscn",
    "reduced_motion_accessibility_probe.tscn",
    "race_difficulty_quality_probe.tscn",
    "web_runtime_budget_probe.tscn",
    "opponent_challenge_probe.tscn",
    "settings_navigation_probe.tscn",
    "touch_riding_controls_probe.tscn",
    "results_navigation_probe.tscn",
    "player_race_metrics_isolation_probe.tscn",
    "progression_pacing_probe.tscn",
    "race_reputation_pacing_probe.tscn",
    "career_systems_probe.tscn",
    "competitive_services_probe.tscn",
    "race_feature_contract_probe.tscn",
    "race_gate_launch_probe.tscn",
    "race_pack_launch_probe.tscn",
    "race_integrity_tracker_probe.tscn",
    "race_integrity_branch_probe.tscn",
    "closed_loop_seam_probe.tscn",
    "lap_crossing_continuity_probe.tscn",
    "racecraft_rules_probe.tscn",
    "racecraft_integration_probe.tscn",
    "full_game_meta_integration_probe.tscn",
    "route_authority_probe.tscn",
    "geometry_clipping_probe.tscn",
    "terrain_ribbon_clearance_probe.tscn",
    "terrain_profile_spatial_index_probe.tscn",
    "pine_dressing_asset_probe.tscn",
    "physical_route_traversability_probe.tscn",
    "full_race_lifecycle_probe.tscn",
    "bike_dynamics_probe.tscn",
)
ACTIVITY_SMOKES = (
    "CIRCUIT",
    "PINE_ENDURO",
    "MESA_MX",
    "FREESTYLE",
    "DISCOVERY",
)
RENDERED_PROBES = {
    "quarry_base_ribbon_visual_probe.tscn",
    "quarry_gate8_chase_visual_probe.tscn",
    "quarry_route_visual_probe.tscn",
}
EXTERNAL_PROBES = {
    "competitive_services_probe.tscn": ROOT / "features" / "competitive" / "competitive_services_probe.tscn",
}


def _godot_path(explicit: str | None) -> Path:
    if explicit:
        candidate = Path(explicit).expanduser().resolve()
        if candidate.is_file():
            return candidate
        raise FileNotFoundError(f"Godot executable does not exist: {candidate}")
    for candidate in GODOT_CANDIDATES:
        if candidate.is_file():
            return candidate
    raise FileNotFoundError("Godot 4.7 executable was not found under tools/godot-4.7")


def _run(label: str, command: list[str], timeout_seconds: int) -> None:
    print(f"\n=== {label} ===", flush=True)
    try:
        result = subprocess.run(command, cwd=ROOT, timeout=timeout_seconds, check=False)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f"{label} timed out after {timeout_seconds}s") from error
    if result.returncode != 0:
        raise RuntimeError(f"{label} failed with exit code {result.returncode}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--full", action="store_true", help="run every focused Godot probe")
    parser.add_argument("--skip-activities", action="store_true", help="skip representative playable smokes")
    parser.add_argument("--godot", help="explicit Godot 4.7 console executable")
    parser.add_argument("--timeout", type=int, default=360, help="per-command timeout in seconds")
    args = parser.parse_args()

    try:
        godot = _godot_path(args.godot)
        headless = [str(godot), "--headless", "--path", str(ROOT)]
        rendered = [
            str(godot), "--path", str(ROOT), "--windowed",
            "--resolution", "2560x1600", "--position", "0,0",
        ]
        _run("Godot parser/editor scan", headless + ["--editor", "--quit"], args.timeout)

        probe_dir = ROOT / "features" / "testing"
        probe_names = (
            sorted(
                [path.name for path in probe_dir.glob("*_probe.tscn")]
                + list(EXTERNAL_PROBES)
            )
            if args.full
            else list(QUICK_PROBES)
        )
        for probe_name in probe_names:
            probe_path = EXTERNAL_PROBES.get(probe_name, probe_dir / probe_name)
            if not probe_path.is_file():
                raise FileNotFoundError(f"Required probe is missing: {probe_path}")
            resource = "res://" + probe_path.relative_to(ROOT).as_posix()
            # Focused probes must exercise the complete production path.  The
            # runtime smoke flag intentionally suppresses costly live systems
            # such as race-integrity updates and would make those assertions
            # either impossible or falsely green.
            command = rendered + [resource] if probe_name in RENDERED_PROBES else headless + [resource]
            if args.full and probe_name == "physical_route_traversability_probe.tscn":
                command += ["--", "--three-lines"]
            _run(probe_name, command, args.timeout)

        if not args.skip_activities:
            for activity in ACTIVITY_SMOKES:
                _run(
                    f"activity smoke {activity}",
                    headless + ["--", "--smoke-test", f"--activity={activity}"],
                    args.timeout,
                )
    except (FileNotFoundError, RuntimeError) as error:
        print(f"\nQUALITY GATE FAILED: {error}", file=sys.stderr, flush=True)
        return 1

    print(
        f"\nQUALITY GATE PASS: probes={len(probe_names)} "
        f"activities={0 if args.skip_activities else len(ACTIVITY_SMOKES)} full={args.full}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
