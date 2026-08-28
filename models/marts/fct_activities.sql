-- Fact table: one row per activity event, enriched with its type and assigned
-- user.
--
-- Grain / key: (activity_id, deal_id) - one row per activity/deal association.
-- (activity_id, deal_id) is unique across every row, so no deduplication is
-- done; activity_key hashes that pair.
--
-- activity_id alone is NOT unique - the exploratory analysis found some ids on
-- more than one row (different deal, user, type and due date; no exact- or
-- near-duplicate rows). Two candidate business meanings, TO BE CONFIRMED with
-- the CRM owner:
--   (a) An activity is genuinely linked to several deals - one call/meeting that
--       advances more than one open deal for the same customer. Pipedrive and
--       most CRMs support many-to-many activity<->deal links; the export would
--       then be one row per link and activity_id is meant to repeat.
--   (b) Id reuse / export artifact - two unrelated activities that happen to
--       share an id.
-- The paired rows share almost no attributes, which leans towards (b), but this
-- assumption should be verified before activity_id is ever treated as a key or
-- used to dedupe. Either way, grain (activity_id, deal_id) is safe and loses
-- nothing.
--
-- `deal_id` is carried but NOT joined to the deal models here: the activity and
-- deal_changes deal populations are near-disjoint (they barely overlap), so deal
-- enrichment belongs in the presentation layer where a report can opt into it.

with activities as (

    select
        *,
        count(*) over (partition by activity_id) > 1 as is_activity_id_shared
    from {{ ref('stg_pipedrive__activities') }}

),

activity_types as (

    select * from {{ ref('stg_pipedrive__activity_types') }}

),

users as (

    select * from {{ ref('dim_users') }}

),

final as (

    select
        {{ dbt_utils.generate_surrogate_key(['a.activity_id', 'a.deal_id']) }} as activity_key,

        a.activity_id,
        a.is_activity_id_shared,
        a.deal_id,

        -- activity attributes
        a.activity_type_key,
        at.activity_type_name,
        at.is_active                                 as activity_type_is_active,
        a.is_done,
        a.due_at,

        -- assigned user
        a.assigned_user_id,
        u.user_name                                  as assigned_user_name,
        u.email                                      as assigned_user_email
    from activities a
    left join activity_types at on at.activity_type_key = a.activity_type_key
    left join users          u  on u.user_id            = a.assigned_user_id

)

select * from final
