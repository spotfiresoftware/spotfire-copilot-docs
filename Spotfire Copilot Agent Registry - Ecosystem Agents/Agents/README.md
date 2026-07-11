# Ecosystem Agent User Guides

End-user guides for the A2A agents hosted by the [Agent Server Deployment](../Agent%20Server%20Deployment/README.md) (a LangGraph DeepAgents server). Each agent depends on a backing [MCP server](../MCP%20Servers/README.md); both the agent server and the agent's MCP server must be reachable before the agent can be invoked from the Spotfire Copilot Panel.

The **Backing MCP server** column links to that server's user guide (its deployment guide sits in the same folder). Servers marked **External** are consumed by the agent but not documented in this section. For the full pairing with A2A agent ids and env prefixes, see the [section capability matrix](../README.md#capability-matrix).

| Agent | What it does | Backing MCP server |
|-------|--------------|--------------------|
| [OSDU Agent](Spotfire%20Copilot%20-%20OSDU%20Agent%20User%20Guide.md) | Explores wells, wellbores, datasets, schemas, and lineage on an OSDU data platform. | [OSDU MCP Server](../MCP%20Servers/OSDU/Spotfire%20Copilot%20-%20OSDU%20MCP%20Server%20User%20Guide.md) |
| [Databricks Agent](Spotfire%20Copilot%20-%20Databricks%20Agent%20User%20Guide.md) | Explores Unity Catalog metadata, traces table lineage, and runs SQL against Databricks. | [Databricks MCP Server](../MCP%20Servers/Databricks/Spotfire%20Copilot%20-%20Databricks%20MCP%20Server%20User%20Guide.md) |
| [Databricks Genie Agent](Spotfire%20Copilot%20-%20Databricks%20Genie%20Agent%20User%20Guide.md) | Answers natural-language data questions through a Databricks Genie space. | `databricks-genie` — External |
| [Data Virtualization (DV) Agent](Spotfire%20Copilot%20-%20Data%20Virtualization%20%28DV%29%20Agent%20User%20Guide.md) | Discovers data sources, tables, and columns via Data Virtualization and runs OData v4 queries. | [Data Virtualization (DV) MCP Server](../MCP%20Servers/Data%20Virtualization%20%28DV%29/Spotfire%20Copilot%20-%20Data%20Virtualization%20%28DV%29%20MCP%20Server%20User%20Guide.md) |
| [Snowflake Agent](Spotfire%20Copilot%20-%20Snowflake%20Agent%20User%20Guide.md) | Runs SQL and Cortex-powered analytics and search against Snowflake. | `snowflake` — External |
| [Spotfire Library Metadata Agent](Spotfire%20Copilot%20-%20Spotfire%20Library%20Metadata%20Agent%20User%20Guide.md) | Browses a Spotfire Server library: discovers connectors and DXPs and returns detailed DXP metadata. | [Spotfire Library MCP Server](../MCP%20Servers/Spotfire%20Library/Spotfire%20Copilot%20-%20Spotfire%20Library%20MCP%20Server%20User%20Guide.md) |
| [Spotfire License Management Agent](Spotfire%20Copilot%20-%20Spotfire%20License%20Management%20Agent%20User%20Guide.md) | Inspects the Spotfire license catalog and entitlements, and assigns or revokes group licenses. | [Spotfire License MCP Server](../MCP%20Servers/Spotfire%20License/Spotfire%20Copilot%20-%20Spotfire%20License%20MCP%20Server%20User%20Guide.md) |
| [Tavily Web Search Agent](Spotfire%20Copilot%20-%20Tavily%20Web%20Search%20Agent%20User%20Guide.md) | AI-powered web research: general search, direct-answer search with citations, and recent news. | [Tavily MCP Server](../MCP%20Servers/Tavily/Spotfire%20Copilot%20-%20Tavily%20MCP%20Server%20User%20Guide.md) |
| [Daily Drilling Reports (DDR) Agent](Spotfire%20Copilot%20-%20Daily%20Drilling%20Reports%20%28DDR%29%20Agent%20User%20Guide.md) | Answers Daily Drilling Report questions against the DDR Neo4j knowledge graph. | [Energy DDR Neo4j MCP Server](../MCP%20Servers/Energy%20DDR%20Neo4j/Spotfire%20Copilot%20-%20Energy%20DDR%20Neo4j%20MCP%20Server%20User%20Guide.md) |

## See also

- [Agent Server Deployment](../Agent%20Server%20Deployment/README.md) — deploy the server that hosts these agents.
- [MCP Servers](../MCP%20Servers/README.md) — consume or deploy the MCP backends each agent requires.
