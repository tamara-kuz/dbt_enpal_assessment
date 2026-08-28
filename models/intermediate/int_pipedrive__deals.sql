-- One row per deal, parsed from the deal_changes event log.
--
-- stg_pipedrive__deal_changes is a long audit log (one row per field change,
-- polymorphic new_value). This model pivots it to a wide deal record: creation
-- time, current + furthest stage, current owner, and the lost_reason.
--
-- Notes from the exploratory analysis:
--   - Every deal has an add_time, at least one stage_id change (always starting
--     at stage 1) and at least one user_id change, so those columns are never
--     null. A handful of deals log add_time / lost_reason twice.
--   - Stage progression is monotonic but skippable, so `max_stage_id` (furthest
--     stage reached) is the field the funnel should use, not `current_stage_id`.
--   - `lost_reason_id` is populated for every deal and is statistically
--     uniform -- it is NOT a won/lost signal. Carried through as-is; do not
--     derive deal status from it here.

with deal_changes as (

    select * from {{ ref('stg_pipedrive__deal_changes') }}

),

-- the spine: one row per deal, so a deal with no owner / lost row still appears
deal_ids as (

    select distinct deal_id from deal_changes

),

-- staging routes changed_field_key -> typed columns; each new_* helper is
-- non-null only for its field key, so we filter on those, not the raw strings.

-- deal creation time, from the add_time change(s)
created as (

    select
        deal_id,
        min(deal_created_at) as created_at   -- some deals log add_time more than once; earliest wins
    from deal_changes
    where deal_created_at is not null
    group by 1

),

-- stage-change rollup: how many, first / last time, furthest + latest stage.
--
-- `(array_agg(x order by changed_at desc))[1]` = the value from the most recent
-- row in the group. Postgres has no LAST()/ARG_MAX aggregate and no QUALIFY, so
-- this is the terse way to get "latest value" AND count(*)/min/max in one
-- grouped pass. `distinct on` would read cleaner but needs a second CTE + join
-- for the counts. `max(new_stage_id)` is a different thing (furthest reached,
-- not latest) - both are kept.
--
-- Equivalent to, on a warehouse that has QUALIFY (Snowflake / BigQuery):
--   qualify row_number() over (partition by deal_id
--                              order by changed_at desc, new_stage_id desc) = 1
-- (kept as one grouped query so the counts come for free). On Snowflake the
-- direct swap is max_by(new_stage_id, changed_at).
stages as (

    select
        deal_id,
        count(*)                                                             as stage_change_count,
        min(changed_at)                                                      as first_stage_changed_at,
        max(changed_at)                                                      as last_stage_changed_at,
        max(new_stage_id)                                                    as max_stage_id,
        -- tie-break on new_stage_id desc for the rare same-timestamp changes
        (array_agg(new_stage_id order by changed_at desc, new_stage_id desc))[1] as current_stage_id
    from deal_changes
    where new_stage_id is not null
    group by 1

),

-- owner-change rollup: how many reassignments, and the most recent owner
-- (array_agg[1] = latest value in group; see the `stages` CTE note)
owners as (

    select
        deal_id,
        count(*)                                                    as owner_change_count,
        (array_agg(new_owner_user_id order by changed_at desc))[1]  as current_owner_user_id
    from deal_changes
    where new_owner_user_id is not null
    group by 1

),

-- lost_reason: the latest code recorded and when (some deals log it more than once)
-- (array_agg[1] = latest value in group; see the `stages` CTE note)
lost as (

    select
        deal_id,
        (array_agg(new_lost_reason_id order by changed_at desc))[1] as lost_reason_id,
        max(changed_at)                                             as lost_reason_at
    from deal_changes
    where new_lost_reason_id is not null
    group by 1

),

-- one row per deal; left joins so missing sub-aggregates don't drop the deal.
-- created_month falls back to the first stage change if add_time is somehow absent.
final as (

    select
        d.deal_id,

        c.created_at,
        cast(date_trunc('month', coalesce(c.created_at, s.first_stage_changed_at)) as date) as created_month,

        o.current_owner_user_id,
        coalesce(o.owner_change_count, 0)    as owner_change_count,

        s.current_stage_id,
        s.max_stage_id,
        s.first_stage_changed_at,
        s.last_stage_changed_at,
        coalesce(s.stage_change_count, 0)    as stage_change_count,

        l.lost_reason_id,
        l.lost_reason_at
    from deal_ids d
    left join created c on c.deal_id = d.deal_id
    left join stages  s on s.deal_id = d.deal_id
    left join owners  o on o.deal_id = d.deal_id
    left join lost    l on l.deal_id = d.deal_id

)

select * from final
