# Marts layer

The dimensional core: conformed facts and dimensions that analysts, BI, and the
`presentation/` report models all build on. Joins and enrichment happen here;
each model has a clearly stated grain. Output-specific shaping does **not** —
that lives in `models/presentation/`.

## Model naming

- `fct_<entity>` — event / transaction facts, one row per business event
  (`fct_activities`, `fct_deals`).
- `dim_<entity>` — descriptive dimensions (`dim_users`).
- No `pipedrive__` source prefix here — marts are source-agnostic by intent.
- Wide, single-purpose report tables (`rep_*`) are **not** here — see
  `models/presentation/`.

## Column naming

- Same standards as the lower layers: `*_id`, `*_at`, `is_*`, `*_key`,
  snake_case.
- Columns pulled from a joined entity are prefixed with that entity:
  `assigned_user_name`, `deal_current_stage_id`.

## What's here

- **`dim_users`** — user dimension, SCD1 (current state, one row per user).
  SCD2 was investigated and rejected (no source history, no slowly-changing
  analytical attributes); the dim is still kept as a stable seam for future
  user modeling. Full rationale + SCD2 upgrade path in
  [`docs/modeling_decisions.md`](../../docs/modeling_decisions.md).
- **`fct_deals`** — one row per deal, from `int_pipedrive__deals`, with stage
  names, current owner name and lost-reason label resolved.
- **`fct_deal_stage_progression`** — one row per (deal, funnel step reached),
  with `reached_at` / `reached_month`. The base fact for funnel / velocity /
  cohort analysis; built straight from `stg_pipedrive__deal_changes` (it needs
  the full ordered stage sequence, which `int_pipedrive__deals` collapsed).
- **`fct_activities`** — one row per activity event, grain `(activity_id,
  deal_id)`, enriched with activity type + assigned user (`dim_users`). `deal_id`
  is carried but deliberately **not** joined to `fct_deals` here — the activity
  and deal_changes deal populations are near-disjoint (they barely overlap), so deal
  context is an opt-in join for the presentation layer, not a fact column.

Fact-to-dimension joins within the layer are fine (facts read `dim_users`).

## Tests

- Grain is enforced: `unique` + `not_null` on the surrogate key.
- `not_null` on every non-nullable enriched column, `relationships` back to the
  staging FKs, `accepted_values` on enums.
- Deliberately nullable columns (the deal_* enrichment) carry no `not_null`.
- Materialised as tables (see `dbt_project.yml`).
