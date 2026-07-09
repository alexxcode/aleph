with distribution_centers as (

    select * from {{ ref('stg_thelook__distribution_centers') }}

),

final as (

    select
        distribution_center_id,
        distribution_center_name,
        latitude,
        longitude
    from distribution_centers

)

select * from final
