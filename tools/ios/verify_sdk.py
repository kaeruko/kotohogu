"""Require the iOS SDK used by the TestFlight build and upload workflows."""

import argparse
from pathlib import Path
import plistlib
import re


def require_ios_sdk(version: str) -> str:
    match = re.fullmatch(r"([0-9]+)(?:\.[0-9]+)*", version)
    if match is None or int(match[1]) < 27:
        raise ValueError(f"iOS SDK 27 or later is required; found {version!r}")
    return version


def verify_ipa_info(path: Path) -> str:
    with path.open("rb") as plist_file:
        info = plistlib.load(plist_file)
    sdk_name = info.get("DTSDKName") if isinstance(info, dict) else None
    if not isinstance(sdk_name, str) or not sdk_name.startswith("iphoneos"):
        raise ValueError(f"Expected a device iOS SDK in IPA DTSDKName; found {sdk_name!r}")
    return require_ios_sdk(sdk_name.removeprefix("iphoneos"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--sdk-version")
    source.add_argument("--ipa-info", type=Path)
    args = parser.parse_args()
    try:
        version = (verify_ipa_info(args.ipa_info) if args.ipa_info is not None
                   else require_ios_sdk(args.sdk_version))
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        parser.exit(1, f"{error}\n")
    print(version)
