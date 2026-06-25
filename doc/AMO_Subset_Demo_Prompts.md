# Demo Prompts — AMO-Subset Deployment

These prompts are scoped to the **four views** available when only the AMO base
tables are loaded (see `SQL/vw_SafetyIntel_Views_AMO_Subset.sql`):

| View | Covers |
|---|---|
| `vw_SafetyIntel_AMO` | AMO registry, country/city, ratings, approval validity, current tier, assigned PMI |
| `vw_SafetyIntel_Audits` | Planned/completed audits, PMI, approval expiry |
| `vw_SafetyIntel_TierTrend` | Tier history by AWI × year |
| `vw_SafetyIntel_TAM` | Bilateral (TAM) arrangements |

> ⚠️ The original demo phrases **"Show me the runway incursion dashboard"**,
> **"Analyze recent bird strike"**, and **"Build me a 2024 safety intelligence
> dashboard"** will **not** work here — they depend on the occurrence, findings,
> and surveillance views whose base tables are not loaded.

Each prompt below is worded so the bot calls `nl2sql` and then `chart_spec`,
rendering a chart on the canvas. The expected chart type is noted for reference.

---

## 1. AMO registry & tiers

**Tier distribution (pie / bar)**
> Show me the distribution of AMOs by current tier as a pie chart.

**AMOs by country (bar)**
> Give me a bar chart of how many AMOs we have in each country.

**Highest rating breakdown (bar)**
> Break down the number of AMOs by highest rating and show it as a chart.

**Active vs other status (pie)**
> What is the share of AMOs by status? Show it as a pie chart.

**Top inspectors by workload (bar)**
> Plot the top 10 PMIs by how many AMOs they are assigned, as a bar chart.

---

## 2. Tier trends over time

**Tier movement year over year (line)**
> Show a line chart of how many AMOs are in each tier per year.

**Downgrades 2023 → 2024 (bar / table)**
> Which AMOs moved to a worse tier between 2023 and 2024? Show a chart.

**Tier 1 trend (line)**
> Plot the number of Tier 1 AMOs by year as a line chart.

---

## 3. Audits

**Planned vs completed audits by year (bar)**
> Compare planned versus completed audits per year as a grouped bar chart.

**Audits by type (bar)**
> Show a bar chart of audit counts by audit type.

**Approvals expiring soon (bar / table)**
> Which AMO approvals expire in the next 6 months? Show them on a chart by month.

**Audit category (CAT) split (pie)**
> Give me a pie chart of audits by CAT category.

---

## 4. TAM bilateral arrangements

**TAM by country (bar)**
> Show a bar chart of TAM bilateral arrangements grouped by country.

**TAM by agreement type (pie)**
> What is the breakdown of TAM arrangements by type of agreement? Pie chart please.

---

## 5. Combined / "mini dashboard" prompts

The bot will emit several `nl2sql` + `chart_spec` pairs for these:

**AMO oversight overview**
> Build me an AMO oversight overview: tier distribution, AMOs by country, and
> audits by type — each as a chart.

**Audit planning snapshot**
> Give me an audit planning snapshot for this year: planned vs completed audits,
> audit types, and approvals expiring in the next 6 months, with charts.

---

## Tips
- Use words like *chart*, *bar*, *pie*, *line*, *trend*, *distribution*,
  *breakdown*, or *top N* to force a chart.
- If you ask for data the deployment doesn't have (findings, bird strikes,
  runway incursions, surveillance, AOC, change management), the bot will reply
  that only AMO registry, audits, tier history, and TAM data are available.
