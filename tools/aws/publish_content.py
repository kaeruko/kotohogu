"""Publish immutable CMS snapshots using AWS CLI v2 (no Python AWS SDK).

Required: an existing CloudFormation stack from tools/aws/content-stack.yaml.
Only the final 'current.json' object is mutable. Upload and verify all release
objects first; failures stop without changing the active release pointer.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "dialogue_cms"))
from server import runtime_catalog, runtime_sprite_path  # noqa: E402
from characters import DIRECTIONS  # noqa: E402

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
FRAMES = ("idle_front_01.png", "clap_front_01.png", "clap_front_02.png")
SPRITE_DIRECTIONS = tuple(DIRECTIONS)
IMMUTABLE = "public,max-age=31536000,immutable"
NO_CACHE = "no-store,no-cache,must-revalidate"


def encode_json(payload):
    return (json.dumps(payload, ensure_ascii=False, sort_keys=True,
                       separators=(",", ":")) + "\n").encode("utf-8")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def frames_for(resident):
    names = list(FRAMES)
    for direction in SPRITE_DIRECTIONS:
        if resident["id"] == "001_shiba" and direction == "left":
            # The project's existing sprite contract explicitly mirrors right.
            # Do not invent files or silently substitute another source image.
            continue
        names.extend(f"walk_{direction}_{frame:02d}.png"
                     for frame in range(1, 5))
    return names


def _record(stage, relative, data, records):
    target = stage / relative
    if target.exists():
        raise ValueError(f"Duplicate bundle path: {relative}")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    records.append({"path": relative.as_posix(), "sha256": digest(data),
                    "size": len(data)})


def prepare(stage):
    """Stage and validate one complete, reproducible immutable release."""
    if stage.exists() and any(stage.iterdir()):
        raise ValueError(f"Staging destination must be empty: {stage}")
    stage.mkdir(parents=True, exist_ok=True)
    catalog = runtime_catalog()
    records = []
    _record(stage, Path("api/runtime/catalog"), encode_json(catalog), records)
    for resident in catalog["characters"]:
        for frame in frames_for(resident):
            path = runtime_sprite_path(resident["artFolder"], frame)
            raw = path.read_bytes()
            if len(raw) < 24 or not raw.startswith(PNG_SIGNATURE) or raw[12:16] != b"IHDR":
                raise ValueError(f"Invalid PNG sprite: {path}")
            relative = Path("api/runtime/sprites") / resident["artFolder"] / frame
            _record(stage, relative, raw, records)
    records.sort(key=lambda row: row["path"])
    release_id = digest(encode_json(records))
    manifest = {
        "schemaVersion": 1,
        "releaseId": release_id,
        "objects": records,
    }
    manifest_bytes = encode_json(manifest)
    manifest_path = stage / "manifest.json"
    manifest_path.write_bytes(manifest_bytes)
    return release_id, records, {
        "schemaVersion": 1,
        "releaseId": release_id,
        "basePath": f"/releases/{release_id}/",
        "manifestPath": f"/releases/{release_id}/manifest.json",
        "manifestSha256": digest(manifest_bytes),
    }


def aws(args, *commands):
    argv = ["aws", "--region", args.region]
    if args.profile:
        argv.extend(["--profile", args.profile])
    argv.extend(commands)
    try:
        result = subprocess.run(argv, text=True, capture_output=True, check=True)
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(
            f"AWS CLI failed, exit={exc.returncode}\n"
            f"argv={argv}\nstdout={exc.stdout}\nstderr={exc.stderr}"
        ) from exc
    return result.stdout


def aws_json(args, *commands):
    raw = aws(args, *commands, "--output", "json")
    return json.loads(raw)


def stack_outputs(args):
    result = aws_json(args, "cloudformation", "describe-stacks",
                      "--stack-name", args.stack)
    stacks = result.get("Stacks")
    if not isinstance(stacks, list) or len(stacks) != 1:
        raise RuntimeError(f"Expected exactly one CloudFormation stack: {args.stack}")
    stack = stacks[0]
    if stack["StackStatus"] not in {"CREATE_COMPLETE", "UPDATE_COMPLETE"}:
        raise RuntimeError(f"Stack is not ready: {stack['StackStatus']}")
    outputs = {item["OutputKey"]: item["OutputValue"]
               for item in stack.get("Outputs", [])}
    needed = {"ContentBucketName", "ContentDistributionId", "ContentDomain"}
    if not needed.issubset(outputs):
        raise RuntimeError(f"Stack outputs missing: {sorted(needed - outputs.keys())}")
    return outputs


def upload(args, bucket, source, key, mime, cache_control):
    aws(args, "s3", "cp", str(source), f"s3://{bucket}/{key}",
        "--content-type", mime, "--cache-control", cache_control,
        "--sse", "AES256", "--only-show-errors", "--no-progress")


def verify_release(args, bucket, prefix, records, manifest_path):
    result = aws_json(args, "s3api", "list-objects-v2",
                      "--bucket", bucket, "--prefix", prefix)
    if result.get("IsTruncated", False):
        raise RuntimeError("S3 listing is truncated; release cannot be verified")
    actual = {item["Key"]: item["Size"] for item in result.get("Contents", [])}
    expected = {prefix + row["path"]: row["size"] for row in records}
    expected[prefix + "manifest.json"] = manifest_path.stat().st_size
    if actual != expected:
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        size_mismatch = [(key, expected[key], actual.get(key))
                         for key in expected if key in actual
                         and expected[key] != actual[key]]
        raise RuntimeError(
            f"Release object verification failed: missing={missing}, "
            f"extra={extra}, size_mismatch={size_mismatch}"
        )


def publish(args):
    if shutil.which("aws") is None:
        raise RuntimeError("AWS CLI v2 must be installed and on PATH")
    if not args.region or not args.stack:
        raise ValueError("An explicit AWS region and stack name are required")
    account = aws_json(args, "sts", "get-caller-identity")
    outputs = stack_outputs(args)
    bucket = outputs["ContentBucketName"]
    domain = outputs["ContentDomain"]
    print(f"Account: {account['Account']}  Region: {args.region}", flush=True)
    print(f"Bucket: {bucket}  CDN: https://{domain}", flush=True)

    with tempfile.TemporaryDirectory(prefix="kotohogu-content-") as tempdir:
        stage = Path(tempdir) / "release"
        release_id, records, pointer = prepare(stage)
        prefix = f"releases/{release_id}/"
        print(f"Validated {len(records)} objects; release={release_id}", flush=True)
        # The release prefix is content-addressed, and therefore immutable.
        # CLI sync does not delete other releases or publish the live pointer.
        aws(args, "s3", "sync", str(stage / "api" / "runtime" / "sprites"),
            f"s3://{bucket}/{prefix}api/runtime/sprites/",
            "--exclude", "*", "--include", "*.png",
            "--content-type", "image/png", "--cache-control", IMMUTABLE,
            "--sse", "AES256", "--only-show-errors", "--no-progress")
        upload(args, bucket, stage / "api" / "runtime" / "catalog",
               prefix + "api/runtime/catalog", "application/json", IMMUTABLE)
        upload(args, bucket, stage / "manifest.json", prefix + "manifest.json",
               "application/json", IMMUTABLE)
        verify_release(args, bucket, prefix, records, stage / "manifest.json")
        # Once every object is present, update the sole mutable entry point.
        current = Path(tempdir) / "current.json"
        current.write_bytes(encode_json(pointer))
        upload(args, bucket, current, "current.json", "application/json", NO_CACHE)
        back = Path(tempdir) / "current-verified.json"
        aws(args, "s3", "cp", f"s3://{bucket}/current.json", str(back),
            "--only-show-errors", "--no-progress")
        if back.read_bytes() != current.read_bytes():
            raise RuntimeError("Published current.json could not be verified")

    print(f"Published: https://{domain}/current.json", flush=True)
    print(f"Pinned release base URL: https://{domain}/releases/{release_id}/",
          flush=True)
    print("AWS upload confirmed; HTTPS/CloudFront retrieval must still be tested.",
          flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stack", required=True, help="CloudFormation stack name")
    parser.add_argument("--region", required=True, help="Explicit AWS region")
    parser.add_argument("--profile", help="Optional AWS CLI profile name")
    args = parser.parse_args()
    publish(args)


if __name__ == "__main__":
    main()
