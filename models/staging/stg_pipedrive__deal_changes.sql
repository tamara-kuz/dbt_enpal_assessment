with source as (

    select * from {{ source('pipedrive', 'deal_changes') }}

),

renamed as (

    select
        deal_id::integer            as deal_id,
        change_time::timestamp      as changed_at,
        changed_field_key           as changed_field_key,
        new_value                   as new_value,

        -- new_value is polymorphic text; expose a typed column per field kind
        case when changed_field_key = 'stage_id'    then new_value::integer   end as new_stage_id,
        case when changed_field_key = 'user_id'     then new_value::integer   end as new_owner_user_id,
        case when changed_field_key = 'add_time'    then new_value::timestamp end as deal_created_at,
        case when changed_field_key = 'lost_reason' then new_value::integer   end as new_lost_reason_id
    from source

)

select * from renamed
