# Presentation layer

Wide, denormalised tables shaped for **one specific output** — a dashboard tile,
a report, an export. Each is a final projection of the marts, not a reusable
building block. If two consumers would need it, it belongs in `marts/` instead.

## Model naming — `rep_<subject>_<grain>`

- `rep_` prefix marks the layer.
- `<subject>` = what the report is about (`sales_funnel`).
- `<grain>` = the row grain / period (`monthly`).
- e.g. `rep_sales_funnel_monthly`.

## Rules

- Reads from `marts/` (and `intermediate/` only if unavoidable) — never from
  `staging/` or `source()`.
- Column names and shape match what the consumer expects, even when that means
  breaking the lower-layer naming conventions (e.g. a literal `month` column, a
  `kpi_name` label column).
- No further business logic that other models might want — pull that back into
  `marts/` or `intermediate/`.
- Materialised as tables.

## What's here

### `rep_sales_funnel_monthly` — the deliverable

One row per `(month, funnel_step)`. Columns exactly as the brief specifies:
`month`, `kpi_name`, `funnel_step`, `deals_count`.

- `kpi_name` — step name **plus its kind**: `Qualified Lead (stage)` …
  `Renewal/Expansion (stage)`, and `Sales Call 1 (activity)` /
  `Sales Call 2 (activity)`. The `(activity)` rows are a parallel
  activity-volume metric on a near-disjoint deal population — **not** sub-counts
  of the surrounding stages. `step_kind` comes from the `funnel_steps` seed and
  is concatenated onto the name in the model.
- `funnel_step` — step number as text: `"1"`..`"9"`, plus `"2.1"` / `"3.1"`.
- `deals_count`:
  - **Steps 1-9** — distinct deals that first **reached** that step in the month
    (stage became ≥ that step; from `fct_deal_stage_progression`). A deal that
    skipped a stage still counts for it — stages are skippable but monotonic, so
    "reached step N" ⇒ passed every step below N.
  - **Sub-steps 2.1 / 3.1** — distinct deals with a Sales Call 1 / 2 activity
    **due** that month (`fct_activities`). These sit on a deal population
    near-disjoint from the funnel deals (§5.2), so they are a
    parallel read, **not** sub-counts of steps 2 / 3.
- The 11 step names and their join keys come from the **`funnel_steps` seed**.
- Sparse: `(month, step)` rows with zero deals are omitted.

> **`deals_count` is a monthly flow, not a cumulative funnel.** Down a single
> month it does not shrink step-by-step, because each step's count is a
> different deal set (deals *entering* that step that month, from any cohort).
> The funnel is monotonic all-time and per cohort; the monthly counts sum back
> to the all-time totals. Proof: `docs/post_integration_validation.md`.

## Tests

**Schema** — `not_null` + `accepted_values` on every output column;
`deals_count` also `dbt_utils.accepted_range` (>= 1, the sparse-table
invariant); grain via `dbt_utils.unique_combination_of_columns`
(`month + funnel_step`), no surrogate-key column so the model keeps the 4 spec
columns.

**Calculation** — singular tests in `tests/`:

| test | asserts |
|---|---|
| `assert_rep_sales_funnel_monthly_reconciles` | per step, `sum(deals_count)` over all months equals the distinct-deal count in the model it's built from (`fct_deal_stage_progression` for 1–9, `fct_activities` for 2.1 / 3.1) — catches double-counting / dropped rows / month-bucketing bugs |
| `assert_rep_sales_funnel_monthly_monotonic` | all-time (summed over months), steps 1–9 are non-increasing |
| `assert_rep_sales_funnel_monthly_step_pairs` | every `(funnel_step, kpi_name)` pair exists in the `funnel_steps` seed |

These codify the checks in
[`docs/post_integration_validation.md`](../../docs/post_integration_validation.md).
