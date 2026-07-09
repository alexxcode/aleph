with users as (

    select * from {{ ref('stg_thelook__users') }}

),

customer_orders as (

    select * from {{ ref('int_customer_orders') }}

),

final as (

    select
        -- clave
        users.user_id as customer_id,

        -- atributos personales
        users.first_name,
        users.last_name,
        users.email,
        users.age,
        users.gender,

        -- ubicación
        users.country,
        users.state,
        users.city,
        users.postal_code,

        -- adquisición
        users.traffic_source,
        users.created_at as signed_up_at,

        -- comportamiento de compra (de int_customer_orders)
        customer_orders.first_order_at,
        customer_orders.most_recent_order_at,
        coalesce(customer_orders.lifetime_orders, 0) as lifetime_orders,
        customer_orders.first_order_at is not null   as has_ordered

    from users
    left join customer_orders
        on users.user_id = customer_orders.user_id

)

select * from final
