with source as (

    select * from {{ source('pipedrive', 'activity_types') }}

),

renamed as (

    select
        id::integer                     as activity_type_id,
        trim(name)                      as activity_type_name,
        trim(type)                      as activity_type_key,
        (lower(trim(active)) = 'yes')   as is_active
    from source

)

select * from renamed
