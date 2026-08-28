-- All-time (deals_count summed over months), the stage funnel steps 1-9 must be
-- non-increasing: reaching step N implies reaching every step below it, so the
-- deal set at N is a subset of the set at N-1. Fails if any step's total
-- exceeds the previous step's - which would mean the "reached >= N" logic in
-- fct_deal_stage_progression is not emitting a row for every gate crossed.
--
-- (Only checks steps 1-9. The monthly column is a flow and is NOT expected to
--  be monotonic - see docs/post_integration_validation.md.)

with totals as (

    select cast(funnel_step as int) as step, sum(deals_count) as total
    from {{ ref('rep_sales_funnel_monthly') }}
    where funnel_step in ('1', '2', '3', '4', '5', '6', '7', '8', '9')
    group by 1

)

select
    t.step,
    t.total,
    prev.total as prev_step_total
from totals t
join totals prev on prev.step = t.step - 1
where t.total > prev.total
