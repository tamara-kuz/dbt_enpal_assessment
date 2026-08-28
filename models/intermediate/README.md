# Intermediate layer

Sits between staging and marts. Purpose-built building blocks — reshaping,
pivoting, cross-model joins — that more than one downstream model (or one
complex mart) will need. Not a place for final business metrics; that's the
marts / reporting layer.

## Model naming — `int_pipedrive__<verb_or_entity>`

- Same `<source>__<object>` convention as staging, `int_` prefix for the layer.
- `<object>` names the thing produced (`deals`, `activities`), not the source
  table it came from.
- File name = model name; one `.yml` per model.

## Column naming

- Same standards as staging: `*_id`, `*_at`, `is_*`, `*_key`, snake_case.
- Aggregated/derived columns say what they are: `*_count`, `first_*_at`,
  `last_*_at`, `current_*`, `max_*`.

## What's here

- **`int_pipedrive__deals`** — the `deal_changes` event log pivoted to one row
  per deal (creation, current + furthest stage, current owner, lost_reason).
  Feeds `marts/fct_deals`.

The other per-deal shape of the change log — one row per funnel step reached —
is a standalone analytical fact, so it lives in `marts/fct_deal_stage_progression`
rather than here. Activities need no intermediate step (nothing to deduplicate),
so they go straight to `marts/fct_activities`.

## Tests

- Tests live where the transformation happens: this layer tests the **new**
  guarantees — grain uniqueness (`dbt_utils.unique_combination_of_columns` /
  `unique`), derived-column `not_null` / `accepted_values`, and FK
  `relationships` back to staging.

## Materialisation — views

Set in `dbt_project.yml` (`intermediate: +materialized: view`).

- **Nobody queries an intermediate model directly** — its only consumer is a
  downstream model, at build time. A view is just a stored `SELECT`; when the
  consumer builds, Postgres inlines the view's SQL into one combined query. No
  separate build step, no stored copy.
- **A table would cost more for no gain** — full compute + storage on every
  `dbt build`, and stale between runs. A view costs ~nothing to build and is
  always live against its inputs; the usual downside (recomputed on every read)
  doesn't bite because there are no ad-hoc reads.
- **Nested views collapse**: `fct_deals` (table) ← `int_pipedrive__deals` (view)
  ← `stg_*` (view) ← source flattens into a single query plan when `fct_deals`
  materialises. The expensive work is persisted once, in the mart table.
- **`view` over `ephemeral`** (the other common choice): a view is a real object
  you can `select * from` to debug and run tests against.
- **When to switch to `table`:** the model is expensive *and* fanned out to
  several downstream models (compute once vs N times), or the nested-view SQL
  gets too deep for the planner. Neither applies here.
