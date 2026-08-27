with source as (

    select * from {{ source('pipedrive', 'fields') }}

),

renamed as (

    select
        id::integer             as field_id,
        field_key               as field_key,
        name                    as field_name,
        field_value_options     as field_value_options,   -- jsonb: [{id,label}] for enum fields, else null
        (field_value_options is not null) as is_enum_field
    from source

)

select * from renamed
