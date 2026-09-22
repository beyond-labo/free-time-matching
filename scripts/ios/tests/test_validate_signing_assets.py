from __future__ import annotations

import base64
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from validate_signing_assets import ValidationError, validate_crypto_material, validate_profile


class SigningAssetValidationTests(unittest.TestCase):
    team_id = "ABCDE12345"
    bundle_id = "com.example.himatch"
    runtime_configuration = {
        "SUPABASE_URL": "https://example.supabase.co",
        "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_test",
        "API_BASE_URL": "https://api-staging.example.com",
    }

    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory()
        cls.directory = Path(cls.temporary_directory.name)
        cls.certificate_pem = cls.directory / "distribution-certificate.pem"
        cls.distribution_private_key = cls.directory / "distribution-private-key.pem"
        cls.certificate_der = cls.directory / "distribution-certificate.der"
        cls.mismatched_private_key = cls.directory / "mismatched-private-key.pem"
        cls.expired_certificate = cls.directory / "expired-certificate.pem"
        cls.expired_private_key = cls.directory / "expired-private-key.pem"
        cls.api_p256_key = cls.directory / "api-p256.p8"
        cls.api_p384_key = cls.directory / "api-p384.p8"
        cls.api_rsa_key = cls.directory / "api-rsa.p8"
        cls.invalid_api_key = cls.directory / "invalid-api.p8"
        cls.legacy_pkcs12 = cls.directory / "legacy-distribution.p12"
        cls.pkcs12_password = "test-password"

        cls.run_openssl(
            "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", cls.distribution_private_key,
            "-out", cls.certificate_pem,
            "-days", "1", "-subj", "/CN=Himatch Test Distribution",
        )
        cls.run_openssl("x509", "-in", cls.certificate_pem, "-outform", "DER", "-out", cls.certificate_der)
        cls.run_openssl(
            "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048",
            "-out", cls.mismatched_private_key,
        )

        expired_request = cls.directory / "expired.csr"
        cls.run_openssl(
            "req", "-new", "-newkey", "rsa:2048", "-nodes",
            "-keyout", cls.expired_private_key,
            "-out", expired_request,
            "-subj", "/CN=Expired Distribution",
        )
        cls.run_openssl(
            "x509", "-req", "-in", expired_request,
            "-signkey", cls.expired_private_key,
            "-not_before", "20200101000000Z", "-not_after", "20200102000000Z",
            "-out", cls.expired_certificate,
        )

        cls.run_openssl(
            "genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256",
            "-out", cls.api_p256_key,
        )
        cls.run_openssl(
            "pkcs12", "-export", "-legacy",
            "-inkey", cls.distribution_private_key,
            "-in", cls.certificate_pem,
            "-out", cls.legacy_pkcs12,
            "-passout", f"pass:{cls.pkcs12_password}",
        )
        cls.run_openssl(
            "genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-384",
            "-out", cls.api_p384_key,
        )
        cls.run_openssl(
            "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048",
            "-out", cls.api_rsa_key,
        )
        cls.invalid_api_key.write_text("not a private key", encoding="utf-8")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    @classmethod
    def run_openssl(cls, *arguments: object) -> None:
        subprocess.run(
            ["openssl", *(str(argument) for argument in arguments)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )

    def write_profile(self, *, expiration: datetime, certificate: Optional[bytes] = None) -> Path:
        path = self.directory / "profile.plist"
        profile_certificate = self.certificate_der.read_bytes() if certificate is None else certificate
        with path.open("wb") as profile_file:
            plistlib.dump(
                {
                    "UUID": "12345678-1234-1234-1234-123456789ABC",
                    "Name": "Himatch App Store",
                    "TeamIdentifier": [self.team_id],
                    "Entitlements": {"application-identifier": f"{self.team_id}.{self.bundle_id}"},
                    "ExpirationDate": expiration,
                    "DeveloperCertificates": [profile_certificate],
                },
                profile_file,
            )
        return path

    def test_valid_profile_accepts_matching_unexpired_certificate(self) -> None:
        now = datetime(2026, 9, 16, tzinfo=timezone.utc)
        profile = self.write_profile(expiration=now + timedelta(days=1))
        validate_profile(profile, self.certificate_der, self.team_id, self.bundle_id, now=now)

    def test_expired_profile_is_rejected(self) -> None:
        now = datetime(2026, 9, 16, tzinfo=timezone.utc)
        profile = self.write_profile(expiration=now - timedelta(seconds=1))
        with self.assertRaisesRegex(ValidationError, "has expired"):
            validate_profile(profile, self.certificate_der, self.team_id, self.bundle_id, now=now)

    def test_certificate_not_in_profile_is_rejected(self) -> None:
        now = datetime(2026, 9, 16, tzinfo=timezone.utc)
        profile = self.write_profile(expiration=now + timedelta(days=1), certificate=b"another-certificate")
        with self.assertRaisesRegex(ValidationError, "not included"):
            validate_profile(profile, self.certificate_der, self.team_id, self.bundle_id, now=now)

    def test_valid_crypto_material_accepts_p256_api_key(self) -> None:
        validate_crypto_material(self.certificate_pem, self.distribution_private_key, self.api_p256_key)

    def test_expired_certificate_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValidationError, "has expired"):
            validate_crypto_material(self.expired_certificate, self.expired_private_key, self.api_p256_key)

    def test_mismatched_distribution_private_key_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValidationError, "do not match"):
            validate_crypto_material(self.certificate_pem, self.mismatched_private_key, self.api_p256_key)

    def test_invalid_api_private_key_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValidationError, "private key is invalid"):
            validate_crypto_material(self.certificate_pem, self.distribution_private_key, self.invalid_api_key)

    def test_rsa_api_private_key_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValidationError, "EC P-256"):
            validate_crypto_material(self.certificate_pem, self.distribution_private_key, self.api_rsa_key)

    def test_p384_api_private_key_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValidationError, "EC P-256"):
            validate_crypto_material(self.certificate_pem, self.distribution_private_key, self.api_p384_key)

    def test_release_rejects_non_uuid_issuer_before_decoding_assets(self) -> None:
        environment = os.environ | self.runtime_configuration | {
            "APPLE_TEAM_ID": self.team_id,
            "IOS_BUNDLE_ID": self.bundle_id,
            "IOS_MARKETING_VERSION": "1.0.0",
            "IOS_BUILD_NUMBER": "1",
            "IOS_DISTRIBUTION_CERTIFICATE_BASE64": "unused",
            "IOS_DISTRIBUTION_CERTIFICATE_PASSWORD": "unused",
            "IOS_PROVISIONING_PROFILE_BASE64": "unused",
            "APP_STORE_CONNECT_KEY_ID": "ABCDEF1234",
            "APP_STORE_CONNECT_ISSUER_ID": "123456789012345678901234567890123456",
            "APP_STORE_CONNECT_PRIVATE_KEY_BASE64": "unused",
        }
        result = subprocess.run(
            ["bash", str(SCRIPT_DIR / "release.sh")],
            capture_output=True,
            text=True,
            env=environment,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must be a UUID", result.stderr)

    def test_release_rejects_non_https_runtime_url_before_decoding_assets(self) -> None:
        environment = os.environ | self.runtime_configuration | {
            "APPLE_TEAM_ID": self.team_id,
            "IOS_BUNDLE_ID": self.bundle_id,
            "IOS_MARKETING_VERSION": "1.0.0",
            "IOS_BUILD_NUMBER": "1",
            "IOS_DISTRIBUTION_CERTIFICATE_BASE64": "unused",
            "IOS_DISTRIBUTION_CERTIFICATE_PASSWORD": "unused",
            "IOS_PROVISIONING_PROFILE_BASE64": "unused",
            "APP_STORE_CONNECT_KEY_ID": "ABCDEF1234",
            "APP_STORE_CONNECT_ISSUER_ID": "12345678-1234-1234-1234-123456789abc",
            "APP_STORE_CONNECT_PRIVATE_KEY_BASE64": "unused",
            "SUPABASE_URL": "http://example.supabase.co",
        }
        result = subprocess.run(
            ["bash", str(SCRIPT_DIR / "release.sh")],
            capture_output=True,
            text=True,
            env=environment,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SUPABASE_URL must be a non-empty HTTPS URL", result.stderr)

    def test_release_can_extract_legacy_pkcs12_before_profile_validation(self) -> None:
        fake_bin = self.directory / "fake-bin"
        fake_bin.mkdir(exist_ok=True)
        fake_security = fake_bin / "security"
        fake_security.write_text(
            "#!/bin/bash\n"
            "if [[ \"$1\" == \"cms\" ]]; then\n"
            "  cat \"$FAKE_PROFILE_PLIST\"\n"
            "  exit 0\n"
            "fi\n"
            "exit 1\n",
            encoding="utf-8",
        )
        fake_security.chmod(0o755)

        invalid_profile = self.directory / "invalid-profile.plist"
        with invalid_profile.open("wb") as profile_file:
            plistlib.dump({}, profile_file)

        fake_home = self.directory / "home"
        fake_runner_temp = self.directory / "runner-temp"
        fake_home.mkdir(exist_ok=True)
        fake_runner_temp.mkdir(exist_ok=True)
        environment = os.environ | self.runtime_configuration | {
            "APPLE_TEAM_ID": self.team_id,
            "IOS_BUNDLE_ID": self.bundle_id,
            "IOS_MARKETING_VERSION": "1.0.0",
            "IOS_BUILD_NUMBER": "1",
            "IOS_DISTRIBUTION_CERTIFICATE_BASE64": base64.b64encode(
                self.legacy_pkcs12.read_bytes()
            ).decode("ascii"),
            "IOS_DISTRIBUTION_CERTIFICATE_PASSWORD": self.pkcs12_password,
            "IOS_PROVISIONING_PROFILE_BASE64": base64.b64encode(b"placeholder").decode("ascii"),
            "APP_STORE_CONNECT_KEY_ID": "ABCDEF1234",
            "APP_STORE_CONNECT_ISSUER_ID": "12345678-1234-1234-1234-123456789abc",
            "APP_STORE_CONNECT_PRIVATE_KEY_BASE64": base64.b64encode(
                self.api_p256_key.read_bytes()
            ).decode("ascii"),
            "FAKE_PROFILE_PLIST": str(invalid_profile),
            "HOME": str(fake_home),
            "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
            "RUNNER_TEMP": str(fake_runner_temp),
        }

        result = subprocess.run(
            ["bash", str(SCRIPT_DIR / "release.sh")],
            capture_output=True,
            text=True,
            env=environment,
            check=False,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Provisioning profile UUID is invalid", result.stderr)
        self.assertNotIn("RC2-40-CBC", result.stderr)
        self.assertNotIn("inner_evp_generic_fetch:unsupported", result.stderr)


if __name__ == "__main__":
    unittest.main()
