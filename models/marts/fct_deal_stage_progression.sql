-- Fact: one row per (deal, funnel step) the deal reached, with the first time
-- its stage became >= that step.
--
-- Stages are skippable but monotonic, so "reached step S" = the deal's stage
-- first became >= S: a deal recorded at 1 -> 3 has rows for steps 2 and 3.
-- Built from the stage_id change log (the per-stage timestamps that
-- int_pipedrive__deals / fct_deals aggregate away).
--
-- The base fact for any funnel / velocity / cohort analysis; feeds
-- rep_sales_funnel_monthly.
--
-- Grain: (deal_id, funnel_step).

with deal_changes as (

    select * from {{ ref('stg_pipedrive__deal_changes') }}

),

-- every stage_id change with the deal's previous stage value (0 = before the
-- first change). staging routes changed_field_key -> new_stage_id, so filter
-- on that rather than the raw key string.
stage_changes as (

    select
        deal_id,
        changed_at,
        new_stage_id,
        coalesce(
            lag(new_stage_id) over (partition by deal_id order by changed_at, new_stage_id),
            0
        ) as prev_stage_id
    from deal_changes
    where new_stage_id is not null

),

-- one row per gate crossed on a forward move (prev, new] - every step the deal
-- reached, skipped-over ones included; keep the first time it happened.
--
-- `cross join lateral`: a plain CROSS JOIN pairs each left row with a FIXED
-- right table and the right side can't see left columns. LATERAL removes that
-- restriction - the right expression is evaluated once PER left row and CAN
-- reference its columns (like a correlated subquery that returns a set).
-- Here `generate_series(prev_stage_id + 1, new_stage_id)` uses this row's
-- prev/new to emit the integers between them, one output row each:
-- a 1 -> 3 change fans out to funnel_step 2 and 3, both carrying that change's
-- deal_id / changed_at. Rows with an empty series (no forward move) drop out,
-- so it behaves like an inner join - the WHERE below makes that explicit.
-- Portability: Snowflake `LATERAL FLATTEN`, BigQuery `CROSS JOIN UNNEST`,
-- Redshift has no LATERAL (use a numbers table).
final as (

    select
        sc.deal_id,
        gs.s                                              as funnel_step,
        min(sc.changed_at)                                as reached_at,
        cast(date_trunc('month', min(sc.changed_at)) as date) as reached_month
    from stage_changes sc
    cross join lateral generate_series(sc.prev_stage_id + 1, sc.new_stage_id) as gs(s)
    where sc.new_stage_id > sc.prev_stage_id
    group by 1, 2

)

select * from final
