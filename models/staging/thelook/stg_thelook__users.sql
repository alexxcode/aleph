with source as (

    select * from {{ source('thelook', 'users') }}

),

renamed as (

    select
        -- claves
        id as user_id,

        -- atributos personales
        first_name,
        last_name,
        email,
        age,
        gender,

        -- ubicación
        country,
        state,
        city,
        postal_code,
        street_address,
        latitude,
        longitude,
        user_geom,

        -- adquisición
        traffic_source,

        -- timestamps
        created_at

    from source

)

select * from renamed
