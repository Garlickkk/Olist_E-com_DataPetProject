WITH counts (table_name, actual_rows, expected_rows) AS (
    SELECT 'orders', COUNT(*), 99441 FROM raw.orders
    UNION ALL
    SELECT 'customers', COUNT(*), 99441 FROM raw.customers
    UNION ALL
    SELECT 'order_items', COUNT(*), 112650 FROM raw.order_items
    UNION ALL
    SELECT 'order_payments', COUNT(*), 103886 FROM raw.order_payments
    UNION ALL
    SELECT 'order_reviews', COUNT(*), 99224 FROM raw.order_reviews
    UNION ALL
    SELECT 'products', COUNT(*), 32951 FROM raw.products
    UNION ALL
    SELECT 'sellers', COUNT(*), 3095 FROM raw.sellers
    UNION ALL
    SELECT 'geolocation', COUNT(*), 1000163 FROM raw.geolocation
    UNION ALL
    SELECT 'category_translation', COUNT(*), 71 FROM raw.category_translation
)
SELECT
    table_name,
    actual_rows,
    expected_rows,
    actual_rows = expected_rows AS row_count_matches
FROM counts
ORDER BY table_name;