"""Render the inline Lambda CloudFormation template and deploy explicitly."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent


def render():
    template = json.loads((ROOT / "duel-stack.json").read_text(encoding="utf-8"))
    source = (ROOT / "duel_api.py").read_text(encoding="utf-8")
    compile(source, "duel_api.py", "exec")
    code = template["Resources"]["Function"]["Properties"]["Code"]
    if code != {"ZipFile": "__DUEL_SOURCE__"}:
        raise ValueError("Unexpected duel template source marker")
    code["ZipFile"] = source
    rendered = json.dumps(template, ensure_ascii=False)
    if len(rendered.encode("utf-8")) > 51200:
        raise ValueError("Duel template exceeds CloudFormation inline limit")
    return rendered


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--stack", default="kotohogu-duel")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9-]{0,59}", args.stack):
        parser.error("Invalid stack name (maximum 60 characters)")
    rendered = render()
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "duel-stack.json"
        path.write_text(rendered, encoding="utf-8")
        common = ["--region", args.region, "--profile", args.profile]
        subprocess.run(["aws", "cloudformation", "deploy",
                        "--template-file", str(path), "--stack-name", args.stack,
                        "--capabilities", "CAPABILITY_IAM",
                        "--no-fail-on-empty-changeset", *common], check=True)
        subprocess.run(["aws", "cloudformation", "describe-stacks",
                        "--stack-name", args.stack, "--query",
                        "Stacks[0].Outputs", "--output", "table", *common], check=True)


if __name__ == "__main__":
    main()
