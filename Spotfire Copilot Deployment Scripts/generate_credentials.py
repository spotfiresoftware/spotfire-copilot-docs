#!/usr/bin/env python3
# <copyright file="generate_credentials.py" company="Cloud Software Group, Inc.">
#   Copyright © 2006 - 2026 Cloud Software Group, Inc.
# All rights reserved.
# This software is the confidential and proprietary information
# of Cloud Software Group, Inc. ("Confidential Information"). You shall not
# disclose such Confidential Information and may not use it in any way,
# absent an express written license agreement between you and
# Cloud Software Group, Inc. that authorizes such use.
# </copyright>
"""
Spotfire Copilot™ — Credential Generator

Generates bcrypt-hashed credentials for secure deployment configuration.
All output is ready to paste into your .env file — no plaintext passwords
are ever stored in deployment config.

Usage:
    python generate_credentials.py                  # Generate everything
    python generate_credentials.py --admin-only     # Admin password only
    python generate_credentials.py --oauth2-only    # OAuth2 client only
    python generate_credentials.py --secret-key-only # SECRET_KEY only
    python generate_credentials.py --password "MyP@ssw0rd"  # Specific password
"""

import argparse
import secrets
import string
import sys

try:
    import bcrypt as _bcrypt
    
    def hash_password(password: str) -> str:
        """Hash a password using bcrypt (direct bcrypt library)."""
        return _bcrypt.hashpw(
            password.encode("utf-8"), _bcrypt.gensalt(rounds=12)
        ).decode("utf-8")

except ImportError:
    try:
        from passlib.context import CryptContext
        import logging
        logging.getLogger("passlib").setLevel(logging.ERROR)
        _pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
        
        def hash_password(password: str) -> str:
            """Hash a password using passlib bcrypt."""
            return _pwd_context.hash(password)
    
    except ImportError:
        print("ERROR: bcrypt or passlib is required.")
        print("  Install with: pip install bcrypt")
        print("  Or:           pip install passlib[bcrypt]")
        sys.exit(1)


def generate_secure_password(length: int = 24) -> str:
    """Generate a cryptographically secure random password."""
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    # Ensure at least one of each required character type
    password = [
        secrets.choice(string.ascii_uppercase),
        secrets.choice(string.ascii_lowercase),
        secrets.choice(string.digits),
        secrets.choice("!@#$%^&*"),
    ]
    password += [secrets.choice(alphabet) for _ in range(length - 4)]
    # Shuffle to avoid predictable positions
    pw_list = list(password)
    secrets.SystemRandom().shuffle(pw_list)
    return "".join(pw_list)


def generate_client_id(length: int = 22) -> str:
    """Generate a secure OAuth2 client ID."""
    return "".join(
        secrets.choice(string.ascii_letters + string.digits + "-_")
        for _ in range(length)
    )


def generate_client_secret(length: int = 43) -> str:
    """Generate a secure OAuth2 client secret."""
    return "".join(
        secrets.choice(string.ascii_letters + string.digits + "-_+/")
        for _ in range(length)
    )


def main():
    parser = argparse.ArgumentParser(
        description="Generate hashed credentials for Spotfire Copilot™ deployment"
    )
    parser.add_argument(
        "--admin-only",
        action="store_true",
        help="Generate only the admin password hash",
    )
    parser.add_argument(
        "--oauth2-only",
        action="store_true",
        help="Generate only the OAuth2 client credentials",
    )
    parser.add_argument(
        "--secret-key-only",
        action="store_true",
        help="Generate only the SECRET_KEY",
    )
    parser.add_argument(
        "--password",
        type=str,
        default=None,
        help="Use a specific password instead of generating one",
    )
    args = parser.parse_args()

    # When a --*-only flag is set, only generate that section.
    # When no flags are set, generate everything.
    only_flags = [args.admin_only, args.oauth2_only, args.secret_key_only]
    generate_all = not any(only_flags)
    generate_admin = generate_all or args.admin_only
    generate_oauth2 = generate_all or args.oauth2_only
    generate_secret_key = generate_all or args.secret_key_only

    print()
    print("=" * 70)
    print("  Spotfire Copilot™ — Credential Generator")
    print("=" * 70)
    print()
    print("  ⚠️  IMPORTANT: Bcrypt hashes contain $ characters.")
    print("  The output below is ready to paste directly into .env —")
    print("  single quotes are required to prevent Docker Compose")
    print("  from interpreting $ as variable references.")
    print()

    if generate_secret_key:
        jwt_secret = secrets.token_hex(32)

        print("\u2500\u2500\u2500 SECRET_KEY (JWT + service-to-service auth) \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500")
        print()
        print(f"  Add to .env:")
        print(f"    SECRET_KEY={jwt_secret}")
        print()
        print(f"  Used for JWT token signing AND as X-Internal-API-Key for")
        print(f"  admin console \u2192 orchestrator internal API calls.")
        print()

    if generate_admin:
        password = args.password or generate_secure_password()
        hashed = hash_password(password)

        print("─── Admin Password ───────────────────────────────────────────")
        print()
        print(f"  Plaintext (SAVE THIS — it will NOT be shown again):")
        print(f"    {password}")
        print()
        print(f"  Add to .env:")
        print(f"    HASHED_ADMIN_PASSWORD='{hashed}'")
        print()

    if generate_oauth2:
        client_id = generate_client_id()
        client_secret = generate_client_secret()
        secret_hash = hash_password(client_secret)

        print("─── OAuth2 Client Credentials ────────────────────────────────")
        print()
        print(f"  Client ID:     {client_id}")
        print(f"  Client Secret (SAVE THIS — it will NOT be shown again):")
        print(f"    {client_secret}")
        print()
        print(f"  Add to .env:")
        print(f"    OAUTH2_CLIENT_ID={client_id}")
        print(f"    OAUTH2_CLIENT_SECRET_HASH='{secret_hash}'")
        print()

    print("─── Notes ────────────────────────────────────────────────────")
    print()
    print("  • Paste the lines above directly into .env — quotes included.")
    print("    (Single quotes prevent Docker Compose from mangling the $ chars.)")
    print("  • Only the HASHED values go in .env / docker-compose / K8s secrets.")
    print("  • Store the plaintext password and client secret in a vault.")
    print("  • To reset a forgotten password, generate a new hash and restart.")
    print("    The system detects the changed hash and resets automatically.")
    print()
    print("=" * 70)


if __name__ == "__main__":
    main()
