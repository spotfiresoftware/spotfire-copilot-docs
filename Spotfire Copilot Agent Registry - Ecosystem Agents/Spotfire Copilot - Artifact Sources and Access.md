# Artifact Sources and Access

This document defines the standard artifact source and access workflow shared by the Ecosystem Agents deployment guides (the [Agent Server Deployment](Agent%20Server%20Deployment/README.md) and [MCP Servers](MCP%20Servers/README.md) guides).

## Table of Contents

- [1. Purpose](#1-purpose)
- [2. Standard Artifact Source Pattern](#2-standard-artifact-source-pattern)
- [3. Required Access](#3-required-access)
- [4. Login Commands](#4-login-commands)
- [5. Access Validation](#5-access-validation)
- [6. Version Selection Policy](#6-version-selection-policy)
- [7. Recommended Practices](#7-recommended-practices)
- [8. Troubleshooting](#8-troubleshooting)


## 1. Purpose

Use this reference for:

1. OCI registry login requirements
2. Artifact pull/access validation commands
3. Version selection policy
4. Recommended operator practices

Deployment guides can reference this page instead of repeating the same artifact access details.

## 2. Standard Artifact Source Pattern

Most deployment assets are distributed as OCI artifacts from:

- Registry host: `copilotoci.azurecr.io`
- Repository prefix: `spotfirecopilot`

Common artifact forms:

- Container image: `copilotoci.azurecr.io/spotfirecopilot/<artifact-name>:<image-tag>`
- Helm chart: `oci://copilotoci.azurecr.io/spotfirecopilot/<artifact-name>`

## 3. Required Access

Operators need credentials with pull/read access to OCI artifacts:

- Registry username
- Registry password or access token

## 4. Login Commands

Run both commands before deploying:

```bash
helm registry login copilotoci.azurecr.io
docker login copilotoci.azurecr.io
```

## 5. Access Validation

Validate chart and image access with explicit versions/tags:

```bash
helm show chart oci://copilotoci.azurecr.io/spotfirecopilot/<artifact-name> \
  --version <chart-version>

docker pull copilotoci.azurecr.io/spotfirecopilot/<artifact-name>:<image-tag>
```

## 6. Version Selection Policy

Use operator-approved versions only:

1. Choose an approved chart version and pass it using `--version <chart-version>`.
2. Choose an approved image tag and set it in values files or compose env.
3. Do not assume a fixed chart-to-image mapping unless your platform team publishes one.

## 7. Recommended Practices

1. Pin chart and image versions in deployment automation.
2. Validate pull access during pre-deploy checks, not during incident response.
3. Use least-privilege OCI credentials for runtime environments.
4. Rotate credentials and tokens on a regular schedule.

## 8. Troubleshooting

Common issues and checks:

1. Authentication failures (`401`/`403`):
- Re-run login commands.
- Confirm the credential has pull access.
- Confirm the credential is for `copilotoci.azurecr.io`.

2. Artifact not found:
- Verify `<artifact-name>` path.
- Verify `<chart-version>` and `<image-tag>` exist.
- Confirm you are targeting the correct repository prefix (`spotfirecopilot`).

3. Helm works but Docker fails (or vice versa):
- Authenticate with both `helm registry login` and `docker login`.
- Check local credential helper behavior for each CLI.
