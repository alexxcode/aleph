with source as (

    select * from {{ source('thelook', 'orders') }}

),

renamed as (

    select
        -- claves
        order_id,
        user_id,

        -- atributos
        status,
        gender,
        num_of_item as num_of_items,

        -- timestamps
        created_at,
        shipped_at,
        delivered_at,
        returned_at

    from source

)

select * from renamed
