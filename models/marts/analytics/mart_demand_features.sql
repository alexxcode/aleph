-- Tabla de features para el forecast de demanda. Grano: categoría x semana
-- (semana inicia lunes). Panel denso (zero-fill) con lags, medias móviles,
-- calendario y señales de tráfico web. Alimenta el modelo LightGBM (Fase 6).

with weeks as (

    select week_start_date
    from unnest(generate_date_array(
        (select date_trunc(min(order_date), week(monday)) from {{ ref('fct_order_items') }}),
        (select date_trunc(max(order_date), week(monday)) from {{ ref('fct_order_items') }}),
        interval 1 week
    )) as week_start_date

),

categories as (

    select distinct category
    from {{ ref('dim_products') }}
    where category is not null

),

spine as (

    select
        categories.category,
        weeks.week_start_date
    from categories
    cross join weeks

),

weekly_sales as (

    select
        products.category,
        date_trunc(order_items.order_date, week(monday)) as week_start_date,
        count(*)                as units_sold,
        sum(order_items.sale_price) as revenue
    from {{ ref('fct_order_items') }} as order_items
    inner join {{ ref('dim_products') }} as products
        on order_items.product_id = products.product_id
    where products.category is not null
    group by category, week_start_date

),

weekly_events as (

    select
        date_trunc(date(created_at), week(monday))          as week_start_date,
        count(*)                                            as events_total,
        countif(event_type = 'purchase')                   as events_purchase,
        countif(event_type = 'cart')                        as events_cart
    from {{ ref('stg_thelook__events') }}
    group by week_start_date

),

joined as (

    select
        spine.category,
        spine.week_start_date,
        coalesce(weekly_sales.units_sold, 0)   as units_sold,
        coalesce(weekly_sales.revenue, 0)      as revenue,
        coalesce(weekly_events.events_total, 0)    as events_total,
        coalesce(weekly_events.events_purchase, 0) as events_purchase,
        coalesce(weekly_events.events_cart, 0)     as events_cart
    from spine
    left join weekly_sales
        on spine.category = weekly_sales.category
       and spine.week_start_date = weekly_sales.week_start_date
    left join weekly_events
        on spine.week_start_date = weekly_events.week_start_date

),

features as (

    select
        category,
        week_start_date,
        units_sold,
        revenue,
        events_total,
        events_purchase,
        events_cart,

        -- calendario
        extract(isoweek from week_start_date) as week_of_year,
        extract(month   from week_start_date) as month_of_year,
        extract(year    from week_start_date) as year_number,

        -- lags (semanas previas, sin fuga del presente)
        lag(units_sold, 1) over w as lag_1w,
        lag(units_sold, 2) over w as lag_2w,
        lag(units_sold, 4) over w as lag_4w,
        lag(units_sold, 8) over w as lag_8w,

        -- medias móviles excluyendo la semana actual
        avg(units_sold) over (partition by category order by week_start_date
            rows between 4 preceding and 1 preceding)  as roll_mean_4w,
        avg(units_sold) over (partition by category order by week_start_date
            rows between 12 preceding and 1 preceding) as roll_mean_12w,
        stddev_pop(units_sold) over (partition by category order by week_start_date
            rows between 12 preceding and 1 preceding) as roll_std_12w

    from joined
    window w as (partition by category order by week_start_date)

)

select * from features
