-- User dimension. SCD1 (current state, one row per user).
--
-- SCD2 is not modelled: the source is a current-state snapshot with one row per
-- user and only a `modified` "last touched" timestamp -- no prior values, no
-- versions, nothing to reconstruct history from. It also carries no
-- slowly-changing analytical attributes (just name + email). If history is ever
-- needed, add a dbt snapshot on source('pipedrive','users') (check strategy on
-- name/email) and rebuild this from the snapshot. See
-- docs/initial_exploratory_analysis.md.

with users as (

    select * from {{ ref('stg_pipedrive__users') }}

),

final as (

    select
        user_id,
        user_name,
        email,
        split_part(email, '@', 2)                          as email_domain,
        count(*) over (partition by email) > 1             as is_email_shared,
        modified_at
    from users

)

select * from final
