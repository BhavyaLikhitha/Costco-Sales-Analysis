-- ============================================================
-- Costco Sales Analysis: Exploratory Data Analysis
-- Covers: row counts, data quality, distributions, anomalies
-- ============================================================

-- ─────────────────────────────────
-- 1. DATASET OVERVIEW
-- ─────────────────────────────────

-- Row counts per table
SELECT 'customers'     AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL
SELECT 'products',                     COUNT(*)             FROM products
UNION ALL
SELECT 'orders',                       COUNT(*)             FROM orders
UNION ALL
SELECT 'sales_targets',                COUNT(*)             FROM sales_targets;

-- Date range of the sales data
SELECT
    MIN(order_date)                                               AS earliest_order,
    MAX(order_date)                                               AS latest_order,
    MAX(order_date) - MIN(order_date)                             AS day_span,
    COUNT(DISTINCT EXTRACT(YEAR FROM order_date)::INT)            AS years_covered
FROM orders;

-- Order vs line-item counts
SELECT
    COUNT(DISTINCT order_id)                                      AS unique_orders,
    COUNT(*)                                                      AS total_line_items,
    COUNT(DISTINCT customer_id)                                   AS active_customers,
    COUNT(DISTINCT product_id)                                    AS products_sold,
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT order_id), 2)          AS avg_items_per_order
FROM orders;

-- ─────────────────────────────────
-- 2. NULL VALUE CHECKS
-- ─────────────────────────────────

-- Customers
SELECT
    COUNT(*) FILTER (WHERE customer_name IS NULL) AS null_name,
    COUNT(*) FILTER (WHERE segment       IS NULL) AS null_segment,
    COUNT(*) FILTER (WHERE region        IS NULL) AS null_region,
    COUNT(*) FILTER (WHERE state         IS NULL) AS null_state,
    COUNT(*) FILTER (WHERE city          IS NULL) AS null_city
FROM customers;

-- Products
SELECT
    COUNT(*) FILTER (WHERE product_name IS NULL) AS null_name,
    COUNT(*) FILTER (WHERE category     IS NULL) AS null_category,
    COUNT(*) FILTER (WHERE sub_category IS NULL) AS null_sub_category,
    COUNT(*) FILTER (WHERE unit_price   IS NULL) AS null_unit_price,
    COUNT(*) FILTER (WHERE cogs         IS NULL) AS null_cogs
FROM products;

-- Orders
SELECT
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS null_customer_id,
    COUNT(*) FILTER (WHERE product_id  IS NULL) AS null_product_id,
    COUNT(*) FILTER (WHERE order_date  IS NULL) AS null_order_date,
    COUNT(*) FILTER (WHERE ship_date   IS NULL) AS null_ship_date,
    COUNT(*) FILTER (WHERE qty         IS NULL) AS null_qty,
    COUNT(*) FILTER (WHERE discount    IS NULL) AS null_discount
FROM orders;

-- ─────────────────────────────────
-- 3. DUPLICATE CHECKS
-- ─────────────────────────────────

-- Duplicate customer_ids
SELECT customer_id, COUNT(*) AS occurrences
FROM customers
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- Duplicate product_ids
SELECT product_id, COUNT(*) AS occurrences
FROM products
GROUP BY product_id
HAVING COUNT(*) > 1;

-- Duplicate order line items (same order + same product)
SELECT order_id, product_id, COUNT(*) AS occurrences
FROM orders
GROUP BY order_id, product_id
HAVING COUNT(*) > 1;

-- ─────────────────────────────────
-- 4. REFERENTIAL INTEGRITY CHECKS
-- ─────────────────────────────────

-- Orders referencing customers that don't exist in the customers table
SELECT DISTINCT o.customer_id AS orphan_customer_id
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- Orders referencing products that don't exist in the products table
SELECT DISTINCT o.product_id AS orphan_product_id
FROM orders o
LEFT JOIN products p ON o.product_id = p.product_id
WHERE p.product_id IS NULL;

-- ─────────────────────────────────
-- 5. CUSTOMER DISTRIBUTIONS
-- ─────────────────────────────────

-- By segment
SELECT
    segment,
    COUNT(*)                                                           AS customer_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1)                AS pct_of_total
FROM customers
GROUP BY segment
ORDER BY customer_count DESC;

-- By region
SELECT
    region,
    COUNT(*)                                                           AS customer_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1)                AS pct_of_total
FROM customers
GROUP BY region
ORDER BY customer_count DESC;

-- By state (top 15)
SELECT
    state,
    region,
    COUNT(*) AS customer_count
FROM customers
GROUP BY state, region
ORDER BY customer_count DESC
LIMIT 15;

-- ─────────────────────────────────
-- 6. PRODUCT DISTRIBUTIONS
-- ─────────────────────────────────

-- Category overview: product count, price range, built-in margin at list price
SELECT
    category,
    COUNT(*)                                                           AS product_count,
    ROUND(MIN(unit_price), 2)                                         AS min_price,
    ROUND(MAX(unit_price), 2)                                         AS max_price,
    ROUND(AVG(unit_price), 2)                                         AS avg_price,
    ROUND(AVG((unit_price - cogs) / unit_price * 100), 1)            AS avg_list_margin_pct
FROM products
GROUP BY category
ORDER BY product_count DESC;

-- Products where cogs >= unit_price (inherently unprofitable at full price)
SELECT product_id, product_name, category, unit_price, cogs,
       ROUND((unit_price - cogs) / NULLIF(unit_price, 0) * 100, 1) AS list_margin_pct
FROM products
WHERE cogs >= unit_price
ORDER BY list_margin_pct;

-- ─────────────────────────────────
-- 7. ORDER DISTRIBUTIONS
-- ─────────────────────────────────

-- Annual order and revenue summary
SELECT
    EXTRACT(YEAR FROM order_date)::INT                                AS year,
    COUNT(DISTINCT order_id)                                          AS unique_orders,
    COUNT(*)                                                          AS line_items,
    SUM(qty)                                                          AS total_qty
FROM orders
GROUP BY year
ORDER BY year;

-- Ship mode distribution
SELECT
    ship_mode,
    COUNT(DISTINCT order_id)                                          AS orders,
    COUNT(*)                                                          AS line_items,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1)               AS pct_of_lines
FROM orders
GROUP BY ship_mode
ORDER BY orders DESC;

-- ─────────────────────────────────
-- 8. DISCOUNT ANALYSIS
-- ─────────────────────────────────

-- Discount distribution buckets
SELECT
    CASE
        WHEN discount = 0          THEN 'No discount'
        WHEN discount <= 0.10      THEN '1-10%'
        WHEN discount <= 0.20      THEN '11-20%'
        WHEN discount <= 0.40      THEN '21-40%'
        WHEN discount <= 0.60      THEN '41-60%'
        ELSE                            'Over 60%'
    END AS discount_range,
    COUNT(*)                                                          AS line_items,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1)               AS pct
FROM orders
GROUP BY discount_range
ORDER BY MIN(discount);

-- Line items where the discounted price falls below cost (loss-making sales)
SELECT
    COUNT(*)                                                          AS loss_making_lines,
    ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)          AS revenue_at_loss,
    ROUND(SUM(o.qty * p.cogs), 2)                                    AS cogs_at_loss
FROM orders o
JOIN products p ON o.product_id = p.product_id
WHERE p.unit_price * (1 - o.discount) < p.cogs;

-- ─────────────────────────────────
-- 9. SHIPPING LAG ANALYSIS
-- ─────────────────────────────────

-- Average fulfillment days by ship mode
SELECT
    ship_mode,
    ROUND(AVG(ship_date - order_date), 1)                            AS avg_ship_days,
    MIN(ship_date - order_date)                                       AS min_days,
    MAX(ship_date - order_date)                                       AS max_days
FROM orders
WHERE ship_date IS NOT NULL
GROUP BY ship_mode
ORDER BY avg_ship_days;

-- Orders where ship_date is before order_date (data quality flag)
SELECT COUNT(*) AS bad_ship_dates
FROM orders
WHERE ship_date < order_date;
