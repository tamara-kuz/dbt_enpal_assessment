-- Fact table: one row per deal, from int_pipedrive__deals, enriched with stage
-- names, the current owner's name, and the lost-reason label.
--
-- `lost_reason_label` is carried for readability but is noise (every deal has
-- one, uniform across outcomes - not a won/lost signal). Use `max_stage_id` for
-- "how far the deal got", not `current_stage_id`.

with deals as (

    select * from {{ ref('int_pipedrive__deals') }}

),

stages as (

    select stage_id, stage_name from {{ ref('stg_pipedrive__stages') }}

),

users as (

    select user_id, user_name from {{ ref('dim_users') }}

),

lost_reasons as (

    -- id -> label from the lost_reason option set (consistent casing source).
    --
    -- field_value_options is jsonb: [{"id":"1","label":"..."}, ...].
    -- jsonb_array_elements() expands the array to one row per element; each
    -- `opt` is a jsonb object like {"id":"1","label":"..."}.
    --   opt -> 'id'   returns the value as jsonb  (would be "1" with quotes)
    --   opt ->> 'id'  returns the value as TEXT   ('1')  <- the ->> operator
    -- so `(opt ->> 'id')::integer` = extract "id" as text, then cast to int.
    select
        (opt ->> 'id')::integer as lost_reason_id,
        opt ->> 'label'         as lost_reason_label
    from {{ ref('stg_pipedrive__fields') }} f
    cross join lateral jsonb_array_elements(f.field_value_options) as opt
    where f.field_key = 'lost_reason'

),

final as (

    select
        d.deal_id,

        d.created_at,
        d.created_month,
        (d.last_stage_changed_at::date - d.created_at::date) as pipeline_duration_days,

        d.current_owner_user_id,
        u.user_name                     as current_owner_name,
        d.owner_change_count,

        d.current_stage_id,
        cs.stage_name                   as current_stage_name,
        d.max_stage_id,
        ms.stage_name                   as max_stage_name,
        d.first_stage_changed_at,
        d.last_stage_changed_at,
        d.stage_change_count,

        d.lost_reason_id,
        lr.lost_reason_label,
        d.lost_reason_at
    from deals d
    left join stages cs        on cs.stage_id       = d.current_stage_id
    left join stages ms        on ms.stage_id       = d.max_stage_id
    left join users u          on u.user_id         = d.current_owner_user_id
    left join lost_reasons lr  on lr.lost_reason_id = d.lost_reason_id

)

select * from final
