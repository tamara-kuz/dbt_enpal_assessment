## Documentation

All work on this assessment is written up in the [`docs/`](docs/) folder.

- **[`docs/initial_exploratory_analysis.md`](docs/initial_exploratory_analysis.md)** — the deep dive into the
  Pipedrive source data: CRM glossary, the deal lifecycle (stages, activities,
  status) with diagrams, a full CSV ↔ Postgres comparison, a column-by-column
  data dictionary with accepted values, source-freshness threshold analysis, and
  the data-quality findings that shaped the model design.

Model-level documentation lives next to the code: source and freshness/PK tests
in [`models/sources.yml`](models/sources.yml), and per-model column descriptions
and tests in the layer folders under [`models/`](models/).

**Each `models/` subfolder has its own `README.md`** with that layer's general
rules — naming conventions, column-naming standards, and how tests are split
between layers. See [`models/staging/README.md`](models/staging/README.md) for
the staging layer; later layers (intermediate, reporting) follow the same
pattern.

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
7. Now you can run `dbt run` with the test model and check public_pipedrive_analytics schema to see the dbt result (with one test model)

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
