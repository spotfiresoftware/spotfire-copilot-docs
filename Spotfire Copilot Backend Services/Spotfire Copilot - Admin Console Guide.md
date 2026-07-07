# Spotfire Copilot — Admin Console Guide

> **Versions covered:** 2.3.0, 2.3.1, 2.3.2, and 2.3.4 &nbsp;|&nbsp; **Last updated:** 24 June 2026 &nbsp;|&nbsp; **Applies to:** Admin Console (companion service to the orchestrator)
>
> This guide is for **customer administrators** who need to operate the Spotfire Copilot admin console day-to-day — managing users, OAuth2 clients, conversations, RAG indexes, and system health. For installing or deploying the admin console alongside the orchestrator, see the [Spotfire Copilot Installation Guide — Backend Infrastructure Setup](Spotfire%20Copilot%20-%20Installation%20Guide%20-%20Backend%20Setup.md).

## Table of Contents

- [1. What the Admin Console Is (and Isn't)](#1-what-the-admin-console-is-and-isnt)
  - [What it does](#what-it-does)
  - [What it doesn't do](#what-it-doesnt-do)
- [2. Getting Started — First Login](#2-getting-started--first-login)
  - [2.1 URL and port](#21-url-and-port)
  - [2.2 The bootstrap admin account](#22-the-bootstrap-admin-account)
  - [2.4 Session lifetime](#24-session-lifetime)
- [3. Roles and Permissions](#3-roles-and-permissions)
  - [3.1 What each role sees in the UI](#31-what-each-role-sees-in-the-ui)
  - [3.2 Conversation privacy mode](#32-conversation-privacy-mode)
- [4. Dashboard](#4-dashboard)
- [5. Conversations and Token Usage](#5-conversations-and-token-usage)
  - [5.1 Conversations tab](#51-conversations-tab)
  - [5.2 Token Usage tab](#52-token-usage-tab)
- [6. User Management](#6-user-management)
  - [6.1 Common actions](#61-common-actions)
  - [6.2 The temporary-password-shown-once gotcha](#62-the-temporary-password-shown-once-gotcha)
- [7. OAuth2 Clients](#7-oauth2-clients)
  - [7.1 Creating a client](#71-creating-a-client)
  - [7.2 Toggling and revoking](#72-toggling-and-revoking)
  - [7.3 Cross-reference](#73-cross-reference)
- [8. Security and Password Policy](#8-security-and-password-policy)
  - [8.1 Security events](#81-security-events)
  - [8.2 Password policy](#82-password-policy)
  - [8.3 Forcing a re-login](#83-forcing-a-re-login)
- [9. RAG Indexes](#9-rag-indexes)
- [10. A2A Agents and Tunnels](#10-a2a-agents-and-tunnels)
  - [10.1 A2A Agents tab](#101-a2a-agents-tab)
  - [10.2 Tunnels tab](#102-tunnels-tab)
- [11. System Logs](#11-system-logs)
- [12. Common Tasks](#12-common-tasks)
  - [Add a new internal user](#add-a-new-internal-user)
  - [Issue OAuth2 credentials for a new Spotfire client install](#issue-oauth2-credentials-for-a-new-spotfire-client-install)
  - [Investigate "the chatbot gave the wrong answer"](#investigate-the-chatbot-gave-the-wrong-answer)
  - [Reset a user's password](#reset-a-users-password)
  - [Lock down a leaked OAuth2 client](#lock-down-a-leaked-oauth2-client)
  - [Investigate a "can't log in" ticket](#investigate-a-cant-log-in-ticket)
  - [Investigate "RAG isn't returning my new document"](#investigate-rag-isnt-returning-my-new-document)
  - [Audit who's been logging in](#audit-whos-been-logging-in)
- [13. Troubleshooting](#13-troubleshooting)
  - [`Incorrect username or password` when logging in as admin](#incorrect-username-or-password-when-logging-in-as-admin)
  - [`Account is temporarily locked` even though I haven't tried many times](#account-is-temporarily-locked-even-though-i-havent-tried-many-times)
  - [Tabs are visible but every list is empty](#tabs-are-visible-but-every-list-is-empty)
  - [Dashboard tiles show zero](#dashboard-tiles-show-zero)
  - [`Log proxy unavailable` on the System Logs tab](#log-proxy-unavailable-on-the-system-logs-tab)
  - [`403 Forbidden` after I just clicked a button](#403-forbidden-after-i-just-clicked-a-button)
  - [Token expired and I keep getting redirected to login](#token-expired-and-i-keep-getting-redirected-to-login)
  - [Conversations show `[Content hidden — conversation privacy is enabled]`](#conversations-show-content-hidden--conversation-privacy-is-enabled)

---

## 1. What the Admin Console Is (and Isn't)

The **admin console** is a browser-based **operations dashboard** for Spotfire Copilot. It runs as a companion container next to the orchestrator and shares its PostgreSQL database. It is **not** a chat interface — end users never see it. It is the tool your operations team uses to keep the orchestrator running smoothly.

### What it does

- **User management** — create users, assign roles, reset passwords, enable/disable accounts.
- **OAuth2 client management** — issue and revoke machine-to-machine credentials for Spotfire clients, scripts, and CI/CD integrations.
- **Conversation monitoring** — read across all users' conversations to investigate support issues, study usage, and audit activity.
- **Token usage analytics** — track LLM token spend per user and per client.
- **RAG index management** — list knowledge-base collections, view indexed sources, trigger enrichment.
- **A2A agent registry** — view and manage agents the orchestrator routes to.
- **MCP tunnel management** — see active tunnels for tools that bridge to local Spotfire instances.
- **Security audit** — view failed login attempts, configure password policy and account-lockout rules.
- **System logs** — tail orchestrator, admin-console, and PostgreSQL container logs from the browser.

### What it doesn't do

- It does **not** answer chat prompts. Inference is the orchestrator's job; the admin console only inspects what already happened.
- It does **not** own the LLM, vector database, or plugin configuration — those are configured via the orchestrator's environment variables.
- It does **not** require a separate database — it uses the orchestrator's PostgreSQL database directly.
- It is **optional**. The orchestrator runs perfectly well without it; you only lose the GUI for the operations above (everything can also be done through the orchestrator's REST API, but the admin console is the supported user experience).

> **Production recommendation:** deploy the admin console. Operating Spotfire Copilot at scale without it means resetting passwords via SQL and managing OAuth2 clients via curl, which is unpleasant.

*[Screenshot: Admin console dashboard home page showing tab bar across the top and "Welcome, admin" header]*

## 2. Getting Started — First Login

### 2.1 URL and port

The admin console runs on **port 8081** by default. Open it in a browser:

```
http://<your-orchestrator-host>:8081/
```

You will be redirected to `/login` if you do not have a valid session.

*[Screenshot: Admin console login form with Username and Password fields and a blue "Sign In" button]*

### 2.2 The bootstrap admin account

The orchestrator bootstraps a built-in admin user the first time it starts. **The username is `admin`**. The login form's first field is labeled "Username" — type `admin` there.

The password is the **plaintext** that `generate_credentials.py` printed during installation (labelled "Plaintext (SAVE THIS)"). That script bcrypt-hashes the password and outputs the hash as `HASHED_ADMIN_PASSWORD` — only the hash is stored in `.env`; the plaintext is never written to any file. You should have stored it in a password manager at install time. If you have lost it, run `generate_credentials.py` again to produce a new hash, update `HASHED_ADMIN_PASSWORD` in `.env`, and restart the admin console container.

### 2.4 Session lifetime

A successful login issues a JWT that is valid for **1 hour**. After that, the next click triggers a redirect back to the login form. There is no "remember me" option and tokens are not refreshed silently — re-authenticate when prompted.

## 3. Roles and Permissions

The admin console has **three roles**, stored in the `role` column of the `users` table:

| Role | Internal value | Who it's for | Can do |
|------|---------------|--------------|--------|
| **Admin** | `admin` | Operations team, IT administrators | Everything — user management, OAuth2 clients, security policy, system logs, all conversations, all token usage |
| **Power user** | `power_user` | Analysts, support engineers, team leads | View **all** conversations, view system-wide stats, trigger summarisation and RAG enrichment — but **not** create users, manage OAuth2 clients, or change security policy |
| **User** | `user` (default) | End users | Their own conversations only, their own token usage, their own password change |

> **Why role separation matters:** the most common operator confusion is "my power user can't reset passwords". That's deliberate. Password resets, OAuth2 client creation, and security-policy changes are admin-only because they affect other users' ability to authenticate. Power users get **read access** to everything operational; admins get **write access** to identity and policy.

### 3.1 What each role sees in the UI

The admin console does **not** hide tabs based on role — every signed-in user sees the full tab bar. Authorisation is enforced on the **server**, not in the navigation. When a non-admin opens an admin-only tab (for example **User Management**, **OAuth Clients**, or **Security**), the tab's data request returns `403 Forbidden` and the panel fails to load rather than showing data.

This is a known cosmetic limitation: the tab buttons are still visible even though their contents are inaccessible. If you want a cleaner experience for non-admins, gate access at your reverse proxy and only give the admin console URL to admins. Power users and standard users typically don't need direct access to it — they interact with Spotfire Copilot through the chat UI.

### 3.2 Conversation privacy mode

If your deployment sets `HIDE_CONVERSATION_CONTENT=true` in the admin console's environment, all message bodies in the **Conversations** view are replaced server-side with:

```
[Content hidden — conversation privacy is enabled]
```

Metadata (timestamps, user IDs, role markers, token counts) still shows. This applies to **every role including admins** — there is no override. Use this in regulated environments where even admins must not read the contents of user conversations.

## 4. Dashboard

The **Dashboard** tab is the landing page after login. It shows top-line counts and quick links.

*[Screenshot: Dashboard tab showing tiles for Total Users, Total Conversations, Tokens Today, Active Clients]*

What's on it:

- **Total users** — count of all users in the `users` table, regardless of active/inactive.
- **Total conversations** — count of threads across all users (admin/power-user view) or the current user's threads (standard user view).
- **Tokens today / this week / this month** — aggregated from per-message metadata.
- **Active OAuth2 clients** — clients with `is_active=true`.
- **Recent activity** — most recent conversations, last 10 by default.

Nothing here is configurable. If a tile shows `0` or `—`, see **[§13](#13-troubleshooting) Troubleshooting → Dashboard tiles show zero**.

## 5. Conversations and Token Usage

### 5.1 Conversations tab

The **Conversations** tab lists every conversation thread in the system. Use it to investigate "what did the user ask?" support tickets, audit prompt activity, or spot-check answers.

*[Screenshot: Conversations tab showing a paginated table with columns User, Document, Started, Last Message, Message count, with a row expanded to show the full message thread]*

What you can do:

- **Search and filter** — by user ID, document ID (the `.dxp` analysis the conversation was anchored to), date range, and free-text against message content.
- **Click a row** — opens the full thread inline: every prompt, every assistant response, every tool call, every summary checkpoint.
- **Delete a thread** — removes it and all its messages permanently. Use sparingly; this is for cleaning up test data, not for compliance redaction (which is what **conversation privacy mode** is for — see **[§3.2](#32-conversation-privacy-mode)**).

Quirks worth knowing:

- The **on-demand summarisation** button is present in the UI but currently returns `501 Not Implemented`. Background summarisation runs automatically; manual triggering will be re-enabled in a later release.
- Threads with branches (where the user edited an earlier prompt and re-ran the conversation) show all branches stacked. The "active" branch — the one the user is currently looking at — is highlighted.
- A power user sees every thread; a standard user logging into the admin console only ever sees their own threads. The same `/conversations` API endpoint enforces both views via role-based filtering.

### 5.2 Token Usage tab

The **Token Usage** tab analyses LLM token consumption from message metadata.

*[Screenshot: Token Usage tab with a bar chart of tokens-per-day over a selected period and a table broken down by user]*

What you can do:

- **Pick a period** — week, month, quarter, year, all, or a custom `days=N`.
- **Filter by user or client** — `user_id=alice` or `client_id=<oauth2-client>`.
- **Purge token-usage metadata for a user** — useful when offboarding (deletes the `token_usage` dict from each message's metadata while keeping the conversation text intact).

Where the numbers come from: every assistant message is stamped with the provider's reported prompt/completion/total token counts in `metadata_.token_usage`. The Token Usage tab simply aggregates this JSONB field. If your LLM provider doesn't return usage (rare), the count is zero — the answer was still generated, but it's not visible here.

## 6. User Management

The **User Management** tab is **admin-only**. Power users see the tab but every action returns 403.

*[Screenshot: User Management tab showing a table of users with columns Email, Username, Role, Active, Last Login, plus action buttons]*

### 6.1 Common actions

- **Create user** — opens a modal. Required: email, username, full name, role (`user` / `power_user` / `admin`). The system generates a temporary password and **shows it once in the response**. Copy it immediately and pass it to the user by an out-of-band channel; it cannot be retrieved later.
- **Reset password** — same flow as Create user: a new temporary password is generated and displayed once. The next time the user logs in, they are forced to change it (`must_change_password=True`).
- **Change role** — promotes a user to `power_user` or `admin`, or demotes back to `user`. Effective on their next login (existing tokens keep their original role claim until they expire — at most 1 hour).
- **Disable user** — sets `is_active=false`. The user can no longer log in; their existing tokens stop working as soon as `is_active` is checked by middleware. Their conversations are preserved.
- **Delete user** — permanent. Removes the user row. Conversations they authored are **not** automatically deleted — they remain in the database, anchored to the now-orphan user ID.

> **You cannot delete yourself.** The API refuses `DELETE /admin/users/<your-own-username>` to prevent locking the system out. To replace the bootstrap admin, create a second admin first, log in as that admin, then delete the original.

### 6.2 The temporary-password-shown-once gotcha

The single biggest source of admin-console support tickets: **temporary passwords are shown in plaintext in the HTTP response and never stored unhashed in the database**. If you close the browser tab without copying it, the only way to recover is to **reset the password again**, which produces a new temporary password.

This is intentional. The admin console never persists plaintext passwords on disk. Closing the modal without copying is the equivalent of writing a password on a sticky note and shredding it — you have to issue a new one.

*[Screenshot: "Password reset" modal showing the new temporary password in a monospaced font with a "Copy" button highlighted]*

## 7. OAuth2 Clients

The **OAuth Clients** tab is **admin-only**. It manages the credentials that programs (Spotfire client, scripts, CI/CD pipelines, agents) use to authenticate to the orchestrator without a human in the loop. Every machine-to-machine integration needs exactly one OAuth2 client.

*[Screenshot: OAuth Clients tab showing a table with columns Name, Client ID, Scopes, Status (Active/Disabled), Created, with a "Create Client" button]*

### 7.1 Creating a client

Click **Create Client**, then choose a **scope profile**:

- **`spotfire_client`** — for the Spotfire desktop / web client. Grants the scopes the client needs to call `/orchestrator`, manage threads, and read its own user's data.
- **`agent_developer`** — for someone building or testing a new A2A agent. Grants the agent-registry scopes.
- **`custom`** — pick scopes individually for a tight integration that doesn't fit the two profiles above.

On creation, the dialog shows the `client_id` and the **plaintext `client_secret`** once. The secret is bcrypt-hashed in the database immediately; **there is no way to retrieve it again**. Same rule as user passwords: copy it now, or regenerate.

### 7.2 Toggling and revoking

- **Toggle** flips `is_active` between `true` and `false` without deleting the row. Use this to temporarily quarantine a client (e.g. while you investigate a suspected leak) without destroying the audit trail of which integrations were configured.
- **Delete** removes the row entirely. The `client_id` is freed for re-use, but you almost never want to re-use one — generate a fresh client for the new integration.

### 7.3 Cross-reference

The exact `curl` commands for using these credentials — minting a token via `/client/token`, calling `/orchestrator`, supplying `Authorization: Bearer <token>` — are in **[§9](#9-rag-indexes) Authentication Guide** of the [Spotfire Copilot Installation Guide — Backend Infrastructure Setup](Spotfire%20Copilot%20-%20Installation%20Guide%20-%20Backend%20Setup.md). The admin console issues the credentials; the install guide explains how to use them.

## 8. Security and Password Policy

The **Security** tab is **admin-only**. Two things live here: the audit log and the password policy.

*[Screenshot: Security tab split into two panels — top shows a chronological list of security events; bottom shows a form with password policy settings]*

### 8.1 Security events

A chronological log of authentication-related events:

- `login_failure` — bad password.
- `login_success` — successful authentication (recorded for audit completeness).
- `account_locked` — too many failures in the window.
- `account_unlocked` — automatic at end of lockout window, or manual via user-management.
- `password_reset` — admin reset another user's password.
- `password_changed` — user changed their own.

Filter by event type, user, and date range. The default view is the most recent 100 events. Use this when investigating a suspected brute-force, a user reporting "I can't log in but I know my password is right" (almost always means lockout), or a compliance audit.

### 8.2 Password policy

Configure the orchestrator's password rules:

| Setting | Default | Effect |
|---------|---------|--------|
| Minimum length | 12 | Refuses any password shorter than this on creation or reset |
| Require uppercase | true | Must contain at least one A–Z |
| Require lowercase | true | Must contain at least one a–z |
| Require digit | true | Must contain at least one 0–9 |
| Require special character | true | Must contain at least one non-alphanumeric |
| Password expiry (days) | 90 | Forces a reset after this many days; set to 0 to disable |
| Max failed attempts | 5 | Triggers lockout after this many consecutive bad passwords |
| Lockout duration (minutes) | 30 | Length of the auto-lockout window |

Changes take effect on the **next** login attempt or password reset — already-issued JWTs are not retroactively invalidated.

### 8.3 Forcing a re-login

To forcibly log out a user who cannot log out themselves — for example after rotating stolen credentials — set `is_active=false` in **[§6](#6-user-management) User Management**. Middleware checks this on every request, so the token stops working immediately. Set it back to `true` once they’re ready to log in again with the new password.

To forcibly log out **everyone** (for example, after rotating the orchestrator's `SECRET_KEY`), restart the orchestrator. All previously-issued tokens are signed with the old key and will fail verification.

## 9. RAG Indexes

The **RAG Indexes** tab is visible to admins and power users. It is a thin proxy onto the orchestrator's knowledge-base management endpoints — the admin console does not talk to the vector database directly; it asks the orchestrator to do it.

*[Screenshot: RAG Indexes tab showing a list of collections with columns Name, Provider, Document count, Last enriched, plus a "Trigger enrichment now" button]*

What you can do:

- **List collections** — see every configured RAG collection (Milvus, pgvector, Bedrock KB, Azure Search, OpenSearch, etc. — whichever your `RAG_BACKEND` is set to).
- **List sources in a collection** — see which documents have been indexed, when they were last refreshed, and how many chunks each produced.
- **Rename a collection** — cosmetic only; updates the display name. The underlying vector-DB collection name is unchanged.
- **Trigger enrichment now** — bypasses the background daemon's schedule and runs the enrichment cycle immediately. Useful right after adding new source documents.

If this tab shows "RAG is not configured" or returns errors, the orchestrator is not configured with a RAG backend — see the **Knowledge Base & RAG Configuration** section of the [Spotfire Copilot Installation Guide — Backend Infrastructure Setup](Spotfire%20Copilot%20-%20Installation%20Guide%20-%20Backend%20Setup.md).

For the data-loading side of RAG (the data loaders that ingest your documents and turn them into vectors), see the [Spotfire Copilot Data Loaders Installation Guide](Spotfire%20Copilot%20-%20Data%20Loaders%20Installation%20Guide.md).

## 10. A2A Agents and Tunnels

### 10.1 A2A Agents tab

Lists every agent registered with the orchestrator's A2A (agent-to-agent) registry. Use this to:

- Confirm an agent your team is developing is visible to the orchestrator.
- Refresh the registry after adding a new agent.
- Mint a short-lived development token for testing an agent directly.
- Manually test an agent's `/.well-known/agent.json` endpoint from the browser.

*[Screenshot: A2A Agents tab with a list of registered agents and "Test", "Refresh", and "Dev Token" buttons]*

For the deeper architecture (when to register an agent here vs. running it inside the Domain Agents or Platform Integrations containers), see the [Agent Registry overview](https://community.spotfire.com/articles/spotfire/agent-registry-for-spotfire/).

### 10.2 Tunnels tab

Shows the live MCP (Model Context Protocol) tunnels currently open between Spotfire Copilot and bridged tools. Each tunnel represents one Spotfire client that has connected to give the orchestrator access to its local Spotfire instance for things like running data functions and reading the active analysis.

*[Screenshot: Tunnels tab showing a list of active tunnels with columns User, Tunnel ID, Opened, Last activity]*

You can't create tunnels here — they are opened by the Spotfire client when a user signs in. The tab is read-only and is most useful for:

- Confirming a user's Spotfire client has successfully connected after install.
- Debugging a "the agent says it can't read my Spotfire" support ticket.
- Spotting stale tunnels (high "Last activity" age) that haven't been cleaned up.

## 11. System Logs

The **System Logs** tab is **admin-only**. It tails container logs without needing to SSH into the host.

*[Screenshot: System Logs tab showing a dropdown of containers and a scrolling log viewer with timestamps]*

Available containers:

- `orchestrator-admin-console` — the admin console's own logs (served from in-memory buffer, no Docker socket required).
- `orchestrator` — the orchestrator service's logs.
- `orchestrator-postgres` — the database.

By default the last 100 lines are shown. Use this for first-line diagnosis before reaching for `docker logs` on the host.

> **Requirement for orchestrator and PostgreSQL logs:** the orchestrator container needs access to the Docker socket (or to its own in-memory log buffer as a fallback) so the admin console can proxy the request through. If you see `Log proxy unavailable` for those two sources but `orchestrator-admin-console` logs work fine, the Docker socket is the missing piece — see the deployment guide for your platform in the install guide.

## 12. Common Tasks

A cookbook of the most common operations, with the menu path to perform each.

### Add a new internal user

1. **User Management** → **Create User**.
2. Fill in email, username, full name. Set **Role** to `user` (or `power_user` if they need cross-user conversation visibility).
3. Click **Create**. **Copy the temporary password** from the response — it is not shown again.
4. Hand the password to the user via your normal secure channel (Slack DM, password manager share, in person).
5. The user logs in once; the orchestrator immediately forces them to choose their own password.

### Issue OAuth2 credentials for a new Spotfire client install

1. **OAuth Clients** → **Create Client**.
2. Pick the **`spotfire_client`** scope profile.
3. Click **Create**. **Copy `client_id` and `client_secret`** from the response.
4. Paste them into the Spotfire client's configuration screen on the user's workstation.
5. Test by signing in from the Spotfire client.

### Investigate "the chatbot gave the wrong answer"

1. **Conversations** → filter by the user's email or ID.
2. Click the thread to expand it.
3. Read the full exchange. Look at the assistant message metadata for which model was used, how many tokens were spent, which tool calls (if any) ran, and any summary checkpoints that may have compressed earlier turns.
4. If the answer came from RAG, check **[§9](#9-rag-indexes) RAG Indexes** to confirm the collection was up to date at the time.

### Reset a user's password

1. **User Management** → find the user → **Reset Password**.
2. Copy the new temporary password from the response.
3. Hand it to the user. They'll be forced to change it on next login.

### Lock down a leaked OAuth2 client

1. **OAuth Clients** → find the client → **Toggle** to disable it. The integration stops working within seconds (next token request returns 401).
2. Investigate. If genuinely compromised, **Delete** the client.
3. **Create Client** with the same scope profile to issue fresh credentials.
4. Hand the new credentials to the integration owner.

### Investigate a "can't log in" ticket

1. **Security** → filter events by the user's email.
2. Look for `account_locked` in the recent history — almost always the cause.
3. Either wait out the lockout window, or **User Management** → find the user → toggle them off and back on (this clears the lockout counter via the daemon's cleanup pass).
4. If there's no `account_locked` event, look for `login_failure` — if there are zero failures, the user isn't reaching the orchestrator at all (network / CORS / wrong URL).

### Investigate "RAG isn't returning my new document"

1. **RAG Indexes** → click the collection.
2. Check **Last enriched** — if it's older than when the new document was uploaded, the daemon hasn't picked it up yet.
3. Click **Trigger enrichment now**.
4. Wait for the next sources refresh; the new document should appear with a recent timestamp.

### Audit who's been logging in

1. **Security** → filter by `event_type=login_success`.
2. Export the table (right-click → Save as CSV in most browsers) for compliance evidence.

## 13. Troubleshooting

### `Incorrect username or password` when logging in as admin

The username for the bootstrap admin account is **`admin`**.

The password must be the **plaintext** that `generate_credentials.py` printed when you ran it (labelled "Plaintext (SAVE THIS)"). The bcrypt hash in `HASHED_ADMIN_PASSWORD` in `.env` is not the login password. If you have lost the plaintext, run `generate_credentials.py` again, put the new hash in `.env`, and restart the admin console container.

### `Account is temporarily locked` even though I haven't tried many times

Someone or something else has — automated tooling pointed at the wrong host, a stale Spotfire client trying to authenticate with the old password after a rotation, or a brute-force attempt. Check **[§8](#8-security-and-password-policy) Security and Password Policy → Security events** filtered by your email to see the failure source. Wait out the lockout window (30 minutes by default), or as an admin disable + re-enable the user account to clear the counter.

### Tabs are visible but every list is empty

You're logged in as a non-admin (most likely a standard `user`). Role-based filtering is showing you no data because there's nothing in scope. Log in as an admin to see the system view.

If you're logged in as an admin and lists are still empty, the database is genuinely empty (you've just installed) or the admin console can't reach PostgreSQL. Check **[§11](#11-system-logs) System Logs → `orchestrator-admin-console`** for connection errors.

### Dashboard tiles show zero

Most likely cause: the admin console started before PostgreSQL was ready and is caching the empty result. Reload the dashboard once the orchestrator is fully up. If the tiles stay at zero, check the admin-console logs for `DATABASE_URL` errors — `SECRET_KEY` and `DATABASE_URL` **must match exactly** between the orchestrator and admin console.

### `Log proxy unavailable` on the System Logs tab

The admin console proxies log requests for `orchestrator` and `orchestrator-postgres` through the orchestrator container, which needs the Docker socket mounted. The admin console's **own** logs (`orchestrator-admin-console`) never need the socket and should always work. If the admin-console logs work but the others don't, fix the Docker-socket mount on the orchestrator container.

### `403 Forbidden` after I just clicked a button

You're logged in as a **power user** or **standard user**, not an **admin**. Most write operations (user creation, OAuth2 management, security policy) are admin-only. Either log in as an admin or, if you should have admin rights, ask another admin to promote your account in **[§6](#6-user-management) User Management**.

### Token expired and I keep getting redirected to login

Tokens are valid for 1 hour and there is no silent refresh. Log in again. If this is interrupting long-running operations, consider running those via the REST API with an OAuth2 client token (1 hour but easy to script renewal) instead of the browser UI.

### Conversations show `[Content hidden — conversation privacy is enabled]`

That's intentional — your deployment has `HIDE_CONVERSATION_CONTENT=true` set. There is no per-user override; the redaction is at the server. If you need to read conversation contents and you have a legitimate reason to, change the env var on the admin console container and restart it. If you can't (regulated deployment), use the audit logs instead.
