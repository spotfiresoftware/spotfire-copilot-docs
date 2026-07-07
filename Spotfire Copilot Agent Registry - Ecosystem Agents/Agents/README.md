# Ecosystem Agent User Guides

End-user guides for the A2A agents hosted by the [LangGraph DeepAgents](../LangGraph%20DeepAgents%20Servers/README.md) agent server. Each agent depends on a backing [MCP server](../MCP%20Servers/README.md); both the agent server and the agent's MCP server must be deployed before the agent can be invoked from the Spotfire Copilot Panel.

| Agent | What it does |
|-------|--------------|
| [OSDU Agent](Spotfire%20Copilot%20-%20OSDU%20Agent%20User%20Guide.md) | Explores wells, wellbores, datasets, schemas, and lineage on an OSDU data platform. |
| [Databricks Agent](Spotfire%20Copilot%20-%20Databricks%20Agent%20User%20Guide.md) | Explores Unity Catalog metadata, traces table lineage, and runs SQL against Databricks. |
| [Databricks Genie Agent](Spotfire%20Copilot%20-%20Databricks%20Genie%20Agent%20User%20Guide.md) | Answers natural-language data questions through a Databricks Genie space. |
| [Data Virtualization (DV) Agent](Spotfire%20Copilot%20-%20Data%20Virtualization%20%28DV%29%20Agent%20User%20Guide.md) | Discovers data sources, tables, and columns via Data Virtualization and runs OData v4 queries. |
| [Snowflake Agent](Spotfire%20Copilot%20-%20Snowflake%20Agent%20User%20Guide.md) | Runs SQL and Cortex-powered analytics and search against Snowflake. |
| [Spotfire Library Metadata Agent](Spotfire%20Copilot%20-%20Spotfire%20Library%20Metadata%20Agent%20User%20Guide.md) | Browses a Spotfire Server library: discovers connectors and DXPs and returns detailed DXP metadata. |
| [Spotfire License Management Agent](Spotfire%20Copilot%20-%20Spotfire%20License%20Management%20Agent%20User%20Guide.md) | Inspects the Spotfire license catalog and entitlements, and assigns or revokes group licenses. |
| [Tavily Web Search Agent](Spotfire%20Copilot%20-%20Tavily%20Web%20Search%20Agent%20User%20Guide.md) | AI-powered web research: general search, direct-answer search with citations, and recent news. |
| [Daily Drilling Reports (DDR) Agent](Spotfire%20Copilot%20-%20Daily%20Drilling%20Reports%20%28DDR%29%20Agent%20User%20Guide.md) | Answers Daily Drilling Report questions against the DDR Neo4j knowledge graph. |

## See also

- [LangGraph DeepAgents Servers](../LangGraph%20DeepAgents%20Servers/README.md) — deploy the agent server that hosts these agents.
- [MCP Servers](../MCP%20Servers/README.md) — deploy the MCP backends each agent requires.
