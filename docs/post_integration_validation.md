# Post-integration validation

Checks run against the built models (schema `public_pipedrive_analytics`) after
the whole pipeline runs — to confirm the aggregations are correct, and to
document behaviour that looks wrong but isn't. Each item is reproducible SQL.

1. `rep_sales_funnel_monthly` — the monthly funnel is a flow, not a cumulative
   shape (proven correct; codified as tests).
2. Sub-steps `2.1` / `3.1` are activity volume on a deal population disjoint
   from the funnel — a source-data limitation, made explicit in `kpi_name`.

---

## 1. `rep_sales_funnel_monthly` — the monthly funnel does not shrink step-by-step, and that is correct

**Observation.** Read straight down one month, `deals_count` is not monotonic —
e.g. for `2024-06-01`:

| step | kpi_name | deals_count |
|--:|---|--:|
| 1 | Lead Generation (stage) | 244 |
| 2 | Qualified Lead (stage) | **245** |
| 3 | Needs Assessment (stage) | **247** |
| 4 | Proposal/Quote Preparation (stage) | 240 |
| 5 | Negotiation (stage) | 206 |
| 6 | Closing (stage) | 181 |
| 7 | Implementation/Onboarding (stage) | 138 |
| 8 | Follow-up/Customer Success (stage) | 98 |
| 9 | Renewal/Expansion (stage) | 42 |

**Explanation.** `deals_count(month M, step N)` = distinct deals whose stage
**first reached N during M** — an *entry rate*, not a running total. A deal's
"reached step 1" and "reached step 2" events usually fall in different months, so
a month's step-N rows are a **different deal set** than its step-(N-1) rows. The
funnel is monotonic only when the deal set is held fixed (all-time, or one
cohort).

### 1a. All-time funnel is strictly non-increasing

```sql
select funnel_step, count(distinct deal_id) as deals
from public_pipedrive_analytics.fct_deal_stage_progression
group by 1 order by 1;
```

| step | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| deals | 1995 | 1990 | 1951 | 1862 | 1693 | 1424 | 1081 | 723 | 324 |

Guaranteed by construction: `fct_deal_stage_progression` emits a row for **every**
gate crossed on a forward move (`generate_series(prev+1, new)` in the lateral
join), so "reached step N" implies a row for every step `< N`. Reaching N is a
strict subset of reaching N-1.

### 1b. A single month mixes cohorts

```sql
with sr as (select * from public_pipedrive_analytics.fct_deal_stage_progression),
first_reach_month as (
  select deal_id, min(reached_month) as cohort_month
  from sr where funnel_step = 1 group by 1
)
select
  sr.funnel_step,
  count(distinct sr.deal_id)                                                     as june_total,
  count(distinct sr.deal_id) filter (where fr.cohort_month =  date '2024-06-01') as created_in_june,
  count(distinct sr.deal_id) filter (where fr.cohort_month <  date '2024-06-01') as created_earlier
from sr
join first_reach_month fr using (deal_id)
where sr.reached_month = date '2024-06-01' and sr.funnel_step <= 9
group by 1 order by 1;
```

| step | june_total | created_in_june | created_earlier |
|--:|--:|--:|--:|
| 1 | 244 | 244 | 0 |
| 2 | 245 | 123 | **122** |
| 3 | 247 | 62 | **185** |
| 4 | 240 | 37 | 203 |
| 5 | 206 | 17 | 189 |
| 9 | 42 | 0 | 42 |

June's step-2 count (245) is 123 deals created in June **plus** 122 older deals
that only advanced to stage 2 in June — not a wider funnel, a bigger feeder pool.

### 1c. A single creation-month cohort is non-increasing

```sql
with sr as (select * from public_pipedrive_analytics.fct_deal_stage_progression),
cohort as (select deal_id from sr where funnel_step = 1 and reached_month = date '2024-06-01')
select sr.funnel_step, count(distinct sr.deal_id)
from sr join cohort using (deal_id)
group by 1 order by 1;
```

| step | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| deals | 244 | 244 | 241 | 232 | 209 | 176 | 134 | 84 | 41 |

### 1d. The monthly numbers reconcile to the all-time totals

```sql
select m.funnel_step,
       sum(m.cnt) as sum_of_months,
       (select count(distinct deal_id)
        from public_pipedrive_analytics.fct_deal_stage_progression p
        where p.funnel_step = m.funnel_step) as all_time
from (
  select funnel_step, reached_month, count(distinct deal_id) cnt
  from public_pipedrive_analytics.fct_deal_stage_progression
  group by 1, 2
) m
group by 1 order by 1;
```

`sum_of_months = all_time` for every step (1995, 1990, 1951, 1862, 1693, 1424,
1081, 723, 324). No double-counting, no leakage — the monthly table is the
all-time funnel sliced by entry month.

**Conclusion.** The model is correct. To read the funnel as a narrowing shape,
aggregate away `month` (all-time) or filter to one cohort; a single calendar
month is a flow across mixed cohorts.

**Codified as tests.** Checks 1a and 1d run on every build:

- `tests/assert_rep_sales_funnel_monthly_monotonic.sql` — steps 1–9, all-time,
  non-increasing (1a).
- `tests/assert_rep_sales_funnel_monthly_reconciles.sql` — per step,
  `sum(monthly deals_count) == distinct deals in the source fact` (1d, extended
  to the 2.1 / 3.1 activity sub-steps).

---

## 2. Sub-steps `2.1` / `3.1` (Sales Call 1 / 2) are activity volume, not a funnel sub-count

**Observation.** Read down a single month, the *stage* steps 1–9 are fine, but
the two Sales Call rows sit higher than the stages around them — e.g.
`2024-02-01`:

| step | kpi_name | deals_count |
|--:|---|--:|
| 2 | Qualified Lead (stage) | 92 |
| **2.1** | **Sales Call 1 (activity)** | **117** |
| 3 | Needs Assessment (stage) | 49 |
| **3.1** | **Sales Call 2 (activity)** | **117** |
| 4 | Proposal/Quote Preparation (stage) | 31 |

Stage-only for 2024-02: `194, 92, 49, 31, 20, 11, 3, 2, 2` — non-increasing.
The bumps are entirely `2.1` / `3.1`.

**Explanation.** `2.1` / `3.1` are counts from `fct_activities` (deals with a
Sales Call 1 / 2 activity **due** that month). That deal population is
near-disjoint from the `deal_changes` funnel deals, so they are **not**
sub-counts of steps 2 / 3 — a Sales Call row and its neighbouring stage rows
describe different companies. They are placed at `2.1` / `3.1` because the brief
lists them there; the `kpi_name` suffix `(activity)` vs `(stage)` marks the
distinction on every row.

### 2a. The two deal populations barely overlap

```sql
-- distinct deals in each universe, and the intersection
select
  (select count(distinct deal_id) from public.activity)                                            as activity_deals,
  (select count(distinct deal_id) from public.deal_changes)                                         as funnel_deals,
  (select count(distinct deal_id) from public.activity
     where deal_id in (select deal_id from public.deal_changes))                                    as in_both;
```

`activity_deals = 4572`, `funnel_deals = 1995`, `in_both = 8`.

### 2b. `activity.deal_id` is not malformed — it is independently random

Same format (all 6-digit), same range (`activity` 100007–999826, `deal_changes`
100086–999037). The observed overlap of 8 matches what you would get from two
**independent** random draws from the 6-digit space:

```
expected overlap = activity_deals * funnel_deals / 900000
                 = 4572 * 1995 / 900000  ≈ 10       (observed 8)
```

An expected-collision count: each of the 4572 activity ids has a `1995 / 900000`
chance of landing on a real funnel deal, so ≈ 10 hits by chance alone. If the
ids were the *same* deals with an encoding bug you would see ~1995 matches, not
8 — this rules out "malformed but recoverable".

```sql
-- constant offset: does (activity.deal_id - k) land in deal_changes for any k?
select k, (select count(distinct a.deal_id) from public.activity a
           where (a.deal_id - k) in (select deal_id from public.deal_changes)) as hits
from (values (0),(1),(-1),(10),(100),(1000),(79),(-79)) t(k);
-- -> every k gives 5-15 hits (noise). A real offset would give ~1900.

-- digits reversed
select count(*) from public.activity a
where reverse(a.deal_id::text)::bigint in (select deal_id from public.deal_changes);
-- -> 5 (noise)

-- is it actually the activity_id space?
select count(*) from public.activity where deal_id = activity_id;   -- -> 0
```

(`activity.assigned_to_user` *does* link cleanly to `users` — 0 orphans — so the
table isn't garbage; only the `deal_id` linkage was never generated.)

### 2c. Restricting `2.1` to funnel deals collapses it to nothing

```sql
select count(distinct a.deal_id)
from public.activity a
where a.type = 'meeting'                                    -- Sales Call 1
  and a.deal_id in (select deal_id from public.deal_changes);
```

| definition | deals, all-time |
|---|--:|
| current — any deal with a Sales Call 1 activity | 1145 |
| Sales Call 1 **and** deal is in the funnel | **2** |

**Conclusion.** The disjointness is a source-data artifact and cannot be
cleaned. The pragmatic choice was made: keep `2.1` / `3.1` to satisfy the brief,
report them as **activity volume**, and mark every row's kind in `kpi_name` so
they cannot be read as sub-counts of steps 2 / 3. If activity–deal linkage is
ever fixed upstream, restrict them to deals that reached stage 2 / 3, at which
point `2.1 <= step 2` becomes a valid invariant. This is a data-quality issue to
raise with the CRM owner.
