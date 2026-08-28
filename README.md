## Documentation

All work on this assessment is written up in the [`docs/`](docs/) folder.

- **[`docs/initial_exploratory_analysis.md`](docs/initial_exploratory_analysis.md)** — the deep dive into the
  Pipedrive source data: CRM glossary, the deal lifecycle (stages, activities,
  status) with diagrams, a full CSV ↔ Postgres comparison, a column-by-column
  data dictionary with accepted values, source-freshness threshold analysis, and
  the data-quality findings that shaped the model design.
- **[`docs/modeling_decisions.md`](docs/modeling_decisions.md)** — rationale for the
  non-obvious design choices: the layer map, the two shapes of the deal change
  log (`int_pipedrive__deals` vs `fct_deal_stage_progression`), why `dim_users`
  is SCD1 but kept anyway, and how the funnel report is built.
- **[`docs/post_integration_validation.md`](docs/post_integration_validation.md)** —
  reproducible checks on the built models: (1) why the monthly funnel is a flow,
  not a cumulative shape, and how it reconciles; (2) why the `2.1` / `3.1` Sales
  Call rows sit outside the funnel and can't be linked to it.

**The deliverable** is [`models/presentation/rep_sales_funnel_monthly.sql`](models/presentation/rep_sales_funnel_monthly.sql)
— columns `month`, `kpi_name`, `funnel_step`, `deals_count` exactly as briefed.
`kpi_name` carries the step name and its kind (`… (stage)` / `… (activity)`);
`deals_count` counts the deals that reached that step in the month. The 11 step
names come from the [`funnel_steps`](seeds/funnel_steps.csv) seed. See
[`models/presentation/README.md`](models/presentation/README.md).

Model-level documentation lives next to the code: source and freshness/PK tests
in [`models/sources.yml`](models/sources.yml), and per-model column descriptions
and tests in the layer folders under [`models/`](models/).

**Each `models/` subfolder has its own `README.md`** with that layer's general
rules — naming conventions, column-naming standards, and how tests are split
between layers:
[`staging/`](models/staging/README.md) →
[`intermediate/`](models/intermediate/README.md) →
[`marts/`](models/marts/README.md) →
[`presentation/`](models/presentation/README.md).

### Conventions shared by every model

- **`.sql` file shape:** import CTEs first — one
  `with <name> as (select * from {{ ref(...) }} / {{ source(...) }})` per
  upstream, no logic; then transformation CTEs, each with a one-line comment;
  then a `final` CTE that assembles the output, and `select * from final` as the
  last line so the returned columns are always in one obvious place.
- **`.yml` file:** every model and every column carries a `description`, plus
  `meta` (layer, grain, …) — these feed the data catalogue / `dbt docs`. Grain
  and any non-obvious behaviour are called out in the model description.

## Setup

1. Download Docker Desktop (if you don’t have installed) using the official website, install and launch.
2. Fork this Github project to you Github account. Clone the forked repo to your device.
3. Open your Command Prompt or Terminal, navigate to that folder, and run the command `docker compose up`.
4. Now you have launched a local Postgres database with the following credentials:
 ```
    Host: localhost
    User: admin
    Password: admin
    Port: 5432 
```
5. Connect to the db via a preferred tool (e.g. DataGrip, Dbeaver etc)
6. Install dbt-core and dbt-postgres using pip (if you don’t have) on your preferred environment.
7. Run `dbt deps` to install packages (`dbt_utils`), then `dbt build` to run
   every model and test. Results land in the `public_pipedrive_analytics` schema;
   `rep_sales_funnel_monthly` is the deliverable.

> `dbt source freshness` reports STALE by design — the CSV load is a static 2024
> snapshot; see `docs/initial_exploratory_analysis.md` §3.1.

## Project
1. Remove the test model once you make sure it works
2. Dive deep into the Pipedrive CRM source data to gain a thorough understanding of all its details. (You may also research the Pipedrive CRM tool terms).
3. Define DBT sources and build the necessary layers organizing the data flow for optimal relevance and maintainability.
4. Build a reporting model (rep_sales_funnel_monthly) with monthly intervals, incorporating the following funnel steps (KPIs):  
  &nbsp;&nbsp;&nbsp;Step 1: Lead Generation  
  &nbsp;&nbsp;&nbsp;Step 2: Qualified Lead  
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Step 2.1: Sales Call 1  
  &nbsp;&nbsp;&nbsp;Step 3: Needs Assessment  
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Step 3.1: Sales Call 2  
  &nbsp;&nbsp;&nbsp;Step 4: Proposal/Quote Preparation  
  &nbsp;&nbsp;&nbsp;Step 5: Negotiation  
  &nbsp;&nbsp;&nbsp;Step 6: Closing  
  &nbsp;&nbsp;&nbsp;Step 7: Implementation/Onboarding  
  &nbsp;&nbsp;&nbsp;Step 8: Follow-up/Customer Success  
  &nbsp;&nbsp;&nbsp;Step 9: Renewal/Expansion
5. Column names of the reporting model: `month`, `kpi_name`, `funnel_step`, `deals_count`
6. “Git commit” all the changes and create a PR to your forked repo (not the original one). Send your repo link to us.
