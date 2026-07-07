# Spotfire Copilot™ Installation Guide — Frontend Setup

**Applies to: Spotfire Copilot version 2.3.x**

**Last updated: 23-June-2026**

---

## Table of Contents

- [Introduction](#introduction)
  - [Who Should Use This Guide](#who-should-use-this-guide)
  - [⚠️ Deploying to non-English users](#-deploying-to-non-english-users)
- [Prerequisites](#prerequisites)
- [Deploying the Spotfire Copilot Package](#deploying-the-spotfire-copilot-package)
  - [Accessing the Server Administration Console](#accessing-the-server-administration-console)
  - [Uploading the Package to a Deployment Area](#uploading-the-package-to-a-deployment-area)
  - [Updating Web Player Instances](#updating-web-player-instances)
- [Configuring Copilot Preferences](#configuring-copilot-preferences)
  - [Connecting to Spotfire Analyst as an Administrator](#connecting-to-spotfire-analyst-as-an-administrator)
  - [Setting Preferences via Administration Manager](#setting-preferences-via-administration-manager)
  - [Preference Reference](#preference-reference)
  - [Allowed RAG Indexes Format](#allowed-rag-indexes-format)
  - [Customizing the Welcome Buttons](#customizing-the-welcome-buttons)
  - [Configuring Copilot for Non-English Users (Localisation)](#configuring-copilot-for-non-english-users-localisation)
- [Licensing](#licensing)
  - [Enabling the Copilot Custom Panel License](#enabling-the-copilot-custom-panel-license)
- [Enabling the Copilot Panel in Spotfire Clients](#enabling-the-copilot-panel-in-spotfire-clients)
  - [Spotfire Analyst](#spotfire-analyst)
  - [Spotfire Web Player](#spotfire-web-player)
- [First Usage of Copilot](#first-usage-of-copilot)
  - [Starting a Conversation](#starting-a-conversation)
  - [Using Knowledge Bases](#using-knowledge-bases)
  - [External Agents](#external-agents)
  - [Supported Features](#supported-features)
  - [Supported Visualization Types](#supported-visualization-types)
- [Monitoring and Logging](#monitoring-and-logging)
  - [Log Format](#log-format)
- [Troubleshooting](#troubleshooting)
  - [Checking Active Preferences with `/status`](#checking-active-preferences-with-status)
  - ["Error posting to orchestrator"](#error-posting-to-orchestrator)
  - ["I'm sorry, I've become a bit stuck. Can you try again, rephrasing your question?"](#im-sorry-ive-become-a-bit-stuck-can-you-try-again-rephrasing-your-question)
  - [Visualization created with errors](#visualization-created-with-errors)
  - [Empty results from Specific Data Questions](#empty-results-from-specific-data-questions)
  - [RAG / User Docs results are missing or incomplete](#rag--user-docs-results-are-missing-or-incomplete)
  - [Explain Visualization results are vague or inaccurate](#explain-visualization-results-are-vague-or-inaccurate)
  - [Data Function has errors](#data-function-has-errors)
  - [Copilot seems "stuck" giving the same response](#copilot-seems-stuck-giving-the-same-response)
  - [Internal Server Error when setting licenses](#internal-server-error-when-setting-licenses)
- [Revision History](#revision-history)

---

## Introduction

This guide covers the Spotfire® frontend deployment and configuration of Spotfire Copilot™ version 2.3.x.

**Before beginning this guide**, ensure you have completed the [Part 1 — Backend Infrastructure Setup](../Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Installation%20Guide%20-%20Backend%20Setup.md) guide, which covers installation and configuration of the Copilot Orchestrator service.

This guide will walk you through:

- Deploying the Copilot SDN package to a Spotfire Server deployment area
- Updating Web Player service instances to pick up the new package
- Configuring Copilot preferences (orchestrator connection, RAG indexes, agents, etc.)
- Enabling the necessary licenses for users and groups
- Enabling the Copilot custom panel in Spotfire Analyst and Web Player clients

### Who Should Use This Guide

| Role | Responsibilities |
|------|-----------------|
| **Spotfire Server Administrator** | Deploy the package, update Web Player instances, configure preferences, assign licenses |
| **Spotfire Analyst / Power User** | Verify the panel is enabled, begin using Copilot features |

### ⚠️ Deploying to non-English users

If any of your users will interact with Copilot in a language other than English (Japanese, French, German, Spanish, Chinese, etc.), the default configuration is **not** sufficient — Copilot will reply in English even when the user types in another language. Two preferences must be changed; see *Configuring Copilot for Non-English Users (Localisation)* later in this guide for the full procedure.

---

## Prerequisites

Before you begin, confirm the following:

- The **Copilot Orchestrator** (backend) is installed, configured, and running. You should have the following values from the backend setup:
  - **Orchestrator Base URL** (e.g. `https://orchestrator.example.com:8443`)
  - **Orchestrator Client ID**
  - **Orchestrator Client Secret**
- You have **administrator access** to the Spotfire Server Administration console
- You have the appropriate **Spotfire Copilot SDN file** for your environment:
  - `SpotfireCopilot-windows-2.3.x-SF14.x-YYYY-MM-DD.HH-MM.sdn` — for Windows-based Spotfire Servers
  - `SpotfireCopilot-linux-2.3.x-SF14.x-YYYY-MM-DD.HH-MM.sdn` — for Linux-based Spotfire Servers
- You have the **Spotfire Analyst** desktop client installed (required for configuring preferences)

---

## Deploying the Spotfire Copilot Package

### Accessing the Server Administration Console

1. Open a web browser and navigate to your Spotfire Server Administration console. The URL typically follows this pattern:

   ```
   https://<your-server-hostname>/spotfire
   ```

2. Log in with an account that has **administrator privileges**.

   > *Screenshot placeholder: Spotfire Server login page*

3. In the left-hand navigation, click **Deployments & Packages**.

   > *Screenshot placeholder: Spotfire Server administration console showing Deployments & Packages in the navigation*

### Uploading the Package to a Deployment Area

You will see a list of existing deployment areas on your server. A deployment area is a named collection of packages that defines what software is available to clients that connect using that area.

4. **Choose a deployment area.** You have two options:

   - **Use an existing deployment area** — Select the area you want to add the Copilot package to.
   - **Create a new deployment area** — If you want to isolate Copilot to a specific group of users, it is recommended to **copy** an existing deployment area and give the copy a descriptive name (e.g. "Production - Copilot"). This ensures all existing packages are carried over.

   > **Important:** Copying a deployment area creates a copy on the *same* server. It does not copy the area to another server.

   > *Screenshot placeholder: Deployment areas list with "Copy" option highlighted*

5. With your target deployment area selected, click the **Add packages** button.

   > *Screenshot placeholder: Deployment area detail page showing the "Add packages" button*

6. In the file browser dialog, navigate to and select the Copilot SDN file (e.g. `SpotfireCopilot-windows-2.3.x-SF14.6-2026-04-23.sdn`). Click **Open** to upload.

   The upload may take a moment depending on file size and network speed.

7. Once the upload completes, review the list of packages. You should see the Copilot packages listed. Click the **Save area** button.

   > *Screenshot placeholder: Package list showing newly uploaded Copilot packages, with the "Save area" button highlighted*

8. Optionally edit the description for the deployment area (e.g. add "Includes Spotfire Copilot 2.3"), and confirm by clicking **Save area** again.

   > *Screenshot placeholder: Save area confirmation dialog*

The package is now deployed. Spotfire Analyst clients that connect to this deployment area will automatically download the Copilot extension on their next login.

### Updating Web Player Instances

If you use the **Spotfire Web Player**, you must explicitly update each Web Player service instance that uses the deployment area you just modified. The Web Player does not automatically pick up new packages — you must trigger an update.

1. In the Spotfire Server Administration console, navigate to **Nodes & Services** in the left-hand navigation.

   > *Screenshot placeholder: Administration console showing Nodes & Services in the left navigation*

2. On the **Network** page, expand the **Node managers** section. You will see a list of node managers with their associated services.

3. Click on the **node manager** that hosts the Web Player service you want to update.

4. In the list of services under that node manager, click on the **Web Player** service instance.

   > *Screenshot placeholder: Node manager expanded to show Web Player service instance*

5. In the upper-right pane, you will see details about the service including its current deployment. Look at the **Packages** pane — it will show notes indicating what has changed compared to the current deployment (e.g. "New: SpotfireDs.CopilotCustomPanel 2.3.x").

6. Click the **Update service** button in the upper-right corner.

   > *Screenshot placeholder: Service detail pane showing the "Update service" button and package change notes*

7. A confirmation dialog will appear. Review the changes and click **Update** to proceed.

8. The **Status** line in the upper-right pane will indicate the update has started. You can monitor the progress on the **Activity** page.

   > **Note:** The Web Player service will briefly become unavailable during the update. Plan accordingly for production environments.

9. **Repeat steps 3–8** for every Web Player service instance that uses the updated deployment area.

   > **Tip:** If you have multiple Web Player instances, consider scheduling the updates during a maintenance window. You can update instances one at a time to maintain availability if you have a load-balanced configuration.

---

## Configuring Copilot Preferences

Copilot preferences control the connection to the Orchestrator backend, RAG behavior, welcome messages, and more. These are managed through the Spotfire Administration Manager and apply at the **user group** level.

### Connecting to Spotfire Analyst as an Administrator

1. Launch **Spotfire Analyst** and connect to your Spotfire Server.
2. Log in with an account that has **administrator privileges**.
3. When prompted, select the **deployment area** that contains the Copilot package (the one you configured when deploying the package above).
4. Spotfire will download and install the Copilot package automatically on first use.

### Setting Preferences via Administration Manager

5. From the **Tools** menu, choose **Administration Manager…**

   > *Screenshot placeholder: Tools menu with Administration Manager highlighted*

6. Select the **Preferences** tab.

7. In the left-hand group tree, **choose a user group** to configure.

   - For a quick setup, you can select the **Everyone** group — this will make Copilot available to all users on the server.
   - For a more targeted rollout, create or select a specific group. User group management is covered in the [Spotfire Server and Administration Manual](https://docs.tibco.com/products/tibco-spotfire-server).

   > *Screenshot placeholder: Administration Manager showing the Preferences tab and group selection*

8. In the preferences tree on the right, expand **Copilot** → **Orchestrator Configuration**.

9. Click the **Edit** button to modify the preferences.

   > *Screenshot placeholder: Copilot > Orchestrator Configuration preferences with Edit button*

10. Enter the preference values as described in *Preference Reference* below. At a minimum, you must set:
    - **Orchestrator Base URL**
    - **Orchestrator Client ID**
    - **Orchestrator Client Secret**

11. Click **OK** to save the preferences.

### Preference Reference

The following table describes all available Copilot preferences. Required preferences are marked with (**Required**).

#### Connection Settings

| Preference | Type | Default | Description |
|-----------|------|---------|-------------|
| **Orchestrator Base URL** | String | *(empty)* | **(Required)** The base URL of the Copilot Orchestrator service. Example: `https://orchestrator.example.com:8443`. **Do not include a trailing slash.** |
| **Orchestrator Client ID** | String | *(empty)* | **(Required)** The OAuth client ID generated during Orchestrator setup. |
| **Orchestrator Client Secret** | String | *(empty)* | **(Required)** The OAuth client secret generated during Orchestrator setup. |

#### RAG (Retrieval-Augmented Generation) Settings

| Preference | Type | Default | Description |
|-----------|------|---------|-------------|
| **Spotfire Docs Index Name** | String | `spotfiredocs` | The name of the RAG index that Copilot queries for HowTo and Help answers. Only change this if your backend exposes the Spotfire documentation under a different index name (for example, an AWS Knowledge Base deployment). **If you accidentally clear this preference, set it back to `spotfiredocs`** — leaving it blank is treated as the default `spotfiredocs`, but an explicit value is recommended for clarity. |
| **Allowed RAG Indexes** | String | *(empty)* | Whitelist of RAG indexes that users in this group can access. Format: `indexName1:Display Name 1;indexName2:Display Name 2`. See *Allowed RAG Indexes Format* later in this section for details and examples. **If empty, all RAG indexes from the Orchestrator are available.** When set, only the listed indexes are shown to users — use this to control which user groups have access to which indexes. |
| **RAG Top K** | Integer | `5` | The number of document chunks to retrieve per RAG query. Higher values may improve answer quality at the cost of increased token usage. |
| **RAG Min Relevance Score** | Decimal | `0.50` | Minimum relevance score (0.0–1.0) for a retrieved document chunk to be included in the LLM context. Increase this to filter out low-quality matches; decrease to include more context. |
| **HowTo Document Filter Mapping** | String | `Analyst:SPOT_sfire_client_14_6.pdf;`<br>`Web:SPOT_sfire_web_client_14_4.pdf;`<br>`Copilot:SpotfireCopilotUserManual.pdf` | Maps Spotfire client types to source document filenames for HowTo RAG metadata filtering. This allows the HowTo feature to return answers specific to the client type (Analyst vs. Web Player vs. Copilot). Only change this if you have loaded different documentation PDFs into your RAG index. |

#### Chat & History Settings

| Preference | Type | Default | Description |
|-----------|------|---------|-------------|
| **Message History Size** | Integer | `10` | Number of previous exchanges (question + response pairs) to include when sending a request to the LLM. Higher values help the LLM maintain conversational context, but increase token usage and cost. |
| **Strip RAG Context from History** | Boolean | `true` | When enabled, large RAG context blocks are removed from conversation history before sending to the Orchestrator. This significantly reduces token usage. Recommended to leave enabled. |
| **Persist Chat History to Table** | Boolean | `false` | When enabled, chat conversations are saved to a temporary data table within the Spotfire analysis. Useful for debugging or auditing. The table is removed when the analysis file is saved. |

#### System Prompt Settings

| Preference | Type | Default | Description |
|-----------|------|---------|-------------|
| **System Prompts Set Name** | String | `SetA` | The system prompt set to use. Options: `SetA` (default, optimized for OpenAI models), `SetB` (alternative set — try this if you are using Claude or other non-OpenAI models), or `SetC` (**required for non-English deployments**; available from version 2.3.1 — see *Configuring Copilot for Non-English Users (Localisation)* later in this section; includes an explicit "reply in the user's language" instruction so that questions asked in Japanese, French, German, Spanish, Chinese, etc. receive replies in the same language). Leave empty to use `SetA`. |

#### Customization Settings

| Preference | Type | Default | Description |
|-----------|------|---------|-------------|
| **Customized Welcome Message** | String | *(empty)* | A custom message displayed when the Copilot panel is first opened. Use this to include your organization's legal disclaimers, usage guidelines, or a custom greeting. Leave empty to use the default welcome message. |
| **Customized Welcome Buttons** | String[] | *(empty)* | Override the default welcome buttons with a custom JSON document. See *Customizing the Welcome Buttons* later in this section for the format and examples. If provided, this completely replaces the default welcome buttons. |

#### External Agent Settings

| Preference | Type | Default | Description |
|-----------|------|---------|-------------|
| **Allowed Agents** | String | *(empty)* | Whitelist of external agent names that users in this group may access. Agents are registered with the Orchestrator and appear in the `/` slash-command intent picker in the chat input. **If empty, all agents registered with the Orchestrator are available.** When set, only the listed agents are shown — use this to control which user groups have access to which agents. Format: `agent1;agent2;agent3` |

### Allowed RAG Indexes Format

The **Allowed RAG Indexes** preference uses a semicolon-separated format:

```
indexName1:Display Name 1;indexName2:Display Name 2
```

#### Examples

**Single index:**
```
my-company-docs:Company Documentation
```

> **Note:** When specifying only one index, do not add a trailing semicolon.

**Multiple indexes:**
```
engineering-docs:Engineering Manuals;safety-docs:Safety Procedures;training:Training Materials
```

**Using non-guessable index names (recommended for security):**

If you segment indexes by user group and want to prevent users from guessing another group's index name, use GUIDs:

```
176a6a1d-dd19-493b-8394-257710a4db9f:Engineering Docs;e3b1ccd1-f720-4644-a377-74fcbd996fd5:Safety Docs
```

### Customizing the Welcome Buttons

You can customize the welcome buttons that appear when the Copilot panel is first opened. The JSON document must be placed in the **Customized Welcome Buttons** preference.

> For non-English deployments, see *Configuring Copilot for Non-English Users (Localisation)* below — the localised welcome buttons described here must be paired with the `SetC` system prompts to ensure Copilot replies in the user's language.

> **Important:** The JSON must be wrapped in triple backticks with the `json` language tag. This is mandatory:
>
> ````
> ```json
> { ... }
> ```
> ````

#### Default Welcome Buttons

The following JSON represents the standard welcome buttons shipped with Copilot 2.3. Use this as a starting point for customization:

```json
{
  "operations": [
    {
      "operationTarget": "user",
      "operationType": "Suggest How To questions",
      "buttonClass": "centered",
      "operationParameters": {
        "questionText": "Suggest some How To questions",
        "intent": "SuggestHowToQuestions"
      }
    },
    {
      "operationTarget": "user",
      "operationType": "What questions can I ask of my data?",
      "buttonClass": "centered",
      "operationParameters": {
        "questionText": "What questions can I ask of my data?",
        "intent": "DataStructure"
      }
    },
    {
      "operationTarget": "user",
      "operationType": "Describe my data",
      "buttonClass": "centered",
      "operationParameters": {
        "questionText": "What should I be looking at in my data?",
        "intent": "DataStructure"
      }
    },
    {
      "operationTarget": "user",
      "operationType": "Explain visualization",
      "buttonClass": "centered",
      "operationParameters": {
        "questionText": "Explain a visualization",
        "intent": "ExplainVisualization"
      }
    },
    {
      "operationTarget": "user",
      "operationType": "Explain page",
      "buttonClass": "centered",
      "operationParameters": {
        "questionText": "Explain the current page",
        "intent": "InterpretPageData"
      }
    }
  ]
}
```

#### JSON Structure

| Field | Description |
|-------|-------------|
| `operations` | Array of button definitions |
| `operationTarget` | Must be `"user"` for clickable buttons |
| `operationType` | The **dispatch key** that selects the backend handler. Must be one of the recognised English strings listed below. Also used as the button label when `operationParameters.buttonText` is not provided. |
| `buttonClass` | Visual style. Use `"centered"` for standard buttons |
| `operationParameters.buttonText` | *(Optional)* Overrides the visible button label. Use this to localise the button text while keeping `operationType` as the English dispatch key. |
| `operationParameters.questionText` | The prompt text sent to Copilot when the button is clicked |
| `operationParameters.intent` | *(Optional)* Forces a specific intent. If omitted, Copilot determines the intent automatically |

#### Recognised `operationType` values

These are the English keys the backend dispatches on (case-insensitive). Pick the one whose behaviour you want and use `buttonText` to control what the user sees:

| `operationType` | Behaviour |
|------|-----------|
| `Suggest How To questions` | Asks the LLM to suggest a few "How To" questions |
| `What questions can I ask of my data?` | Suggests data questions based on the loaded tables |
| `Describe my data` *(or any string containing `"describe"` or `"sample"`)* | Generic sample/describe handler — sends `questionText` with optional `intent` |
| `Explain visualization` | Explains the active visualization |
| `Explain page` | Explains all visualizations on the current page |

> If `operationType` is not one of the above (and does not contain `"sample"` or `"describe"`), the click will fail with *"Something has gone wrong"*.

#### Localised example (full Japanese translation of the default buttons)

The following is a complete Japanese equivalent of the default English welcome buttons shown above. Use this as a starting point for any localisation — keep the `operationType` and `intent` values **exactly as shown** (they are English dispatch keys, not user-visible text), and translate only `buttonText` and `questionText`.

> **Reminder:** For non-English deployments you must also set the **System Prompts Set Name** preference to `SetC` (see *Configuring Copilot for Non-English Users (Localisation)* below). Localised buttons alone are not sufficient — without `SetC` the model may still reply in English.

```json
{
  "operations": [
    {
      "operationTarget": "user",
      "operationType": "Suggest How To questions",
      "buttonClass": "centered",
      "operationParameters": {
        "buttonText": "How-Toの質問を提案して",
        "questionText": "How-Toの質問をいくつか提案して",
        "intent": "SuggestHowToQuestions"
      }
    },
    {
      "operationTarget": "user",
      "operationType": "What questions can I ask of my data?",
      "buttonClass": "centered",
      "operationParameters": {
        "buttonText": "データにどんな質問ができる？",
        "questionText": "私のデータに対してどんな質問ができますか？",
        "intent": "DataStructure"
      }
    },
    {
      "operationTarget": "user",
      "operationType": "Describe my data",
      "buttonClass": "centered",
      "operationParameters": {
        "buttonText": "データを説明して",
        "questionText": "このデータで注目すべき点は何ですか？",
        "intent": "DataStructure"
      }
    },
    {
      "operationTarget": "user",
      "operationType": "Explain visualization",
      "buttonClass": "centered",
      "operationParameters": {
        "buttonText": "ビジュアライゼーションを説明して",
        "questionText": "このビジュアライゼーションを説明して",
        "intent": "ExplainVisualization"
      }
    },
    {
      "operationTarget": "user",
      "operationType": "Explain page",
      "buttonClass": "centered",
      "operationParameters": {
        "buttonText": "ページを説明して",
        "questionText": "現在のページを説明して",
        "intent": "InterpretPageData"
      }
    }
  ]
}
```

#### Valid Intent Values

| Intent | Description |
|--------|-------------|
| `HowTo` | Answer a "How To" question about Spotfire |
| `KnowledgeBase` | Query the knowledge base / RAG documentation |
| `DataStructure` | Describe the data structure |
| `ExplainVisualization` | Explain a visualization |
| `InterpretPageData` | Explain all visualizations on the page |
| `CreateVisualization` | Create a visualization |
| `SpecificDataQuestion` | Ask a specific data question |
| `SuggestHowToQuestions` | Suggest How To questions |

### Configuring Copilot for Non-English Users (Localisation)

By default, Copilot is configured for English-speaking users: the system prompts do not instruct the model to reply in the user's language, and the welcome buttons that bootstrap the conversation are written in English. As a result, a deployment that uses the defaults will reply in English even when users type in Japanese, French, German, Spanish, Chinese, or any other language.

To deploy Copilot for non-English users, configure **both** of the following preferences for the relevant user group (Administration Manager → Preferences → Copilot → Orchestrator Configuration):

#### Step 1 — Set the system prompts to `SetC`

Change the **System Prompts Set Name** preference from its default (`SetA`) to:

```
SetC
```

`SetC` is identical to `SetA` in capability but adds an explicit *"reply in the same language as the user's question"* instruction across all intents. Without `SetC`, the model will frequently default to English regardless of the input language. `SetC` was introduced in version 2.3.1 and is not available in 2.3.0.

#### Step 2 — Provide localised welcome buttons

The welcome buttons that appear when a user first opens the Copilot panel are what bootstrap the conversation's language: the first message Copilot sees often comes from clicking a welcome button, and if that button text is English, the conversation starts in English.

Set the **Customized Welcome Buttons** preference to a localised JSON document. See *Customizing the Welcome Buttons* above for the format and a complete Japanese example that you can adapt for any language.

When localising:

- Translate **only** the `buttonText` (visible label) and `questionText` (prompt sent to Copilot) values.
- Keep `operationType` and `intent` values **exactly** as shown in the default English JSON — these are dispatch keys read by the backend, not user-visible text. Translating them will cause buttons to fail with *"Something has gone wrong"*.

#### Verifying the configuration

After saving the preferences and reopening Spotfire Analyst (or refreshing the Web Player):

1. The welcome buttons in the Copilot panel should appear in the target language.
2. Click a localised welcome button. Copilot's response should be in the same language.
3. Type a free-text question in the target language. The reply should also be in that language.

If Copilot still replies in English, confirm that **both** preferences are set on the group the test user belongs to — setting one without the other will not work.

---

## Licensing

### Enabling the Copilot Custom Panel License

Copilot requires a specific license to be enabled for each user group that will use it.

> **Important:** You must enable licenses at the **Spotfire Extensions** group level first, then expand and enable the **Copilot Custom Panel** sub-license. Enabling only the Copilot sub-license without the parent group will result in an Internal Server Error.

1. In the **Administration Manager**, select the **Groups and Licenses** tab.

   > *Screenshot placeholder: Administration Manager showing the Groups and Licenses tab*

2. In the group tree on the left, select the user group you want to enable Copilot for.

3. On the right-hand side, select the **Licenses** tab.

4. Click **Edit**.

   > *Screenshot placeholder: License editing dialog*

5. Scroll to the **Spotfire Extensions** license group.

6. **Enable** the top-level **Spotfire Extensions** checkbox.

7. **Expand** the Spotfire Extensions group and **enable** the **Copilot Custom Panel** license.

   > *Screenshot placeholder: Expanded Spotfire Extensions license group showing Copilot Custom Panel checked*

8. Click **OK** to save.

9. **Close and reopen Spotfire Analyst** for the license changes to take effect.

---

## Enabling the Copilot Panel in Spotfire Clients

The Copilot is a **Custom Panel** in Spotfire. It may not be visible by default. The steps to enable it are the same for both Spotfire Analyst and Spotfire Web Player.

### Spotfire Analyst

1. Right-click on the **toolbar area** in Spotfire and choose **Customize toolbar…**

   > *Screenshot placeholder: Right-click context menu showing "Customize toolbar..."*

2. In the customization dialog, locate the **Custom Panels** section.

3. Check the box next to **Copilot Panel**.

   > *Screenshot placeholder: Customize toolbar dialog showing Copilot Panel under Custom Panels*

4. Click **OK**. The Copilot icon will now appear in your toolbar.

### Spotfire Web Player

1. In the Web Player, click the **panels** icon or navigate to the panel settings.

2. Enable the **Copilot Panel** from the list of available custom panels.

> **Note:** Each user must enable the panel individually in their own client. You may wish to communicate this step to your users when rolling out Copilot.

---

## First Usage of Copilot

### Starting a Conversation

Copilot is available only when a Spotfire analysis file is open and data has been loaded. If no analysis or data is present, the Copilot panel will not be functional.

1. Open a Spotfire analysis file (or load data into a new analysis).
2. Click the **Copilot** icon in the toolbar to open the panel.
3. Copilot will display a welcome message along with a set of quick-action buttons.

   > *Screenshot placeholder: Copilot panel showing welcome message and default buttons*

You can click one of the suggested quick-action buttons, or type your own question in the text box at the bottom of the panel.

### Using Knowledge Bases

Copilot supports **Knowledge Bases** — document indexes registered with the Orchestrator that you can query using natural language. Your administrator controls which knowledge bases are available via the **Allowed RAG Indexes** preference (see *Configuring Copilot Preferences* earlier in this guide).

To query a knowledge base, type `@` in the chat input. A picker will appear listing all available indexes. Select one and type your question — the `@IndexName` tag in the message shows which knowledge base will be queried. You can add more than one `@` tag to a single message to query multiple indexes at once.

> **Note:** Knowledge base selection is per-message. There is no persistent mode to switch back from — every message independently uses the knowledge base(s) you tag with `@`, or Copilot's standard capabilities if no `@` tag is present.

### External Agents

Copilot 2.3 supports **external agents** — specialized AI agents registered with the Orchestrator that can handle domain-specific tasks. If your administrator has configured agents, you invoke one by typing `/` in the chat input and selecting the agent (e.g. `/AgentName`) from the intent picker that appears, then typing your question. The Copilot routes that message directly to the chosen agent through the Orchestrator instead of running the default intent-detection flow.

### Supported Features

Spotfire Copilot 2.3 supports the following capabilities:

| Feature | Description | How to Activate |
|---------|-------------|----------------|
| **HowTo** | Answer common questions about Spotfire functionality | Ask a question, e.g. *"How do I add layers to a map chart?"* |
| **Knowledge Base** | Answer questions from your organization's document indexes | Type `@` in the chat input and select the knowledge base from the picker |
| **Create Visualization** | Create visualizations from natural language | e.g. *"Show sales over time"* or *"Create a bar chart showing yield by lot"* |
| **Modify Visualization** | Adjust an existing Copilot-created visualization | e.g. *"Change it to a line chart"* or *"Add color by region"* |
| **Explain Visualization** | Analyze a visualization for outliers, trends, and patterns | Type `/` in the chat input and select **Explain Visualization** from the intent picker, then select the visual |
| **Explain Page** | Analyze all visualizations on the current page | Type `/` in the chat input and select **Explain Page** from the intent picker |
| **Specific Data Question** | Query your data using natural language (Copilot generates and executes SQL) | e.g. *"What is my highest performing store?"* |
| **Data Structure** | Describe the tables, columns, and general structure of your data | e.g. *"Describe my data"* or *"What should I be looking at?"* |
| **Create Data Function** | Generate a Python data function with defined inputs and outputs | e.g. *"Create a function to normalize my numeric columns"* |
| **Suggest Table Relations** | Recommend how to join multiple data tables | Appears automatically when 2+ tables are loaded, or click the suggestion button |
| **Example Questions** | Get AI-generated questions relevant to your data | e.g. *"What questions can I ask of my data?"* |
| **Copy Responses** | Copy any Copilot response to clipboard for use in reports or text areas | Click the copy icon on any response |

### Supported Visualization Types

Copilot 2.3 can create and modify the following visualization types:

| Visualization | Example Prompt |
|--------------|---------------|
| Bar Chart / Stacked Bar Chart | *"Create a bar chart showing revenue by region"* |
| Line Chart | *"Show the trend of temperature over time"* |
| Scatter Plot | *"Plot height vs weight"* |
| Pie Chart | *"Show market share as a pie chart"* |
| Combination Chart | *"Show revenue as bars and profit as a line"* |
| Cross Table | *"Create a cross table of product by quarter"* |
| Table | *"Show the raw data in a table"* |
| Summary Table | *"Summarize the statistics for each group"* |
| Treemap | *"Create a treemap of sales by category"* |
| Heat Map | *"Show a heatmap of correlation between variables"* |
| Box Plot | *"Create a box plot of scores by department"* |
| Waterfall Chart | *"Show a waterfall of budget changes"* |
| 3D Scatter Plot | *"Create a 3D scatter plot of X, Y, and Z"* |
| KPI Chart | *"Create a KPI showing total revenue"* |
| Parallel Coordinate Plot | *"Show a parallel coordinates plot of my numeric columns"* |

Modification capabilities for existing Copilot-created visualizations include:

- Changing axis columns or expressions (including aggregations)
- Changing the visualization type
- Changing bar chart orientation
- Changing bar chart stack mode
- Adding or changing color-by columns

---

## Monitoring and Logging

If your Spotfire Server has **Action Logging** enabled, Copilot writes user interactions to the server audit log.

For information on enabling and configuring action logging, see the [Spotfire Server Action Logging documentation](https://docs.tibco.com/pub/spotfire_server/latest/doc/html/TIB_sfire_server_tsas_admin_help/server/topics/action_logs_and_system_monitoring.html).

### Log Format

Copilot log entries follow the standard Spotfire action log format. The Copilot-specific fields include:

```
<timestamp>;<client-ip>;<username>;<timestamp>;<server-ip>;<client-type>;
<copilot-action>;<success>;<analysis-id>;<session-id>;<analysis-path>;
<user-prompt>;<detected-intent>;<additional-ids>...
```

**Copilot-specific action values** include:

| Action | Description |
|--------|-------------|
| `copilot_post_user_message` | User sent a free-text message |
| `copilot_sample_question` | User clicked a sample/welcome button |
| `copilot_specific_data_question_ask` | User asked a specific data question |
| `copilot_explain_visualization` | User requested explain visualization |
| `copilot_explain_page` | User requested explain page |

**Example log entry:**

```
2026-04-23T10:15:07,096-0400;10.0.0.5;jsmith;2026-04-23T10:15:07,094-0400;
10.113.0.165;analysis_wp;copilot_post_user_message;true;
92fe8c42-c7cc-375f-b7c5-4fd8200627b8;f73d3df4-92fc-40e9-9a1f-04e15a6b2c82;
/Shared/Sales Dashboard;Show revenue by region;intent_CreateVisualization;...
```

> **Note:** Action logging from Copilot is evolving. The action names and logged fields may change in future versions. Not all Copilot interactions are covered (e.g. clicking welcome buttons to create visualizations may not be logged). Your feedback on this feature is welcome.

---

## Troubleshooting

### Checking Active Preferences with `/status`

If Copilot is not connecting to the Orchestrator, is showing unexpected behaviour, or you simply want to confirm that a preference change has taken effect, the `/status` command shows the effective runtime values that Copilot is actually using — after Spotfire has resolved them through its group hierarchy.

**To run it:** Type `/status` in the Copilot chat input and click the "start/send" button. Just pressing Enter doesn't send this special command.

Copilot will display a diagnostic table:

| Field | What it shows |
|-------|---------------|
| **Server URL** | The Orchestrator Base URL in use. If this is empty, the **Orchestrator Base URL** preference has not reached the current user — see *Preference hierarchy* below. |
| **Client ID** | The OAuth2 Client ID in use. If empty or incorrect, authentication will fail with HTTP 401. |
| **Client Secret** | Shown masked (first two and last two characters visible, e.g. `ab****xy`). Sufficient to confirm the right secret is loaded without exposing it. |
| **Thread ID** | The current conversation thread identifier used by the Orchestrator. Shows `(none)` before the first message of a session is sent. Include this value when reporting issues to the Copilot team. |
| **Message History Size** | The number of prior exchanges that will be sent to the LLM. Reflects the **Message History Size** preference. |
| **Prompt Set** | The active system prompt set (`SetA`, `SetB`, or `SetC`). For non-English deployments this must be `SetC`. |

#### Preference hierarchy

Spotfire resolves preferences through a group hierarchy: a user inherits preferences from every group they belong to, and a more specific (child) group's value overrides the same preference on a more general (parent) group. The **Everyone** group sits at the root of the hierarchy.

If `/status` shows unexpected values — for example, an empty **Server URL** when you believe the preference is configured — the most likely cause is that the preference was set on a group the current user is not a member of. Check Administration Manager → Preferences → Copilot → Orchestrator Configuration for each group the user belongs to and confirm the preference is saved there.

Common mismatches to look for:

- **Server URL is empty** — The **Orchestrator Base URL** preference was not saved on a group covering this user. It may have been set on the wrong group, or the user was added to the target group after the preference was configured.
- **Prompt Set shows `SetA`** when you expect `SetC` — The **System Prompts Set Name** preference is either not set or set to `SetA` on the group used to resolve this user's preferences. Non-English deployments require `SetC`.
- **Client Secret is `(empty)`** — No client secret has been configured for this user's resolved group. Authentication will fail.

> **Note:** `/status` reflects the values loaded when the **current session** started. If you have changed preferences in Administration Manager, close and reopen Spotfire Analyst (or, for Web Player, sign out and back in) to reload them — the updated values will then be visible in a fresh `/status` check.

### "Error posting to orchestrator"

**Cause:** The Spotfire client cannot communicate with the Orchestrator service.

**Steps:**
1. Open the Spotfire **notifications panel** to see the detailed error.
2. **HTTP 401 (Unauthorized):** Verify that the Orchestrator Client ID and Client Secret in Copilot preferences are correct and have not expired.
3. **HTTP 429 (Rate Limit):** The underlying LLM has rate-limited requests. Wait a moment and try again. If this occurs frequently, contact your Orchestrator administrator about rate limit configuration.
4. **Connection refused / timeout:** Verify the Orchestrator Base URL is correct and reachable from the Spotfire client. Check for firewall rules or proxy configurations.

### "I'm sorry, I've become a bit stuck. Can you try again, rephrasing your question?"

**Cause:** Copilot could not determine a suitable way to answer your question.

**Steps:**
1. Try rephrasing the question more specifically.
2. Click the new conversation icon (pencil) at the top of the Copilot panel to reset the conversation context, then try again.
3. If the issue persists, report the question and context to the Copilot team.

### Visualization created with errors

**Cause:** The LLM generated an invalid visualization specification.

**Steps:**
1. The error will appear in the visualization area. Note the error message.
2. Try providing more context, e.g. specify column names explicitly: *"Create a bar chart with 'Region' on the X-axis and 'Revenue' on the Y-axis"*.
3. Report persistent issues to the Copilot team.

### Empty results from Specific Data Questions

**Cause:** The generated SQL query did not match the data structure or returned zero rows.

**Steps:**
1. Respond in the chat with feedback like *"the table came back empty"* or describe what you expected. Copilot will attempt to self-correct.
2. Try phrasing the question differently with more explicit references to column names visible in your data.
3. Use *"Describe my data"* first to help Copilot understand your data structure.

### RAG / User Docs results are missing or incomplete

**Cause:** Data loading may not have completed successfully, or the relevance threshold is filtering out results.

**Steps:**
1. Verify that the data loading process (from the [Part 1 — Backend Infrastructure Setup](../Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Installation%20Guide%20-%20Backend%20Setup.md) guide) completed successfully.
2. Try lowering the **RAG Min Relevance Score** preference (e.g. from 0.5 to 0.3).
3. Try increasing the **RAG Top K** preference (e.g. from 5 to 10).
4. Ensure the index name in the **Allowed RAG Indexes** preference matches the index created during backend setup.

### Explain Visualization results are vague or inaccurate

**Cause:** The LLM interprets a screenshot of the visualization. Complex or cluttered visuals may not be interpreted well.

**Steps:**
1. Try enlarging the visualization before requesting the explanation.
2. Add labels, gridlines, or adjust colors to improve visual clarity.
3. Simplify the visualization (e.g. reduce the number of series or data points).

### Data Function has errors

**Cause:** The LLM-generated Python code contains bugs or references unavailable libraries.

**Steps:**
1. Copy and paste the error message into the chat — Copilot will attempt to debug it.
2. Check that required Python packages are installed in your Spotfire data function execution environment.

### Copilot seems "stuck" giving the same response

**Steps:**
1. Click ⋮ → **New Topic** to clear the conversation context.
2. Alternatively, click ⋮ → **Clear** to fully reset the panel.
3. Ask your question again with fresh context.

### Internal Server Error when setting licenses

**Cause:** The Copilot Custom Panel license was enabled without first enabling the parent **Spotfire Extensions** license.

**Steps:**
1. In Administration Manager → Groups and Licenses → Licenses → Edit, enable the **Spotfire Extensions** checkbox at the top level first.
2. Then expand the group and enable the **Copilot Custom Panel** sub-license.

---

## Revision History

| Date | Author(s) | Copilot Version | Changes |
|------|-----------|----------------|---------|
| 23-June-2026 | Andrew Berridge | 2.3.4 | Removed all references to the obsolete ⋮ (three-dot) menu: replaced the *Modes and RAG Indexes* section with *Using Knowledge Bases* (describes the `@` per-message knowledge base picker); updated Supported Features table rows for Knowledge Base, Explain Visualization, and Explain Page; updated Troubleshooting to reference the new-conversation pencil icon instead of ⋮ → New Topic. |
| 22-June-2026 | Andrew Berridge | 2.3.4 | Added *Checking Active Preferences with `/status`* to the Troubleshooting section: describes the `/status` diagnostic command, the table of effective runtime values it displays, and guidance on diagnosing Spotfire preference group hierarchy mismatches. |
| 18-June-2026 | Andrew Berridge | 2.3.4 | Corrected the External Agents description: agents are invoked via the `/` slash-command intent picker in the chat input, not from the mode selector. Updated both the **Allowed Agents** preference description and the *External Agents* section under *First Usage of Copilot*. |
| 18-June-2026 | Andrew Berridge | 2.3.4 | Clarified the **Spotfire Docs Index Name** preference description: noted that an empty value falls back to `spotfiredocs` (defensive guard added in code) and that admins should restore `spotfiredocs` if cleared. |
| 18-June-2026 | Andrew Berridge | 2.3.4 | Documentation cleanup: removed obsolete `DoNotUse:Do Not Use` workaround from the Allowed RAG Indexes section (the original parser bug is fixed); promoted localisation guidance to its own *Configuring Copilot for Non-English Users (Localisation)* subsection with a step-by-step procedure; restructured for the published renderer (removed the Table of Contents, dropped section numbers from headings, folded Appendix A and Appendix B into the *Configuring Copilot Preferences* section, and replaced all intra-document anchor links with plain-text references); linked the Part 1 — Backend guide to its community URL. |
| 03-June-2026 | Andrew Berridge | 2.3.4 | Bumped applicability to 2.3.4. Includes: `respect_marking` fix for Spotfire 14.0 (single `_InternalRowIndex() IN (…)` injection path; works identically on 14.0, 14.6 and 14.8); fix for `#page` reference being misclassified as Explain Visualization; new marking-topology introspection (document markings + visualization data binding); Web Player page-resolution fix for sample-question / suggestion clicks. |
| 02-June-2026 | Andrew Berridge | 2.3.0 / 2.3.1 | Marked applicability as 2.3.0 and 2.3.1. Flagged non-English deployment guidance (`SetC`, localised welcome buttons, Japanese Appendix A example) as **2.3.1 only**. |
| 02-June-2026 | Andrew Berridge | 2.3 | Added non-English deployment guidance: callout in Introduction, `SetC` documented in System Prompts Set Name preference, full Japanese translation of the default welcome buttons in Appendix A. |
| 23-April-2026 | Andrew Berridge | 2.3 | Complete rewrite for v2.3. Added new preferences (Allowed Agents, RAG Top K, RAG Min Relevance Score, Strip RAG Context from History, HowTo Document Filter Mapping, Spotfire Docs Index Name). Added external agents documentation. Updated supported visualization types (added Table, KPI, Parallel Coordinate). Added Suggest Table Relations feature. Expanded Web Player deployment instructions. Restructured document for clarity. |
| 09-June-2025 | Andrew Berridge | 2.1 | Initial preferences information |
| 28-July-2025 | Andrew Berridge | 2.1 | Final preferences information |

---

> **Disclaimer:** Spotfire Copilot relies on large language model (LLM) technology. Like all generative AI systems, results may occasionally be inaccurate or unexpected. Users should always verify Copilot's outputs. Please report any issues to the Spotfire Copilot team.

---

*Copyright © 2026 Cloud Software Group, Inc.*
