with source as (

    select * from {{ source('pipedrive', 'activity') }}

),

renamed as (

    select
        activity_id::integer        as activity_id,
        trim(type)                  as activity_type_key,
        assigned_to_user::integer   as assigned_user_id,
        deal_id::integer            as deal_id,
        done::boolean               as is_done,
        due_to::timestamp           as due_at
    from source

)

select * from renamed
