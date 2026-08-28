-- Every (funnel_step, kpi_name) pair in the report must be a real pair from the
-- funnel_steps seed. Guards against a label/number mismatch slipping through
-- the join (e.g. a duplicated or edited seed row).

select
    r.funnel_step,
    r.kpi_name
from {{ ref('rep_sales_funnel_monthly') }} r
left join {{ ref('stg_seed__funnel_steps') }} s
    on  s.funnel_step = r.funnel_step
    and r.kpi_name    = s.kpi_name || ' (' || s.step_kind || ')'
where s.funnel_step is null
group by 1, 2
