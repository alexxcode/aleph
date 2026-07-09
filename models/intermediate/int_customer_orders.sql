with orders as (

    select * from {{ ref('stg_thelook__orders') }}

),

aggregated as (

    select
        user_id,
        min(created_at)  as first_order_at,
        max(created_at)  as most_recent_order_at,
        count(*)         as lifetime_orders
    from orders
    group by user_id

)

select * from aggregated
