# Modeling decisions

Rationale for the non-obvious model-design choices. Data-level findings that
drive them are in [`initial_exploratory_analysis.md`](initial_exploratory_analysis.md).

## Layer map

| Layer | Role | Materialisation |
|---|---|---|
| `staging/` | 1:1 with source: rename + cast, no logic | view |
| `intermediate/` | reshape / pivot / cross-model building blocks | view |
| `marts/` | conformed facts + dimensions (`fct_*`, `dim_*`) | table |
| `presentation/` | wide `rep_*` tables shaped for one output | table |

Each folder has its own `README.md` with naming rules and how tests are split.
Test split overall: **`sources.yml`** carries freshness + primary-key tests only
(plus one raw-enum check); everything else lives on the model where the
transformation happens.

## Two shapes of the deal change log

`stg_pipedrive__deal_changes` is a long polymorphic event log. Two models read
it into different shapes; neither depends on the other.

| | `int_pipedrive__deals` | `fct_deal_stage_progression` |
|---|---|---|
| layer | intermediate (view) | marts (table) |
| grain | one row per deal | one row per (deal, funnel step reached) |
| shape | wide — the log pivoted | long — one row per step the deal reached |
| purpose | current deal state → `fct_deals` | base fact for funnel / velocity / cohort analysis → `rep_sales_funnel_monthly` |
| adds | `created_at`, current + max stage, current owner, change counts, `lost_reason_id` | `reached_at` / `reached_month` per step (including skipped-into steps) |

**Why one is intermediate and the other is a fact:** `int_pipedrive__deals` is a
purpose-built rollup consumed only by `fct_deals` — a stepping stone.
`fct_deal_stage_progression` is a first-class analytical grain (a deal reaching a
funnel milestone is a business event) that any funnel/velocity/cohort question
would query directly, so it belongs in `marts/`.

**`fct_deal_stage_progression` reads staging, not `int_pipedrive__deals`:** the
`deals` pivot already collapsed the per-stage timestamps into
`first_/last_stage_changed_at` + `max_stage_id`, but this model needs the full
ordered sequence of stage changes (`lag()` over every row) to know *when* each
step was crossed. That sequence only exists in staging.

_(Earlier iterations, removed once nothing consumed them:
`int_pipedrive__deal_change_history` — a human-readable labelled change log (the
label-resolution pattern lives on in `fct_deals.lost_reason_label`) — and
`int_pipedrive__deal_funnel_events`, which emitted `landed` / `skipped` /
`progressed` / `regressed` / `lost` events; the deliverable only needs "reached".)_

## `dim_users` — SCD1, and why it exists at all

### Why not SCD2

SCD2 is neither possible nor warranted here:

- **No history to model.** `public.users` is a current-state snapshot — exactly
  one row per `id`, and the only change signal is a single `modified` timestamp
  (no prior values, no versions). History cannot be reconstructed from that; the
  earliest you could start is a forward-only dbt snapshot.
- **No slowly-changing analytical attributes.** The table has only `name` and
  `email` — no team, role, region, segment or quota, nothing whose history
  drives analysis.
- **Nothing slices by user.** `rep_sales_funnel_monthly` is month × KPI × step;
  there is no user dimension in the deliverable. Facts join `dim_users` only to
  surface a current name.
- SCD2 would add surrogate keys, `valid_from` / `valid_to` / `is_current`, and
  date-range join complexity — cost with no payoff.

### Why keep `dim_users` anyway

Kept deliberately as a **stable seam**, not because SCD1 adds columns over
`stg_pipedrive__users` today:

- Downstream facts (`fct_deals`, `fct_activities`) join a **dimension**, not a
  staging model. If user modeling ever changes — a real HR / role feed, a
  snapshot-backed SCD2, extra attributes — only `dim_users` changes; every
  consumer's `ref('dim_users')` and join key stay put.
- It is the one place for user-level derivations (`email_domain`,
  `is_email_shared` today) so facts don't each re-derive them.
- The SCD2 upgrade path is pre-planned: add `snapshots/pipedrive_users_snapshot.sql`
  (`check` strategy on `name` / `email`), let it accrue, then rebuild
  `dim_users` from the snapshot with SCD2 columns — no consumer changes.

## The funnel report — `rep_sales_funnel_monthly`

Built to the brief: columns `month`, `kpi_name`, `funnel_step`, `deals_count`;
one row per `(month, funnel_step)`. `kpi_name` is the step name with its kind
appended — `"Qualified Lead (stage)"`, `"Sales Call 1 (activity)"` — so no row
can be misread as a funnel sub-count when it isn't one. `funnel_step` is the
number ("1".."9", "2.1", "3.1"); `deals_count` = distinct deals that **reached**
that step in the month, or, for the sub-steps, that had a Sales Call due that
month. Full column reference: [`models/presentation/README.md`](../models/presentation/README.md).

Structural points:

- **The 11 step names come from a seed** (`seeds/funnel_steps.csv`, read via
  `stg_seed__funnel_steps`), not a hardcoded `values (...)` list in the model. The seed
  also holds each step's `step_kind` (`stage` / `activity`) and `join_key`, so
  the model joins to it rather than `CASE`-ing on stage ids / activity type keys.
- **Steps 1-9 are built on `fct_deal_stage_progression`** — the fact that carries
  the month each deal reached each step (see "Two shapes of the deal change log"
  above).
- **"Reached step N" includes deals that skipped it** — stages are skippable but
  monotonic, so reaching N means the deal passed every step below N. Counting
  only literal `stage_id = N` rows would break monotonicity (the exploratory analysis found most deals skip a
  stage — see `initial_exploratory_analysis.md` §5.3).
- **Sub-steps 2.1 / 3.1 come from `fct_activities`** on a near-disjoint deal
  population (§5.2) — a parallel read, not sub-counts of steps 2 / 3.
- The report is **sparse** (zero-count `(month, step)` rows omitted). A dense
  grid would be a months × steps cross join in the report.
- `deals_count` is a **monthly flow, not a cumulative funnel** — down a single
  month it doesn't shrink step-by-step. Proven in
  [`post_integration_validation.md`](post_integration_validation.md).
