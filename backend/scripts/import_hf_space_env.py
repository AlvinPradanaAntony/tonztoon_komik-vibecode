"""
Import a .env-style file into Hugging Face Space variables and secrets.

Usage:
    python backend/scripts/import_hf_space_env.py --dry-run
    python backend/scripts/import_hf_space_env.py --space username/space-name --dry-run
    python backend/scripts/import_hf_space_env.py --space username/space-name
    python backend/scripts/import_hf_space_env.py --space username/space-name --all-secrets

Authentication:
    Set HF_TOKEN in your shell/env file, or pass --token.

Notes:
    - Values are never printed.
    - If the env file contains section comments named "Environment Variables"
      and "Secrets Variables", keys are classified by section.
    - Obvious sensitive keys are still forced to Secrets unless --trust-sections
      is used.
"""

from __future__ import annotations

import argparse
import os
import re
from pathlib import Path

from dotenv import dotenv_values


DEFAULT_ENV_FILE = Path(__file__).resolve().parents[1] / ".env-hf"

ENV_SECTION_MARKER = "environment variables"
SECRET_SECTION_MARKER = "secrets variables"
ENV_KEY_RE = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=")
SENSITIVE_KEY_PATTERNS = (
    "ACCESS_TOKEN",
    "API_KEY",
    "DATABASE_URL",
    "GITHUB_PAT",
    "JWT_SECRET",
    "PASSWORD",
    "PRIVATE_KEY",
    "SECRET",
    "SERVICE_ROLE",
    "TOKEN",
)
INTERNAL_IMPORT_KEYS = {"HF_SPACE", "HF_SPACE_ID", "HF_TOKEN"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Import backend/.env-hf into Hugging Face Space secrets/variables."
    )
    parser.add_argument(
        "--space",
        default="",
        help="Target Space repo id, e.g. username/space-name.",
    )
    parser.add_argument(
        "--env-file",
        default=str(DEFAULT_ENV_FILE),
        help=f"Path to .env file. Default: {DEFAULT_ENV_FILE}",
    )
    parser.add_argument(
        "--token",
        default=os.getenv("HF_TOKEN", ""),
        help="Hugging Face user access token. Defaults to HF_TOKEN env var.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print key classification without sending anything to Hugging Face.",
    )
    parser.add_argument(
        "--all-secrets",
        action="store_true",
        help="Upload every key as a Space Secret.",
    )
    parser.add_argument(
        "--trust-sections",
        action="store_true",
        help=(
            "Use section classification exactly. Without this flag, obvious "
            "sensitive key names are forced to Secrets."
        ),
    )
    parser.add_argument(
        "--variable",
        action="append",
        default=[],
        metavar="KEY",
        help="Force KEY to be uploaded as a Space Variable. Can be repeated.",
    )
    parser.add_argument(
        "--secret",
        action="append",
        default=[],
        metavar="KEY",
        help="Force KEY to be uploaded as a Space Secret. Can be repeated.",
    )
    parser.add_argument(
        "--include-empty",
        action="store_true",
        help="Also upload keys with empty values. Empty values are skipped by default.",
    )
    return parser.parse_args()


def load_env_file(path: Path, *, include_empty: bool) -> tuple[dict[str, str], dict[str, str]]:
    if not path.exists():
        raise FileNotFoundError(f"Env file not found: {path}")

    parsed = dotenv_values(path)
    values: dict[str, str] = {}
    for key, value in parsed.items():
        if not key:
            continue
        if value is None:
            continue
        if value == "" and not include_empty:
            continue
        values[key] = value

    section_by_key = parse_section_map(path)
    return values, section_by_key


def parse_section_map(path: Path) -> dict[str, str]:
    section_by_key: dict[str, str] = {}
    current_section: str | None = None

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        normalized = raw_line.strip().lstrip("#").strip().lower()
        if ENV_SECTION_MARKER in normalized:
            current_section = "variable"
            continue
        if SECRET_SECTION_MARKER in normalized:
            current_section = "secret"
            continue

        match = ENV_KEY_RE.match(raw_line)
        if match and current_section:
            section_by_key[match.group(1)] = current_section

    return section_by_key


def classify_keys(
    values: dict[str, str],
    section_by_key: dict[str, str],
    *,
    all_secrets: bool,
    forced_variables: set[str],
    forced_secrets: set[str],
    trust_sections: bool,
) -> tuple[dict[str, str], dict[str, str]]:
    overlap = forced_variables & forced_secrets
    if overlap:
        raise ValueError(
            "Keys cannot be forced as both variable and secret: "
            + ", ".join(sorted(overlap))
        )

    variables: dict[str, str] = {}
    secrets: dict[str, str] = {}

    for key, value in values.items():
        if key in INTERNAL_IMPORT_KEYS:
            continue
        if key in forced_variables:
            variables[key] = value
        elif all_secrets or key in forced_secrets:
            secrets[key] = value
        elif _looks_sensitive(key) and not trust_sections:
            secrets[key] = value
        elif section_by_key.get(key) == "variable":
            variables[key] = value
        else:
            secrets[key] = value

    return variables, secrets


def _looks_sensitive(key: str) -> bool:
    normalized = key.upper()
    return any(pattern in normalized for pattern in SENSITIVE_KEY_PATTERNS)


def print_plan(variables: dict[str, str], secrets: dict[str, str]) -> None:
    print("Space Variables:")
    for key in sorted(variables):
        print(f"  - {key}")
    if not variables:
        print("  (none)")

    print("Space Secrets:")
    for key in sorted(secrets):
        print(f"  - {key}")
    if not secrets:
        print("  (none)")


def resolve_hf_token(args: argparse.Namespace, values: dict[str, str]) -> str:
    return args.token or values.get("HF_TOKEN", "") or os.getenv("HF_TOKEN", "")


def resolve_space_id(args: argparse.Namespace, values: dict[str, str]) -> str:
    space = (
        args.space
        or values.get("HF_SPACE", "")
        or values.get("HF_SPACE_ID", "")
        or os.getenv("HF_SPACE", "")
        or os.getenv("HF_SPACE_ID", "")
    )
    if not space:
        raise RuntimeError(
            "Target Space is required. Pass --space or set HF_SPACE in the env file."
        )
    return space


def import_to_hugging_face(
    *,
    space: str,
    token: str,
    variables: dict[str, str],
    secrets: dict[str, str],
) -> None:
    if not token:
        raise RuntimeError("HF token is required. Set HF_TOKEN or pass --token.")

    try:
        from huggingface_hub import HfApi
    except ModuleNotFoundError as exc:
        raise RuntimeError(
            "Missing dependency: huggingface_hub. "
            "Install it with: pip install huggingface_hub"
        ) from exc

    api = HfApi(token=token)

    for key, value in sorted(variables.items()):
        api.add_space_variable(repo_id=space, key=key, value=value)
        print(f"variable set: {key}")

    for key, value in sorted(secrets.items()):
        api.add_space_secret(repo_id=space, key=key, value=value)
        print(f"secret set: {key}")


def main() -> None:
    args = parse_args()
    env_path = Path(args.env_file).expanduser().resolve()
    values, section_by_key = load_env_file(env_path, include_empty=args.include_empty)
    space = resolve_space_id(args, values)
    token = resolve_hf_token(args, values)

    variables, secrets = classify_keys(
        values,
        section_by_key,
        all_secrets=args.all_secrets,
        forced_variables=set(args.variable),
        forced_secrets=set(args.secret),
        trust_sections=args.trust_sections,
    )

    print(f"Env file: {env_path}")
    print(f"Target Space: {space}")
    print_plan(variables, secrets)

    if args.dry_run:
        print("Dry run only. Nothing was uploaded.")
        return

    import_to_hugging_face(
        space=space,
        token=token,
        variables=variables,
        secrets=secrets,
    )
    print("Import complete.")


if __name__ == "__main__":
    main()
