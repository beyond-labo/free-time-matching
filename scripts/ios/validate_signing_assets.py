#!/usr/bin/env python3
"""Validate decoded iOS signing assets before Xcode starts an archive."""

from __future__ import annotations

import argparse
import plistlib
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional


class ValidationError(Exception):
    """An actionable signing preflight failure."""


def _utc(value: datetime) -> datetime:
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def validate_profile(
    profile_path: Path,
    certificate_der_path: Path,
    team_id: str,
    bundle_id: str,
    *,
    now: Optional[datetime] = None,
) -> None:
    try:
        with profile_path.open("rb") as profile_file:
            profile = plistlib.load(profile_file)
    except (OSError, plistlib.InvalidFileException) as error:
        raise ValidationError("Provisioning profile payload is not a valid property list.") from error

    profile_uuid = profile.get("UUID")
    try:
        uuid.UUID(profile_uuid)
    except (AttributeError, TypeError, ValueError) as error:
        raise ValidationError("Provisioning profile UUID is invalid.") from error

    profile_name = profile.get("Name")
    if not isinstance(profile_name, str) or not profile_name or "\n" in profile_name or "\r" in profile_name:
        raise ValidationError("Provisioning profile name is missing or invalid.")

    profile_teams = profile.get("TeamIdentifier")
    if not isinstance(profile_teams, list) or team_id not in profile_teams:
        raise ValidationError("Provisioning profile Team ID does not match APPLE_TEAM_ID.")

    entitlements = profile.get("Entitlements")
    app_identifier = entitlements.get("application-identifier") if isinstance(entitlements, dict) else None
    if app_identifier != f"{team_id}.{bundle_id}":
        raise ValidationError("Provisioning profile application identifier does not match IOS_BUNDLE_ID.")

    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, datetime):
        raise ValidationError("Provisioning profile expiration date is missing or invalid.")
    current_time = _utc(now or datetime.now(timezone.utc))
    if _utc(expiration) <= current_time:
        raise ValidationError("Provisioning profile has expired.")

    try:
        certificate_der = certificate_der_path.read_bytes()
    except OSError as error:
        raise ValidationError("Distribution certificate could not be read.") from error
    profile_certificates = profile.get("DeveloperCertificates")
    if not isinstance(profile_certificates, list) or certificate_der not in profile_certificates:
        raise ValidationError("Distribution certificate is not included in the provisioning profile.")


def _run_openssl(arguments: list[str], failure_message: str) -> str:
    result = subprocess.run(
        ["openssl", *arguments],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise ValidationError(failure_message)
    return result.stdout


def validate_crypto_material(
    certificate_pem_path: Path,
    distribution_private_key_path: Path,
    api_private_key_path: Path,
) -> None:
    _run_openssl(
        ["x509", "-in", str(certificate_pem_path), "-checkend", "0", "-noout"],
        "Distribution certificate is invalid or has expired.",
    )
    certificate_public_key = _run_openssl(
        ["x509", "-in", str(certificate_pem_path), "-pubkey", "-noout"],
        "Distribution certificate is invalid.",
    )
    private_public_key = _run_openssl(
        ["pkey", "-in", str(distribution_private_key_path), "-pubout"],
        "Distribution private key is invalid.",
    )
    if certificate_public_key != private_public_key:
        raise ValidationError("Distribution certificate and private key do not match.")

    api_key_details = _run_openssl(
        ["pkey", "-in", str(api_private_key_path), "-check", "-text", "-noout"],
        "App Store Connect API private key is invalid.",
    )
    if "ASN1 OID: prime256v1" not in api_key_details or "NIST CURVE: P-256" not in api_key_details:
        raise ValidationError("App Store Connect API private key must be an EC P-256 key for ES256.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile-plist", type=Path, required=True)
    parser.add_argument("--certificate-der", type=Path, required=True)
    parser.add_argument("--certificate-pem", type=Path, required=True)
    parser.add_argument("--distribution-private-key", type=Path, required=True)
    parser.add_argument("--api-private-key", type=Path, required=True)
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--bundle-id", required=True)
    arguments = parser.parse_args()

    try:
        validate_profile(
            arguments.profile_plist,
            arguments.certificate_der,
            arguments.team_id,
            arguments.bundle_id,
        )
        validate_crypto_material(
            arguments.certificate_pem,
            arguments.distribution_private_key,
            arguments.api_private_key,
        )
    except ValidationError as error:
        print(f"Signing preflight failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
