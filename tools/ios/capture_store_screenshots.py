#!/usr/bin/env python3
"""Capture real Simulator app frames for the App Store with only stdlib.

This script deliberately never uses Apple signing keys or the user's app data.
It runs the separate lib/store_screenshots.dart entrypoint compiled by CI.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time

PAGES = ("home", "missions", "town", "history")
DEVICES = (
    (
        "iphone_dynamic_island_medium",
        ("iPhone 16 Pro", "iPhone 17 Pro", "iPhone 15 Pro", "iPhone 14 Pro"),
        (1206, 2622),
    ),
    (
        "ipad_13_inch",
        (
            "iPad Pro 13-inch (M4)",
            "iPad Pro 13-inch (M5)",
            "iPad Air 13-inch (M3)",
            "iPad Air 13-inch (M2)",
        ),
        (2064, 2752),
    ),
)
MARKER = "kotohogu-store-ready.txt"


def cmd(*args: str, check: bool = True, env: dict[str, str] | None = None) -> str:
    result = subprocess.run(
        args, check=check, text=True, capture_output=True, env=env
    )
    if result.returncode and check:
        raise RuntimeError(
            f"Command failed ({result.returncode}): {' '.join(args)}\n"
            f"{result.stdout[-2000:]}\n{result.stderr[-4000:]}"
        )
    return result.stdout.strip()


def choose_ios_runtime() -> str:
    runtimes = json.loads(cmd("xcrun", "simctl", "list", "runtimes", "-j"))[
        "runtimes"
    ]
    available = [
        r for r in runtimes
        if r.get("isAvailable", True)
        and str(r.get("identifier", "")).startswith(
            "com.apple.CoreSimulator.SimRuntime.iOS-"
        )
    ]
    if not available:
        raise RuntimeError("No available iOS Simulator runtime is installed")

    def version(runtime: dict) -> tuple[int, ...]:
        return tuple(int(p) for p in re.findall(r"\d+", runtime["version"]))

    return max(available, key=version)["identifier"]


def device_type(names: tuple[str, ...]) -> tuple[str, str]:
    types = json.loads(cmd("xcrun", "simctl", "list", "devicetypes", "-j"))[
        "devicetypes"
    ]
    for wanted in names:
        for entry in types:
            if entry["name"] == wanted:
                return entry["identifier"], entry["name"]
    raise RuntimeError(
        "Missing exact-size simulator type: " + ", ".join(names)
    )


def dimensions(image: Path) -> tuple[int, int]:
    data = cmd("sips", "-g", "pixelWidth", "-g", "pixelHeight", str(image))
    width = re.search(r"pixelWidth:\s*(\d+)", data)
    height = re.search(r"pixelHeight:\s*(\d+)", data)
    if not width or not height:
        raise RuntimeError(f"Unable to inspect image dimensions: {image}: {data}")
    return int(width.group(1)), int(height.group(1))


def await_rendered_page(marker: Path, page: str) -> None:
    deadline = time.monotonic() + 65
    last_status = "<not written>"
    while time.monotonic() < deadline:
        if marker.exists():
            last_status = marker.read_text(encoding="utf-8").strip()
            if last_status == f"ready:{page}":
                return
            if last_status != f"booting:{page}":
                raise RuntimeError(
                    f"Unexpected screenshot status for {page!r}: {last_status!r}"
                )
        time.sleep(0.5)
    raise TimeoutError(
        f"App never rendered {page!r}: last status={last_status!r}; "
        f"expected marker {marker}. Check diagnostics artifact."
    )


def save_diagnostics(
    udid: str, output: Path, marker: Path, page: str, reason: Exception
) -> None:
    """Always save the visible Simulator frame and device logs on failure."""
    target = output / "diagnostics"
    target.mkdir(parents=True, exist_ok=True)
    status = marker.read_text(encoding="utf-8") if marker.exists() else "<absent>"
    text = [
        f"Page: {page}",
        f"Failure: {type(reason).__name__}: {reason}",
        f"Marker: {marker}",
        f"Status: {status}",
    ]
    screenshot = target / f"{page}_on_failure.png"
    proc = subprocess.run(
        ["xcrun", "simctl", "io", udid, "screenshot", "--type=png", str(screenshot)],
        capture_output=True, text=True, timeout=25, check=False,
    )
    text.append(f"Screenshot: {proc.returncode}: {proc.stdout} {proc.stderr}")
    # These are simulator's own logs, not Apple private signing artifacts.
    try:
        log = subprocess.run(
            [
                "xcrun", "simctl", "spawn", udid, "log", "show", "--last", "2m",
                "--style", "compact", "--predicate", 'process == "Runner"',
            ],
            capture_output=True, text=True, timeout=30, check=False,
        )
        (target / f"{page}_runner_log.txt").write_text(
            log.stdout[-150000:] + "\n" + log.stderr[-12000:],
            encoding="utf-8",
        )
        text.append(f"Simulator logs: exit={log.returncode}")
        print(log.stdout[-3500:], flush=True)
    except (subprocess.TimeoutExpired, OSError) as error:
        text.append(f"Could not read Simulator logs: {error}")
    (target / f"{page}_failure.txt").write_text(
        "\n".join(text) + "\n", encoding="utf-8"
    )
    print("\n".join(text), flush=True)


def capture(
    udid: str,
    bundle_id: str,
    output: Path,
    expected_size: tuple[int, int],
) -> list[dict]:
    app_data = Path(
        cmd("xcrun", "simctl", "get_app_container", udid, bundle_id, "data")
    )
    marker = app_data / "tmp" / MARKER
    output.mkdir(parents=True, exist_ok=True)
    metadata = []
    for index, page in enumerate(PAGES, start=1):
        marker.unlink(missing_ok=True)
        env = dict(os.environ)
        # Runtime setting means the *same installed app* renders all four pages.
        env["SIMCTL_CHILD_KOTOHOGU_CAPTURE_SCREEN"] = page
        try:
            launch_result = cmd(
                "xcrun", "simctl", "launch", "--terminate-running-process",
                udid, bundle_id, env=env,
            )
            print(f"Launched {page}: {launch_result}; awaiting UI...", flush=True)
            await_rendered_page(marker, page)
        except Exception as error:
            save_diagnostics(udid, output, marker, page, error)
            raise
        time.sleep(0.8)

        # Native Simulator screenshot includes its genuine status bar.
        raw = output / f"_raw_{index:02d}_{page}.png"
        result = output / f"{index:02d}_{page}.jpg"
        cmd("xcrun", "simctl", "io", udid, "screenshot", "--type=png", str(raw))
        # Apple accepts JPEG; unlike RGBA PNGs it cannot contain an alpha channel.
        cmd(
            "sips", "-s", "format", "jpeg", "-s", "formatOptions", "95",
            str(raw), "--out", str(result),
        )
        raw.unlink()
        actual_size = dimensions(result)
        if actual_size != expected_size:
            raise RuntimeError(
                f"{result}: expected {expected_size}, got {actual_size}; "
                "this is not an App Store Connect screenshot size"
            )
        if result.stat().st_size < 60000:
            raise RuntimeError(
                f"{result} is suspiciously small ({result.stat().st_size} bytes)"
            )
        print(f"Captured {result} at {actual_size}", flush=True)
        metadata.append(
            {
                "page": page,
                "file": result.name,
                "width": actual_size[0],
                "height": actual_size[1],
                "bytes": result.stat().st_size,
            }
        )
    if len(metadata) != 4:
        raise RuntimeError("Missing screens in screenshot output")
    return metadata


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not args.app.is_dir():
        parser.error(f"Simulator .app not found: {args.app}")

    plist = args.app / "Info.plist"
    bundle_id = cmd(
        "/usr/libexec/PlistBuddy", "-c", "Print :CFBundleIdentifier", str(plist)
    )
    runtime = choose_ios_runtime()
    manifest: dict[str, object] = {
        "note": (
            "Simulator screenshots of the actual Kotohogu Flutter screens "
            "with example mission progress. Not an actual player's data."
        ),
        "runtime": runtime,
        "devices": {},
    }
    args.output.mkdir(parents=True, exist_ok=True)
    for folder, names, expected_size in DEVICES:
        type_id, type_name = device_type(names)
        print(f"Starting {type_name} ({runtime})", flush=True)
        udid = cmd(
            "xcrun", "simctl", "create", f"kotohogu-store-{folder}",
            type_id, runtime,
        )
        try:
            cmd("xcrun", "simctl", "boot", udid)
            cmd("xcrun", "simctl", "bootstatus", udid, "-b")
            cmd("xcrun", "simctl", "ui", udid, "appearance", "light")
            cmd(
                "xcrun", "simctl", "status_bar", udid, "override",
                "--time", "9:41", "--batteryState", "charged",
                "--batteryLevel", "100",
            )
            cmd("xcrun", "simctl", "install", udid, str(args.app))
            files = capture(
                udid, bundle_id, args.output / folder, expected_size
            )
            manifest["devices"][folder] = {"model": type_name, "files": files}
        finally:
            cmd("xcrun", "simctl", "shutdown", udid, check=False)
            cmd("xcrun", "simctl", "delete", udid, check=False)

    (args.output / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (args.output / "README.txt").write_text(
        "ことほぐ App Store Connect用スクリーンショット\n"
        "iphone_dynamic_island_medium: 1206 x 2622 px（縦）\n"
        "ipad_13_inch: 2064 x 2752 px（縦）\n"
        "各フォルダーの 01_home ～ 04_history をそのまま登録できます。\n"
        "AppleのPNGアルファチャンネル制限を避けるため、JPEG形式です。\n"
        "撮影は実際のFlutter画面ですが、達成記録と住民は見本データです。\n"
        "提出前に各画像を開き、文字切れやレイアウトを確認してください。\n",
        encoding="utf-8",
    )
    print("All 8 screenshots validated", flush=True)


if __name__ == "__main__":
    main()
