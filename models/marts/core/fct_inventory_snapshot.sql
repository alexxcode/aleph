{{
    config(
        materialized='incremental',
        incremental_strategy='insert_overwrite',
        partition_by={'field': 'snapshot_date', 'data_type': 'date'},
        cluster_by=['product_id', 'distribution_center_id'],
        on_schema_change='sync_all_columns'
    )
}}

-- Foto diaria de inventario por producto x centro. Se reconstruye el on-hand
-- a partir de eventos de entrada (created_at) y salida (sold_at) del inventario,
-- con saldo de apertura para que el primer día de la ventana sea correcto.

{% set window_start = var('inventory_snapshot_start_date') %}

with inventory as (

    select
        product_id,
        distribution_center_id,
        cost,
        date(created_at) as in_date,
        date(sold_at)    as out_date
    from {{ ref('stg_thelook__inventory_items') }}

),

-- combinaciones producto x centro con inventario en algún momento
combos as (

    select distinct product_id, distribution_center_id
    from inventory

),

-- spine de fechas acotado a la ventana configurada
spine as (

    select date_day
    from {{ ref('dim_dates') }}
    where date_day >= date('{{ window_start }}')
      and date_day <= current_date()

),

-- eventos dentro de la ventana: +1 al entrar a stock, -1 al venderse
deltas_in_window as (

    select product_id, distribution_center_id, in_date as event_date, 1 as unit_delta, cost as cost_delta
    from inventory
    where in_date >= date('{{ window_start }}')

    union all

    select product_id, distribution_center_id, out_date as event_date, -1 as unit_delta, -cost as cost_delta
    from inventory
    where out_date is not null
      and out_date >= date('{{ window_start }}')

),

-- saldo de apertura: neto de todo lo ocurrido ANTES de la ventana,
-- imputado al primer día del spine
opening as (

    select
        product_id,
        distribution_center_id,
        date('{{ window_start }}') as event_date,
        countif(in_date < date('{{ window_start }}'))
            - countif(out_date is not null and out_date < date('{{ window_start }}')) as unit_delta,
        sum(if(in_date < date('{{ window_start }}'), cost, 0))
            - sum(if(out_date is not null and out_date < date('{{ window_start }}'), cost, 0)) as cost_delta
    from inventory
    group by product_id, distribution_center_id

),

all_deltas as (

    select product_id, distribution_center_id, event_date, unit_delta, cost_delta from deltas_in_window
    union all
    select product_id, distribution_center_id, event_date, unit_delta, cost_delta from opening

),

daily_deltas as (

    select
        product_id,
        distribution_center_id,
        event_date,
        sum(unit_delta) as unit_delta,
        sum(cost_delta) as cost_delta
    from all_deltas
    group by product_id, distribution_center_id, event_date

),

-- rejilla densa combo x día
scaffold as (

    select
        combos.product_id,
        combos.distribution_center_id,
        spine.date_day as snapshot_date
    from combos
    cross join spine

),

joined as (

    select
        scaffold.product_id,
        scaffold.distribution_center_id,
        scaffold.snapshot_date,
        coalesce(daily_deltas.unit_delta, 0) as unit_delta,
        coalesce(daily_deltas.cost_delta, 0) as cost_delta
    from scaffold
    left join daily_deltas
        on  daily_deltas.product_id = scaffold.product_id
        and daily_deltas.distribution_center_id = scaffold.distribution_center_id
        and daily_deltas.event_date = scaffold.snapshot_date

),

running as (

    select
        product_id,
        distribution_center_id,
        snapshot_date,
        sum(unit_delta) over (
            partition by product_id, distribution_center_id
            order by snapshot_date
        ) as units_on_hand,
        sum(cost_delta) over (
            partition by product_id, distribution_center_id
            order by snapshot_date
        ) as inventory_cost_on_hand
    from joined

)

select *
from running

{% if is_incremental() %}
where snapshot_date >= date_sub(
    (select max(snapshot_date) from {{ this }}), interval 3 day
)
{% endif %}
