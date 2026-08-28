-- rep_sales_funnel_monthly.deals_count, summed over every month for a given
-- funnel_step, must equal the distinct-deal count in the model it is built
-- from. This is the core calculation check - a mismatch means double-counting,
-- dropped rows, or a month-bucketing bug in the aggregation.
--
--   steps 1-9  -> distinct deals in fct_deal_stage_progression (each deal
--                 reaches a step in exactly one month, so sum == distinct)
--   2.1 / 3.1  -> distinct (deal, month) pairs in fct_activities for the
--                 meeting / sc_2 activity types (a deal can have a call in
--                 more than one month, so the grain must match the report)

with rep_totals as (

    select funnel_step, sum(deals_count) as rep_total
    from {{ ref('rep_sales_funnel_monthly') }}
    group by 1

),

expected as (

    select cast(funnel_step as varchar) as funnel_step,
           count(distinct deal_id)      as expected_total
    from {{ ref('fct_deal_stage_progression') }}
    group by 1

    union all

    select '2.1', count(*)
    from (
        select 1
        from {{ ref('fct_activities') }}
        where activity_type_key = 'meeting'
        group by deal_id, date_trunc('month', due_at)
    ) m

    union all

    select '3.1', count(*)
    from (
        select 1
        from {{ ref('fct_activities') }}
        where activity_type_key = 'sc_2'
        group by deal_id, date_trunc('month', due_at)
    ) s

)

select
    e.funnel_step,
    e.expected_total,
    r.rep_total
from expected e
join rep_totals r using (funnel_step)
where e.expected_total is distinct from r.rep_total
