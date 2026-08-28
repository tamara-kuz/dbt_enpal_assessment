with source as (

    select * from {{ source('pipedrive', 'stages') }}

),

renamed as (

    select
        stage_id::integer   as stage_id,
        trim(stage_name)    as stage_name,
        stage_id::integer   as pipeline_step   -- stages are ordered 1..9 == funnel step
    from source

)

select * from renamed
