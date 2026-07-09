with source as (

    select * from {{ source('thelook', 'events') }}

),

renamed as (

    select
        -- claves
        id as event_id,
        user_id,
        session_id,
        sequence_number,

        -- atributos del evento
        event_type,
        uri,
        traffic_source,
        browser,

        -- ubicación
        city,
        state,
        postal_code,
        ip_address,

        -- timestamps
        created_at

    from source

)

select * from renamed
