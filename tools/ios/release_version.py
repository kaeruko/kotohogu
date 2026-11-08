#!/usr/bin/env python3
"""Advance the NEXT iOS release version after a successful App Store Connect upload.

TestFlight builds use the current pubspec version and the workflow run number.
Only a successful upload advances the PATCH number for the *next* build.
"""
import argparse
import json
from pathlib import Path
import re

VERSION_RE = re.compile(
    r"(?m)^version:[ \t]*(?P<major>0|[1-9][0-9]*)\."
    r"(?P<minor>0|[1-9][0-9]*)\."
    r"(?P<patch>0|[1-9][0-9]*)\+"
    r"(?P<build>[1-9][0-9]*)[ \t]*$"
)


def read_version(path):
    source = path.read_text(encoding="utf-8")
    matches = list(VERSION_RE.finditer(source))
    version_lines = re.findall(r"(?m)^version:", source)
    if len(matches) != 1 or len(version_lines) != 1:
        raise ValueError("pubspec.yaml requires exactly one version: MAJOR.MINOR.PATCH+BUILD line")
    match = matches[0]
    name = ".".join(match.group(part) for part in ("major", "minor", "patch"))
    return source, match, name, match.group("build")


def plan(path):
    _source, match, name, build = read_version(path)
    patch = int(match.group("patch"))
    next_name = f"{match.group('major')}.{match.group('minor')}.{patch + 1}"
    return {
        "current_ios_version": name,
        "source_version": f"{name}+{build}",
        "next_ios_version": next_name,
    }


def persist(path, expected_version, next_version):
    source, match, name, build = read_version(path)
    current = f"{name}+{build}"
    if current != expected_version:
        raise ValueError(f"Version changed during upload: expected {expected_version}, found {current}")
    planned_next = plan(path)["next_ios_version"]
    if next_version != planned_next:
        raise ValueError(f"Next iOS version must be {planned_next}, received {next_version}")
    replacement = f"version: {next_version}+{build}"
    updated = source[:match.start()] + replacement + source[match.end():]
    path.write_text(updated, encoding="utf-8", newline="")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pubspec", type=Path, default=Path("pubspec.yaml"))
    sub = parser.add_subparsers(dest="command", required=True)
    planning = sub.add_parser("plan")
    planning.add_argument("--format", choices=("json", "github-env"), default="json")
    persistence = sub.add_parser("persist")
    persistence.add_argument("--expected-version", required=True)
    persistence.add_argument("--next-version", required=True)
    args = parser.parse_args()
    if args.command == "plan":
        values = plan(args.pubspec)
        if args.format == "github-env":
            print("SOURCE_IOS_VERSION=" + values["source_version"])
            print("CURRENT_IOS_VERSION=" + values["current_ios_version"])
            print("NEXT_IOS_VERSION=" + values["next_ios_version"])
        else:
            print(json.dumps(values))
    else:
        persist(args.pubspec, args.expected_version, args.next_version)
        print(f"Updated {args.pubspec}: {args.expected_version} -> {args.next_version}")


if __name__ == "__main__":
    main()
