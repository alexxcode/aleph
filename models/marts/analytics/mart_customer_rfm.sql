-- Segmentación RFM de clientes con al menos una compra. Scores 1-5 por quintiles
-- (recency invertida: más reciente = mejor) y etiqueta de segmento.

with orders as (

    select * from {{ ref('fct_orders') }}

),

customers as (

    select customer_id, first_name, last_name, gender, country, traffic_source
    from {{ ref('dim_customers') }}

),

as_of as (

    select max(order_date) as as_of_date from orders

),

customer_orders as (

    select
        user_id                     as customer_id,
        count(distinct order_id)    as frequency,
        sum(gross_revenue)          as monetary,
        max(order_date)             as last_order_date
    from orders
    where status != 'Cancelled'
    group by user_id

),

rfm_base as (

    select
        customer_id,
        date_diff((select as_of_date from as_of), last_order_date, day) as recency_days,
        frequency,
        monetary
    from customer_orders

),

scored as (

    select
        customer_id,
        recency_days,
        frequency,
        monetary,
        ntile(5) over (order by recency_days desc) as r_score,
        ntile(5) over (order by frequency asc)     as f_score,
        ntile(5) over (order by monetary asc)      as m_score
    from rfm_base

),

final as (

    select
        scored.customer_id,
        customers.first_name,
        customers.last_name,
        customers.country,
        customers.traffic_source,

        scored.recency_days,
        scored.frequency,
        scored.monetary,
        scored.r_score,
        scored.f_score,
        scored.m_score,
        scored.r_score * 100 + scored.f_score * 10 + scored.m_score as rfm_score,
        scored.frequency > 1 as is_repeat_customer,

        case
            when scored.r_score >= 4 and scored.f_score >= 4 then 'Champions'
            when scored.r_score >= 3 and scored.f_score >= 3 then 'Loyal'
            when scored.r_score >= 4 and scored.f_score <= 2 then 'New'
            when scored.r_score <= 2 and scored.f_score >= 3 then 'At Risk'
            when scored.r_score <= 2 and scored.f_score <= 2 then 'Hibernating'
            else 'Others'
        end as segment

    from scored
    left join customers
        on scored.customer_id = customers.customer_id

)

select * from final
