# Staging layer

One-to-one with the raw Pipedrive source tables (and seeds): rename + cast only,
no joins, filters, aggregation or business logic. Materialised as views.

## Model naming — `stg_<source>__<object>`

- `stg_` marks the layer; `<source>` is the source system (`pipedrive`);
  `<object>` is the entity (`users`, `deal_changes`).
- **Double** underscore between source and object because each part can itself
  contain a single underscore (`activity_types`) — keeps the two parts readable.
- Namespacing by source keeps names unique if a second system also has a
  `users` / `fields` table later.
- File name = model name (dbt Labs standard convention).
- **Seeds** get a staging model too (so nothing downstream refs a raw seed),
  under the `seed` origin token instead of a source system:
  `stg_seed__funnel_steps`.

## Column naming — unified across all models

- `*_id` — keys, always `<entity>_id` (`user_id`, `deal_id`, `assigned_user_id`).
- `*_at` — timestamps (`modified_at`, `due_at`, `changed_at`, `deal_created_at`).
- `is_*` — booleans (`is_active`, `is_done`, `is_enum_field`).
- `*_key` — external/business string keys (`field_key`, `activity_type_key`).
- Plain nouns for the rest (`user_name`, `email`, `stage_name`).
- snake_case, lower-case; cryptic source names expanded
  (`due_to` → `due_at`, `modified` → `modified_at`,
  `assigned_to_user` → `assigned_user_id`).
- The point: the same concept has the **same name everywhere**, so downstream
  joins line up without aliasing.

## Test distribution — source vs staging

- **Source (`sources.yml`)** — "did the raw feed load intact and on time?"
  - `freshness` and primary-key tests (`unique` + `not_null` on the id) only.
  - One deliberate exception: `accepted_values ['Yes','No']` on
    `activity_types.active` — a raw-feed enum check with no staging column to
    attach it to (staging exposes only the derived boolean `is_active`).
- **Staging (`stg_*.yml`)** — "is the shaped output correct, for everything that
  `ref()`s it?"
  - `accepted_values`, `relationships` (FKs, e.g.
    `changed_field_key` → `stg_pipedrive__fields.field_key`), `not_null` on
    non-key columns, natural-key `unique` (`activity_type_key`, `field_key`),
    and the `warn`-severity `unique` on the non-unique `activity_id`.
- Rule: never assert the same thing in both layers — source = upstream
  contract, staging = transformation correctness.
