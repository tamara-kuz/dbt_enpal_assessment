-- Monthly sales funnel, per the brief: one KPI per funnel step, counting the
-- deals that reached that step in each month.
--
--   month       - first-of-month date
--   kpi_name    - step name + kind: "Qualified Lead (stage)", "Sales Call 1 (activity)"
--   funnel_step - step number as text ("1" .. "9", plus "2.1" / "3.1")
--   deals_count - distinct deals
--
-- The 11 steps and their names come from the `stg_seed__funnel_steps` seed model.
--
-- Steps 1-9: a deal counts in the month it first reached that step
-- (fct_deal_stage_progression; includes deals that skipped into it).
-- Sub-steps 2.1 / 3.1: deals with a Sales Call 1 / 2 activity due that month
-- (from fct_activities; a near-disjoint deal population, so these are a parallel
-- read, not sub-counts of steps 2 / 3 - see docs/initial_exploratory_analysis.md 5.2).

with stage_progression as (

    select * from {{ ref('fct_deal_stage_progression') }}

),

activities as (

    select * from {{ ref('fct_activities') }}

),

funnel_steps as (

    select * from {{ ref('stg_seed__funnel_steps') }}

),

-- kpi_name carries step_kind so a reader always sees whether a row is a funnel
-- stage or a parallel activity metric: "Qualified Lead (stage)",
-- "Sales Call 1 (activity)". The activity sub-steps are NOT sub-counts of the
-- surrounding stages (near-disjoint deal population - docs 5.2).
-- deals that first reached each pipeline stage in the month
stage_kpis as (

    select
        sp.reached_month                                as month,
        fs.kpi_name || ' (' || fs.step_kind || ')'      as kpi_name,
        fs.funnel_step,
        count(distinct sp.deal_id)                      as deals_count
    from stage_progression sp
    join funnel_steps fs
        on fs.step_kind = 'stage'
       and fs.join_key  = sp.funnel_step::text
    group by 1, 2, 3

),

-- sub-steps 2.1 / 3.1: deals with a Sales Call due that month
substep_kpis as (

    select
        cast(date_trunc('month', a.due_at) as date)    as month,
        fs.kpi_name || ' (' || fs.step_kind || ')'      as kpi_name,
        fs.funnel_step,
        count(distinct a.deal_id)                       as deals_count
    from activities a
    join funnel_steps fs
        on fs.step_kind = 'activity'
       and fs.join_key  = a.activity_type_key
    group by 1, 2, 3

),

final as (

    select month, kpi_name, funnel_step, deals_count from stage_kpis
    union all
    select month, kpi_name, funnel_step, deals_count from substep_kpis

)

select * from final
