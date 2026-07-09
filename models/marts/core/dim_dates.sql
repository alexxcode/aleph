-- Dimensión de fechas generada con dbt_date. Cubre el rango de los datos
-- de thelook con holgura hacia adelante (los datos son "vivos").
{{ dbt_date.get_date_dimension("2018-01-01", "2027-12-31") }}
