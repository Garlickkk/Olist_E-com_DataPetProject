CREATE SCHEMA IF NOT EXISTS mart;

CREATE OR REPLACE VIEW mart.orders AS
WITH items_by_order AS (
    SELECT
        order_id,
        COUNT(*) AS item_count,
        COUNT(DISTINCT NULLIF(seller_id, '')) AS seller_count,
        CASE
            WHEN COUNT(DISTINCT NULLIF(seller_id, '')) = 1
            AND COUNT(NULLIF(seller_id, '')) = COUNT(*)
            THEN MIN(seller_id)
        END AS single_seller_id,
        SUM(NULLIF(price, '')::numeric) AS items_total,
        SUM(NULLIF(freight_value, '')::numeric) AS freight_total
    FROM 
		raw.order_items
    GROUP BY 
		order_id
),


payments_by_order AS (
    SELECT
        order_id,
        SUM(NULLIF(payment_value, '')::numeric) AS payment_total
    FROM 
		raw.order_payments
    GROUP BY 
		order_id
),


latest_review AS (
    SELECT DISTINCT ON (order_id) -- 1 отзыв для каждого order_id
        order_id,
        NULLIF(review_score, '')::integer AS review_score
    FROM 
		raw.order_reviews
    ORDER BY
        order_id,
        NULLIF(review_answer_timestamp, '')::timestamp DESC NULLS LAST,
        NULLIF(review_creation_date, '')::timestamp DESC NULLS LAST,
        review_id,
        NULLIF(review_score, '')::integer
)


SELECT
    o.order_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    o.is_late,
    CASE
        WHEN o.order_status = 'delivered'
         AND o.order_delivered_customer_date >= o.order_purchase_timestamp
        THEN EXTRACT(EPOCH FROM (
            o.order_delivered_customer_date - o.order_purchase_timestamp
        )) / 86400
    END AS delivery_days, -- в остальных случаях будут NULL
    o.customer_id,
    c.customer_unique_id,
    c.customer_state,
    i.item_count,
    i.seller_count,
    i.single_seller_id,
    s.seller_state,
    s.seller_state <> c.customer_state AS is_interstate,
    i.items_total,
    i.freight_total,
    p.payment_total,
    r.review_score
FROM 
	stg.orders AS o
LEFT JOIN raw.customers AS c 
	ON c.customer_id = o.customer_id
LEFT JOIN items_by_order AS i 
	ON i.order_id = o.order_id
LEFT JOIN raw.sellers AS s 
	ON s.seller_id = i.single_seller_id
LEFT JOIN payments_by_order AS p 
	ON p.order_id = o.order_id
LEFT JOIN latest_review AS r
	ON r.order_id = o.order_id;

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id) AS unique_orders,
    SUM(items_total) AS items_total,
    SUM(freight_total) AS freight_total,
    SUM(payment_total) AS payment_total
FROM mart.orders;

SELECT * 
FROM mart.orders;


CREATE OR REPLACE VIEW mart.order_items AS
SELECT
    i.order_id,
    i.order_item_id,
    i.product_id,
    i.seller_id,
    prod.product_category_name,
    ct.product_category_name_english,
    s.seller_state,
    NULLIF(i.price, '')::numeric AS price,
    NULLIF(i.freight_value, '')::numeric AS freight_value
FROM 
	raw.order_items AS i
LEFT JOIN raw.products AS prod
    ON prod.product_id = i.product_id
LEFT JOIN raw.category_translation AS ct
    ON ct.product_category_name = prod.product_category_name
LEFT JOIN raw.sellers AS s
    ON s.seller_id = i.seller_id;

SELECT 
	COUNT(*),
	COUNT(DISTINCT(order_id, order_item_id))
FROM
	mart.order_items;



CREATE OR REPLACE VIEW mart.customer_cohorts AS
WITH parameters AS (
    SELECT TIMESTAMP '2018-09-01 00:00:00' AS observation_end
),
orders_source AS MATERIALIZED (
    SELECT
        customer_unique_id,
        order_id,
        order_status,
        order_purchase_timestamp,
        order_delivered_customer_date,
        is_late
    FROM 
		mart.orders
),
ranked_deliveries AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY order_delivered_customer_date, order_id
        ) AS delivery_number
    FROM 
		orders_source
    WHERE order_status = 'delivered'
      AND customer_unique_id IS NOT NULL
      AND order_delivered_customer_date IS NOT NULL
),
eligible_customers AS (
    SELECT
        d.customer_unique_id,
        d.order_id AS first_order_id,
        d.order_delivered_customer_date AS first_delivery_at,
        DATE_TRUNC('month',d.order_delivered_customer_date)::date AS cohort_month,
        d.is_late,
        p.observation_end
    FROM 
		ranked_deliveries AS d
    CROSS JOIN parameters AS p
    WHERE d.delivery_number = 1
      AND d.is_late IS NOT NULL
      AND d.order_purchase_timestamp IS NOT NULL
      AND d.order_delivered_customer_date >= d.order_purchase_timestamp
      AND d.order_delivered_customer_date + INTERVAL '90 days'
          < p.observation_end
),
customer_results AS (
    SELECT
        e.customer_unique_id,
        e.cohort_month,
        e.is_late,
        BOOL_OR(r.order_id IS NOT NULL) AS has_repeat_order
    FROM eligible_customers AS e
    LEFT JOIN orders_source AS r
        ON r.customer_unique_id = e.customer_unique_id
       AND r.order_id <> e.first_order_id
       AND r.order_purchase_timestamp > e.first_delivery_at
       AND r.order_purchase_timestamp
           <= e.first_delivery_at + INTERVAL '90 days'
       AND r.order_purchase_timestamp < e.observation_end
       AND r.order_status IN (
           'approved',
           'invoiced',
           'processing',
           'shipped',
           'delivered'
       )
    GROUP BY
        e.customer_unique_id,
        e.cohort_month,
        e.is_late
)
SELECT
    cohort_month,
    is_late,
    COUNT(*) AS eligible_customers,
    COUNT(*) FILTER (WHERE has_repeat_order) AS repeat_customers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE has_repeat_order) / COUNT(*),2) AS repeat_purchase_rate_90d_pct
FROM 
	customer_results
GROUP BY cohort_month, 
	is_late;

SELECT 
	*
FROM 
	mart.customer_cohorts
ORDER BY 
	cohort_month, 
	is_late;
