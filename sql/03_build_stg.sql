CREATE SCHEMA IF NOT EXISTS stg;

CREATE OR REPLACE VIEW stg.orders AS 
SELECT
    order_id,
    customer_id,
    order_status,
    NULLIF(order_purchase_timestamp, '')::timestamp AS order_purchase_timestamp,
    NULLIF(order_approved_at, '')::timestamp AS order_approved_at,
    NULLIF(order_delivered_carrier_date, '')::timestamp AS order_delivered_carrier_date,
    NULLIF(order_delivered_customer_date, '')::timestamp AS order_delivered_customer_date,
    NULLIF(order_estimated_delivery_date, '')::date AS order_estimated_delivery_date,
    CASE
        WHEN order_status = 'delivered' THEN
        NULLIF(order_delivered_customer_date, '')::date
        > NULLIF(order_estimated_delivery_date, '')::date
    END AS is_late
FROM raw.orders;


SELECT
    COUNT(*) AS total_orders,
    COUNT(is_late) AS intime_orders,
    COUNT(*) FILTER (WHERE order_status = 'delivered' AND is_late IS NULL) AS delivered_without_result
FROM stg.orders;