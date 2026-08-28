-- Staging for the funnel_steps seed. Pass-through (the seed is authored in its
-- final shape) - present only so nothing downstream refs the raw seed directly.

with source as (

    select * from {{ ref('funnel_steps') }}

),

renamed as (

    select
        funnel_step,
        kpi_name,
        step_kind,
        join_key
    from source

)

select * from renamed
