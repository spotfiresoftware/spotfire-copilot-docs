# Spotfire Copilot — Admin Console Guide

> **Versions covered:** 2.3.0, 2.3.1, 2.3.2, and 2.3.4 &nbsp;|&nbsp; **Last updated:** 16 September 2026 &nbsp;|&nbsp; **Applies to:** Admin Console (companion service to the orchestrator)
>
> This guide is for **customer administrators** who need to operate the Spotfire Copilot admin console day-to-day — managing users, OAuth2 clients, conversations, token budgets, rules, RAG indexes, and system health. For installing or deploying the admin console alongside the orchestrator, see the [Spotfire Copilot Installation Guide — Backend Infrastructure Setup](Spotfire%20Copilot%20-%20Installation%20Guide%20-%20Backend%20Setup.md).

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
  - [5.3 Monthly token budgets (OAuth2 clients)](#53-monthly-token-budgets-oauth2-clients)
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
- [10. Rules (Custom Prompts)](#10-rules-custom-prompts)
  - [10.1 What rules are](#101-what-rules-are)
  - [10.2 Scope model — how rules resolve](#102-scope-model--how-rules-resolve)
  - [10.3 Creating rules — two paths](#103-creating-rules--two-paths)
  - [10.4 The Rules tab UI](#104-the-rules-tab-ui)
  - [10.5 Promotions — widening a rule's scope](#105-promotions--widening-a-rules-scope)
  - [10.6 Who can do what](#106-who-can-do-what)
- [11. A2A Agents, MCP Servers, and Tunnels](#11-a2a-agents-mcp-servers-and-tunnels)
  - [11.1 A2A Agents tab](#111-a2a-agents-tab)
  - [11.2 MCP Servers tab](#112-mcp-servers-tab)
  - [11.3 Tunnels tab](#113-tunnels-tab)
- [12. System Logs](#12-system-logs)
- [13. Common Tasks](#13-common-tasks)
  - [Add a new internal user](#add-a-new-internal-user)
  - [Issue OAuth2 credentials for a new Spotfire client install](#issue-oauth2-credentials-for-a-new-spotfire-client-install)
  - [Investigate "the chatbot gave the wrong answer"](#investigate-the-chatbot-gave-the-wrong-answer)
  - [Reset a user's password](#reset-a-users-password)
  - [Lock down a leaked OAuth2 client](#lock-down-a-leaked-oauth2-client)
  - [Investigate a "can't log in" ticket](#investigate-a-cant-log-in-ticket)
  - [Investigate "RAG isn't returning my new document"](#investigate-rag-isnt-returning-my-new-document)
  - [Audit who's been logging in](#audit-whos-been-logging-in)
  - [Set or top up an OAuth2 client's monthly token budget](#set-or-top-up-an-oauth2-clients-monthly-token-budget)
  - [Promote a user's personal rule to their whole group](#promote-a-users-personal-rule-to-their-whole-group)
  - [Register a new MCP tool server](#register-a-new-mcp-tool-server)
- [14. Troubleshooting](#14-troubleshooting)
  - [`Incorrect username or password` when logging in as admin](#incorrect-username-or-password-when-logging-in-as-admin)
  - [`Account is temporarily locked` even though I haven't tried many times](#account-is-temporarily-locked-even-though-i-havent-tried-many-times)
  - [Tabs are visible but every list is empty](#tabs-are-visible-but-every-list-is-empty)
  - [Dashboard tiles show zero](#dashboard-tiles-show-zero)
  - [`Log proxy unavailable` on the System Logs tab](#log-proxy-unavailable-on-the-system-logs-tab)
  - [`403 Forbidden` after I just clicked a button](#403-forbidden-after-i-just-clicked-a-button)
  - [Token expired and I keep getting redirected to login](#token-expired-and-i-keep-getting-redirected-to-login)
  - [Conversations show `[Content hidden — conversation privacy is enabled]`](#conversations-show-content-hidden--conversation-privacy-is-enabled)
  - [A power user can see Rules but Approve/Reject buttons 403](#a-power-user-can-see-rules-but-approvereject-buttons-403)
  - [An OAuth2 client keeps getting `token_budget_exceeded`](#an-oauth2-client-keeps-getting-token_budget_exceeded)
  - [`'id' is required` or a 400 when registering an MCP server](#id-is-required-or-a-400-when-registering-an-mcp-server)

---

## 1. What the Admin Console Is (and Isn't)

The **admin console** is a browser-based **operations dashboard** for Spotfire Copilot. It runs as a companion container next to the orchestrator and shares its PostgreSQL database. It is **not** a chat interface — end users never see it. It is the tool your operations team uses to keep the orchestrator running smoothly.

### What it does

- **User management** — create users, assign roles, reset passwords, enable/disable accounts.
- **OAuth2 client management** — issue and revoke machine-to-machine credentials for Spotfire clients, scripts, and CI/CD integrations.
- **Conversation monitoring** — read across all users' conversations to investigate support issues, study usage, and audit activity.
- **Token usage analytics** — track LLM token spend per user and per client.
- **Token budget enforcement** — set, top up, and monitor monthly token budgets per OAuth2 client.
- **Rules (custom prompts)** — manage hierarchical, scoped prompt rules that agents fold into their own system prompts, including the promotion workflow for widening a rule's scope.
- **RAG index management** — list knowledge-base collections, view indexed sources, trigger enrichment.
- **A2A agent registry** — view and manage agents the orchestrator routes to.
- **MCP server registry** — register and manage remote MCP tool servers agents can call, including credentials and per-group/per-client access restrictions.
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

Nothing here is configurable. If a tile shows `0` or `—`, see **[§14](#14-troubleshooting) Troubleshooting → Dashboard tiles show zero**.

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

### 5.3 Monthly token budgets (OAuth2 clients)

Below the per-user chart, the Token Usage tab lists every **OAuth2 client** with a bar graph per month: usage vs. the client's monthly token budget. This is where budget restrictions are configured and monitored — there is no separate "Budgets" tab.

*[Screenshot: Token Usage tab, OAuth2 client section, showing a monthly bar for a client with a budget line marker and a "✏️ Set budget" button, plus an "over budget" bar highlighted in red]*

**Scope of enforcement — read this first:**

- Budgets apply **only to OAuth2 clients** (machine-to-machine callers — the Spotfire client, scripts, CI/CD, agents). Human end-user sessions are **never** budget-limited.
- A client only has a budget if you set one. By default `monthly_token_budget` is unset (`NULL`) — **unlimited** — and the client shows no budget bars, just a plain "Unlimited" summary.
- Budget checks **fail open**: if the database is unreachable when checking, the request is allowed and a warning is logged. Budgets must never be able to take the orchestrator down.

**Setting or clearing a budget:**

1. Find the client in the Token Usage tab's OAuth2 client list.
2. Click **✏️ Set budget**.
3. Enter a monthly token cap (a non-negative integer), or leave it blank to make the client **unlimited** again.
4. Confirm. The new cap applies to the **current** calendar month immediately.

**Temporary top-ups ("extend"):**

- Use **Extend** to add a one-off bonus on top of the recurring `monthly_token_budget` for the **current month only** — useful when a client is about to hit its cap mid-month and you don't want to raise its permanent allowance.
- The bonus (`current_period_bonus`) auto-expires at month rollover; it does not carry over or change the recurring base budget.
- Extending a client that has an **unlimited** budget has no effect (there's nothing to top up).

**How usage is measured and enforced:**

| Term | Meaning |
|------|---------|
| `monthly_token_budget` | The recurring base allowance for the client, per calendar month (UTC). `NULL` = unlimited. |
| `current_period_bonus` | A temporary top-up added for the current month only (see **Extend**, above). |
| Effective budget | `monthly_token_budget + current_period_bonus`. This is the number actually enforced and drawn as the budget line in the bar chart. |
| Warning threshold | Once usage crosses **90%** of the effective budget (configurable via the orchestrator's `TOKEN_BUDGET_WARN_PCT` env var), successful API responses to that client carry a `token_budget.warning: true` flag so well-behaved callers can self-throttle before they're cut off. |

- Enforcement is a **pre-request, soft check**: a client already at or over budget is rejected with `HTTP 422` (`error_type: token_budget_exceeded`) *before* the LLM call runs, so a single in-flight request can still overshoot slightly (usage is only known after the call completes) — this is expected and bounded.
- `429` is **not** used for budget exhaustion (that status is reserved for upstream LLM provider rate limits); budget exhaustion is always `422`.

> **Known display caveat:** the bar chart here recomputes usage by summing the `messages` table, while live enforcement uses a fast running counter (`current_period_tokens`) incremented per-request. The two can drift slightly apart. If you need the number that's actually being enforced, don't rely on this tab — check the client's `token_budget` field on a live orchestrator response instead.

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

## 10. Rules (Custom Prompts)

The **Rules** tab manages hierarchical, scoped prompt fragments — the mechanism for "always answer in metric units", "never show the cost column to this group", "for this DXP, prefer the well-log agent", and similar standing instructions that shouldn't have to be retyped into every conversation.

*[Screenshot: Rules tab showing stat tiles (Total/Active/Disabled/Unused), a filter bar, and a table with columns Scope, Applies to, Rule, Used, Last used, Status, Actions]*

Unlike User Management, OAuth Clients, and Security, this tab is **not admin-only** — it's visible and usable by both **admins and power users**. Approving a scope-widening request (see **[§10.5](#105-promotions--widening-a-rules-scope)**) is the one action that additionally requires a **human** admin/power-user account.

### 10.1 What rules are

A rule is a short block of text (up to 5,000 characters) stored in Postgres and resolved against the current request's context (group / user / document / library folder / intent). The orchestrator itself does **not** inject rules into prompts — a downstream agent calls `GET /rules/prompt` for its context and folds the returned text into its own system prompt. If a support ticket claims "the chatbot ignored my rule," first confirm the agent that answered actually calls the rules endpoint — not every agent does.

### 10.2 Scope model — how rules resolve

A rule can be narrowed along up to five independent dimensions:

| Dimension | Field | Matching |
|-----------|-------|----------|
| Group | `group_id` | Exact match against the caller's Spotfire group(s) |
| User | `user_id` | Exact match against the calling end-user |
| Document | `document_id` | Exact match against the `.dxp` analysis ID |
| Library folder | `library_path` | Prefix match (e.g. `/Teams/Reservoir/` matches everything under it) |
| Intent | `intent` | Exact match against the classified intent of the request |

Resolution is **most-specific-wins**: when multiple rules apply to a request, the one combining the most/narrowest dimensions is used first (e.g. a rule scoped to *this user + this document + this intent* beats one scoped to *this user* alone, which beats one scoped to *the user's group*, which beats a fully **global** rule with no dimensions set). Up to `max_rules` (default 10) applicable rules are returned, most-specific first — a request can be governed by several rules stacked together, not just one.

### 10.3 Creating rules — two paths

There are two distinct ways a rule gets created, with different scope limits:

1. **Self-service, via the Spotfire client** — end users can define their own rules (e.g. "always show me results in bbl, not m³") through the client, which relays the request to the orchestrator's `POST /rules`. This path **always** creates a rule owned by and scoped to that calling user — optionally narrowed further by document, library path, or intent. It can **never** create a group- or global-scoped rule directly.
2. **Directly in the admin console** — admins and power users are already elevated humans, so the **New Rule** button in this tab can create a rule at **any** scope, including group-wide or fully global, in one step. Use this for organization-wide standing instructions (e.g. "never fabricate a well name — say you don't have the data").

The **New Rule** modal collects: rule text (required), and optional Group, User, Document/DXP ID, Library folder path, and Intent to narrow it, plus an optional "primary group" (recorded as `owner_primary_group` — the group a later promotion of this rule would target).

### 10.4 The Rules tab UI

- **Stat tiles** — Total, Active, Disabled, and Unused (rules with `usage_count = 0`) rule counts.
- **Filters** — group, user, document, library path, intent, and an "active only" checkbox; **Clear Filters** resets them.
- **Table columns** — Scope (badge, e.g. `user global`, `group doc intent`), Applies to (the concrete dimension values), Rule (truncated preview, full text on hover), Used (usage count), Last used, Status, and row actions:
  - **✏️ Edit** — change the rule text, toggle active/disabled, or update the recorded owner primary group. Scope dimensions are **immutable** once created — to change them, delete the rule and recreate it with the new dimensions.
  - **⏸️/▶️ Toggle** — enable/disable without deleting (and without losing usage history).
  - **🗑️ Delete** — permanent.

### 10.5 Promotions — widening a rule's scope

A rule created via the self-service path is locked to its owner's scope. To widen it (e.g. promote a personal rule to the owner's whole group, or to global), the owner — or an admin/power user — **proposes a promotion**:

1. The owner (or an elevated user) calls `POST /rules/{rule_id}/propose-promotion` with the target scope and a reason.
2. This queues a **pending promotion**; the original self-scoped rule keeps applying unchanged while it waits.
3. A **human** admin or power user reviews it in the **Pending Promotions** panel at the top of the Rules tab and either:
   - **✅ Approve** — the live rule is immediately widened to the new scope, or
   - **❌ Reject** — requires a typed reason; the rule is left untouched at its original scope.
4. Every decision is recorded in **Promotion History** below (filterable by status: pending / approved / rejected) as an audit trail — who proposed it, who decided, and why.

Two things worth calling out:

- **A group promotion always targets the rule's recorded `owner_primary_group`** — the group the trusted Spotfire client relayed when the rule was first created. A user cannot redirect their promotion request into a group they don't belong to.
- **Approve/Reject requires a human account.** Machine callers (OAuth2 clients relaying an end-user's identity) can *propose* a promotion but can never approve one — that would let a machine client silently grant itself an org-wide rule. If a power user's Approve button 403s, see **[§14](#14-troubleshooting) Troubleshooting**.

### 10.6 Who can do what

| Action | Who |
|--------|-----|
| Create a self-scoped rule (via Spotfire client) | Any authenticated end user |
| Create a rule at any scope (admin console) | Admin or power user |
| Edit or delete a rule | The rule's owner, or an admin/power user |
| Propose a promotion | The rule's owner, or an admin/power user |
| Approve or reject a promotion | Admin or power user — **human account only**, never an OAuth2 client |

## 11. A2A Agents, MCP Servers, and Tunnels

Three separate tabs, all **admin-only**, cover three distinct kinds of "things the orchestrator connects to": agents it routes to (A2A Agents), remote tool servers it calls (MCP Servers), and Spotfire clients that have connected to it (Tunnels). It's easy to conflate the last two because both use the MCP protocol — the difference is *direction*: MCP Servers are tool providers the orchestrator calls out to; Tunnels are Spotfire clients that called in.

### 11.1 A2A Agents tab

Lists every agent registered with the orchestrator's A2A (agent-to-agent) registry. Use this to:

- Confirm an agent your team is developing is visible to the orchestrator.
- Refresh the registry after adding a new agent.
- Mint a short-lived development token for testing an agent directly.
- Manually test an agent's `/.well-known/agent.json` endpoint from the browser.

*[Screenshot: A2A Agents tab with a list of registered agents and "Test", "Refresh", and "Dev Token" buttons]*

For the deeper architecture (when to register an agent here vs. running it inside the Domain Agents or Platform Integrations containers), see the [Agent Registry overview](https://community.spotfire.com/articles/spotfire/agent-registry-for-spotfire/).

### 11.2 MCP Servers tab

The **MCP Servers** tab is a registry of remote **Model Context Protocol** tool servers — external endpoints exposing tools (e.g. a GitHub-tools server, an internal data-quality service) that agents can call. This is separate from both the A2A Agents registry (whole agents, not individual tools) and the Tunnels tab (client-initiated connections, not admin-registered ones).

*[Screenshot: MCP Servers tab showing stat tiles (Total/Active/Disabled/Restricted) and a table with columns ID, URL, Auth, Tools, Access, Status, Actions]*

**Registering a server** (**Register Server** button):

- **Server ID** — a slug agents reference to call this server's tools (e.g. `github-tools`). Must be unique.
- **Endpoint URL** — validated with the same SSRF guard used for A2A agent endpoints; URLs pointing at disallowed targets (e.g. internal metadata services) are rejected at registration time.
- **Description** — optional, free text.
- **Default tool kind** — `read` or `write`, used to classify a tool's safety **only when the tool itself doesn't declare a `readOnlyHint`**. Get this wrong and a destructive tool may be treated as safe-to-auto-approve, so default to `write` unless you know every tool on the server is read-only.
- **Authentication** — `none`, `API Key`, `Bearer Token`, or `OAuth2 Client Credentials`, each with its own credential fields. Credentials are **encrypted at rest**; the edit form never redisplays them — it shows a "credentials configured" banner instead, and fields are filled in only to *replace* the existing secret.
- **Access control** — optional `allowed_groups` and/or `allowed_clients` (comma-separated) whitelists. Leaving **both** blank makes the server **public** — any authenticated caller's agent may use its tools; setting either restricts use to the listed Spotfire groups or OAuth2 client IDs.

**Row actions:**

- **✏️ Edit** — change URL, description, default kind, credentials, or access-control whitelists.
- **🧪 Test** — a connectivity probe: the admin console asks the orchestrator to connect to the server and list its tools, then reports success/failure. Credentials are never echoed back in the result.
- **⏸️/▶️ Toggle** — enable/disable without losing the registration or its credentials.
- **🗑️ Delete** — permanent; removes the registration (and its encrypted credentials) entirely.

Stat tiles: **Total**, **Active**, **Disabled**, and **Restricted** (servers with at least one group/client whitelist entry).

### 11.3 Tunnels tab

Shows the live MCP (Model Context Protocol) tunnels currently open between Spotfire Copilot and bridged tools. Each tunnel represents one Spotfire client that has connected to give the orchestrator access to its local Spotfire instance for things like running data functions and reading the active analysis.

*[Screenshot: Tunnels tab showing a list of active tunnels with columns User, Tunnel ID, Opened, Last activity]*

You can't create tunnels here — they are opened by the Spotfire client when a user signs in. The tab is read-only and is most useful for:

- Confirming a user's Spotfire client has successfully connected after install.
- Debugging a "the agent says it can't read my Spotfire" support ticket.
- Spotting stale tunnels (high "Last activity" age) that haven't been cleaned up.

## 12. System Logs

The **System Logs** tab is **admin-only**. It tails container logs without needing to SSH into the host.

*[Screenshot: System Logs tab showing a dropdown of containers and a scrolling log viewer with timestamps]*

Available containers:

- `orchestrator-admin-console` — the admin console's own logs (served from in-memory buffer, no Docker socket required).
- `orchestrator` — the orchestrator service's logs.
- `orchestrator-postgres` — the database.

By default the last 100 lines are shown. Use this for first-line diagnosis before reaching for `docker logs` on the host.

> **Requirement for orchestrator and PostgreSQL logs:** the orchestrator container needs access to the Docker socket (or to its own in-memory log buffer as a fallback) so the admin console can proxy the request through. If you see `Log proxy unavailable` for those two sources but `orchestrator-admin-console` logs work fine, the Docker socket is the missing piece — see the deployment guide for your platform in the install guide.

## 13. Common Tasks

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

### Set or top up an OAuth2 client's monthly token budget

1. **Token Usage** → scroll to the OAuth2 client's row.
2. To set a permanent monthly cap (or remove one): click **✏️ Set budget**, enter a token count, or leave it blank for unlimited.
3. To handle a one-off overage without changing the permanent cap: click **Extend** and enter a temporary top-up — it applies to the current month only and expires automatically at month rollover.
4. Confirm the change took effect by checking the client's bar for the current month; the effective budget line should reflect base + bonus.

### Promote a user's personal rule to their whole group

1. Have the owner (or an admin/power user on their behalf) call `POST /rules/{rule_id}/propose-promotion` with the target scope (typically `group`) and a reason — this is normally done by the trusted Spotfire client, not typed directly into the admin console.
2. **Rules** → **Pending Promotions** → find the request.
3. Review the rule text and the scope change (current → proposed).
4. **✅ Approve** to widen it immediately, or **❌ Reject** with a reason to leave it unchanged.
5. Check **Promotion History** afterward to confirm the decision was recorded.

### Register a new MCP tool server

1. **MCP Servers** → **Register Server**.
2. Fill in a unique **Server ID** (the slug agents will reference), the **Endpoint URL**, and an optional description.
3. Set **Default tool kind** to `read` only if you're certain every tool on that server is non-destructive; otherwise leave it at `write`.
4. If the server requires authentication, pick the auth type and fill in its credential fields — these are encrypted before being stored.
5. Optionally restrict usage with **Access control** (allowed groups and/or allowed OAuth2 client IDs); leave both blank to make it public.
6. Click **Register**, then use **🧪 Test** on the new row to confirm the orchestrator can reach it and list its tools.

## 14. Troubleshooting

### `Incorrect username or password` when logging in as admin

The username for the bootstrap admin account is **`admin`**.

The password must be the **plaintext** that `generate_credentials.py` printed when you ran it (labelled "Plaintext (SAVE THIS)"). The bcrypt hash in `HASHED_ADMIN_PASSWORD` in `.env` is not the login password. If you have lost the plaintext, run `generate_credentials.py` again, put the new hash in `.env`, and restart the admin console container.

### `Account is temporarily locked` even though I haven't tried many times

Someone or something else has — automated tooling pointed at the wrong host, a stale Spotfire client trying to authenticate with the old password after a rotation, or a brute-force attempt. Check **[§8](#8-security-and-password-policy) Security and Password Policy → Security events** filtered by your email to see the failure source. Wait out the lockout window (30 minutes by default), or as an admin disable + re-enable the user account to clear the counter.

### Tabs are visible but every list is empty

You're logged in as a non-admin (most likely a standard `user`). Role-based filtering is showing you no data because there's nothing in scope. Log in as an admin to see the system view.

If you're logged in as an admin and lists are still empty, the database is genuinely empty (you've just installed) or the admin console can't reach PostgreSQL. Check **[§12](#12-system-logs) System Logs → `orchestrator-admin-console`** for connection errors.

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

### A power user can see Rules but Approve/Reject buttons 403

This is by design, not a bug. Viewing and editing rules only requires `admin` or `power_user`, but **approving or rejecting a promotion requires a human account with that role** — an OAuth2 client (even one with the right scopes) is deliberately excluded, so a machine relaying end-user identity can never grant itself an org-wide rule. If the signed-in account genuinely is a human admin/power user and still gets 403, check that they're logged in via the dashboard login form (not a token minted for a machine client) — see **[§3](#3-roles-and-permissions) Roles and Permissions**.

### An OAuth2 client keeps getting `token_budget_exceeded`

The client has hit its monthly token cap. This only ever happens to OAuth2 clients — never to end-user sessions. Options, in **[§5.3](#53-monthly-token-budgets-oauth2-clients) Token Usage → Monthly token budgets**:

- **Extend** the client's budget for the rest of the current month (temporary top-up), or
- **Set budget** to raise the recurring `monthly_token_budget`, or clear it entirely for unlimited use.

The error is `HTTP 422`, not `429` — if you see `429` instead, that's an upstream LLM provider rate limit, not a budget issue, and raising the budget won't help.

### `'id' is required` or a 400 when registering an MCP server

- **`'id' is required` / `'url' is required`** — both the Server ID and Endpoint URL are mandatory; the Server ID must also be unique (a duplicate returns `409 Conflict`, not `400`).
- **`400` naming a URL validation failure** — the endpoint URL failed the same SSRF guard used for A2A agent endpoints (it blocks things like internal-only hosts, link-local/metadata addresses, and disallowed schemes). Point the registration at a URL your admin console/orchestrator network is actually allowed to reach, or ask your platform team to review the SSRF allowlist if the target is legitimate.
- **`422 Invalid credentials`** — the fields for the selected auth type didn't validate (e.g. OAuth2 selected but the token URL was left blank). Re-open the auth-type dropdown and confirm every required field for that type is filled in.
