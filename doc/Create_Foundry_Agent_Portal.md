# Create the Foundry Agent via the Portal (GCC / no `az login`)

This guide recreates exactly what
[agent/scripts/create_foundry_agent.py](../agent/scripts/create_foundry_agent.py)
does, but using the **Azure AI Foundry portal** UI instead of the Python script.
Use this when you can't run the script (e.g. GCC environments where Cloud Shell
`az login` / data-plane access is restricted).

It **replaces Step 11** ("Register the Foundry agent") of
[Deploy_ContainerApp_Guide.md](./Deploy_ContainerApp_Guide.md).

---

## What you're building

A prompt agent named `safety-intelligence-bot` on model `gpt-5.2`, with 4 tools:

| Tool | Type | Purpose |
|---|---|---|
| Azure AI Search | Knowledge | Grounds answers on the `safety-docs` index |
| `nl2sql` | Custom function | Read-only T-SQL against the `vw_SafetyIntel_*` views |
| `chart_spec` | Custom function | Turn nl2sql rows into a Vega-Lite chart |
| `dashboard_spec` | Custom function | Assemble multiple result sets into a dashboard |

> The function tools only declare the **schema**. The actual `nl2sql` /
> `chart_spec` / `dashboard_spec` execution happens inside the Container App —
> no code goes in the portal.

---

## Step 1 — Open the project

1. Go to the Foundry portal:
   - GCC: `https://ai.azure.us`
   - Commercial: `https://ai.azure.com`
2. Open your project (`srgsib-prj`, or the customer's project).
3. Left menu → **Agents** → **+ New agent** (or **Create**).

## Step 2 — Basic settings

- **Name:** `safety-intelligence-bot`
- **Deployment / Model:** select `gpt-5.2` (must already be deployed in the project).

## Step 3 — Instructions

Paste the combined contents of these two repo files into the **Instructions**
box, in this order:

1. All of [agent/prompts/system.md](../agent/prompts/system.md)
2. A separator line `---`
3. All of [agent/prompts/nl2sql_examples.md](../agent/prompts/nl2sql_examples.md)

(That's exactly what the script concatenates.)

## Step 4 — Add the Azure AI Search tool

1. In the agent's **Knowledge / Tools** section → **+ Add** → **Azure AI Search**.
2. **Connection:** the project's AI Search connection (e.g. `srgsib-search-conn`).
3. **Index:** `safety-docs`
4. **Query type:** `Semantic`
5. **Top K:** `8`

## Step 5 — Add the 3 custom function tools

Tools → **+ Add** → **Custom function** (a.k.a. Function tool). Paste each JSON
definition below, one per tool.

### Tool 1 — `nl2sql`

```json
{
  "name": "nl2sql",
  "description": "Run a single read-only T-SQL SELECT against the vw_SafetyIntel_* views in Synapse. Use for any structured data question (counts, lists, trends). Do NOT use for free-text/document questions.",
  "parameters": {
    "type": "object",
    "properties": {
      "sql": {
        "type": "string",
        "description": "A single T-SQL SELECT statement. Must reference only vw_SafetyIntel_* views. No DML/DDL, no chained statements."
      }
    },
    "required": ["sql"],
    "additionalProperties": false
  }
}
```

### Tool 2 — `chart_spec`

```json
{
  "name": "chart_spec",
  "description": "Convert tabular rows from a prior nl2sql call into a Vega-Lite chart spec. MUST be called AFTER nl2sql and MUST pass the actual rows returned by nl2sql in the `rows` argument — never an empty array.",
  "parameters": {
    "type": "object",
    "properties": {
      "intent": {
        "type": "string",
        "enum": ["bar", "line", "pie", "area", "scatter", "heatmap", "table"],
        "description": "Visualization type. Use 'line'/'area' for trends over time, 'bar' for categorical comparisons, 'pie' for share of whole, 'heatmap' for 2-D distributions, 'table' for raw lists."
      },
      "rows": {
        "type": "array",
        "items": { "type": "object" },
        "minItems": 1,
        "description": "Array of row objects returned by nl2sql. MUST contain at least one row; never pass an empty array."
      },
      "x": { "type": "string", "description": "Column name for the x-axis (optional; auto-picked if omitted)." },
      "y": { "type": "string", "description": "Column name for the y-axis / measure (optional; auto-picked if omitted)." },
      "color": { "type": "string", "description": "Column name for color encoding / series split (optional)." },
      "title": { "type": "string", "description": "Chart title (optional)." }
    },
    "required": ["intent", "rows"],
    "additionalProperties": false
  }
}
```

### Tool 3 — `dashboard_spec`

```json
{
  "name": "dashboard_spec",
  "description": "Assemble multiple related result sets from prior nl2sql calls into a single operations-dashboard artifact for occurrence monitoring screens. Use for runway incursion, bird strike, or similar cockpit-style dashboards.",
  "parameters": {
    "type": "object",
    "properties": {
      "title": { "type": "string", "description": "Dashboard title." },
      "domain": { "type": "string", "description": "Domain name such as runway_incursion or bird_strike." },
      "focus": { "type": "string", "description": "Short user-facing focus statement." },
      "datasets": {
        "type": "array",
        "minItems": 1,
        "description": "Named datasets assembled from prior nl2sql responses.",
        "items": {
          "type": "object",
          "properties": {
            "name": { "type": "string", "description": "Dataset role such as overview, tracks, hotspots, alerts, tactical_audit, or recent_records." },
            "title": { "type": "string", "description": "Optional dataset title." },
            "rows": {
              "type": "array",
              "items": { "type": "object" },
              "description": "The actual rows returned by nl2sql for this dataset."
            }
          },
          "required": ["name", "rows"],
          "additionalProperties": false
        }
      }
    },
    "required": ["datasets"],
    "additionalProperties": false
  }
}
```

## Step 6 — Save

Click **Save / Create**. Note the agent name `safety-intelligence-bot`.

## Step 7 — Wire it to the Container App

Set this env var on the Container App so it calls the agent you just made:

```bash
az containerapp update -g "$APP_RG" -n "$APP_NAME" \
  --set-env-vars FOUNDRY_AGENT_NAME=safety-intelligence-bot
```

---

## Notes

- The AI Search tool returns results only once the `safety-docs` index is built;
  agent **creation** itself works without it.
- Keep the agent name in sync with the `FOUNDRY_AGENT_NAME` env var on the
  Container App.
- If you later need to update the instructions or tools, edit the agent in the
  portal and **Save** — no redeploy of the Container App is required.
