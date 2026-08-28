with source as (

    select * from {{ source('pipedrive', 'users') }}

),

renamed as (

    select
        id::integer                 as user_id,
        nullif(trim(name), '')      as user_name,
        lower(nullif(trim(email), '')) as email,
        modified::timestamp         as modified_at
    from source

)

select * from renamed
