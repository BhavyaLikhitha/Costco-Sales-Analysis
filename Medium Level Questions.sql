-- ============================================================
-- Costco Sales Analysis: Medium Level Business Questions
-- ============================================================

-- ─────────────────────────────────
-- Q1. What is the profit margin by product category and sub-category?
-- Which sub-categories are the most and least profitable?
-- ─────────────────────────────────
SELECT
    p.category,
    p.sub_category,
    COUNT(DISTINCT o.order_id)                                                      AS orders,
    ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                        AS revenue,
    ROUND(SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)), 2)             AS profit,
    ROUND(
        SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)) * 100.0
        / NULLIF(SUM(o.qty * p.unit_price * (1 - o.discount)), 0),
    2)                                                                              AS margin_pct
FROM orders o
JOIN products p ON o.product_id = p.product_id
GROUP BY p.category, p.sub_category
ORDER BY margin_pct DESC;

-- ─────────────────────────────────
-- Q2. Who are the top 20 customers by total spend?
-- Include their segment, region, and total profit contribution.
-- ─────────────────────────────────
SELECT
    c.customer_id,
    c.customer_name,
    c.segment,
    c.region,
    c.state,
    COUNT(DISTINCT o.order_id)                                                      AS total_orders,
    ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                        AS total_revenue,
    ROUND(SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)), 2)             AS total_profit
FROM orders o
JOIN products p  ON o.product_id  = p.product_id
JOIN customers c ON o.customer_id = c.customer_id
GROUP BY c.customer_id, c.customer_name, c.segment, c.region, c.state
ORDER BY total_revenue DESC
LIMIT 20;

-- ─────────────────────────────────
-- Q3. What is the monthly revenue trend across all years?
-- Reveals seasonality and the COVID-era impact (2020-2021).
-- ─────────────────────────────────
SELECT
    EXTRACT(YEAR  FROM o.order_date)::INT                                           AS year,
    EXTRACT(MONTH FROM o.order_date)::INT                                           AS month,
    TO_CHAR(o.order_date, 'Mon')                                                    AS month_name,
    COUNT(DISTINCT o.order_id)                                                      AS orders,
    ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                        AS revenue,
    ROUND(SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)), 2)             AS profit
FROM orders o
JOIN products p ON o.product_id = p.product_id
GROUP BY year, month, month_name
ORDER BY year, month;

-- ─────────────────────────────────
-- Q4. What is the revenue and profit by region and customer segment?
-- Reveals which segment drives each region.
-- ─────────────────────────────────
SELECT
    c.region,
    c.segment,
    COUNT(DISTINCT o.order_id)                                                      AS orders,
    ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                        AS revenue,
    ROUND(SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)), 2)             AS profit,
    ROUND(
        SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)) * 100.0
        / NULLIF(SUM(o.qty * p.unit_price * (1 - o.discount)), 0),
    2)                                                                              AS margin_pct
FROM orders o
JOIN products p  ON o.product_id  = p.product_id
JOIN customers c ON o.customer_id = c.customer_id
GROUP BY c.region, c.segment
ORDER BY c.region, revenue DESC;

-- ─────────────────────────────────
-- Q5. Which products are generating losses?
-- Products where the discounted price is below cost of goods.
-- ─────────────────────────────────
SELECT
    p.product_id,
    p.product_name,
    p.category,
    ROUND(AVG(o.discount) * 100, 1)                                                AS avg_discount_pct,
    ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                        AS total_revenue,
    ROUND(SUM(o.qty * p.cogs), 2)                                                  AS total_cogs,
    ROUND(SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)), 2)             AS total_profit,
    COUNT(*)                                                                        AS loss_line_items
FROM orders o
JOIN products p ON o.product_id = p.product_id
WHERE p.unit_price * (1 - o.discount) < p.cogs
GROUP BY p.product_id, p.product_name, p.category
ORDER BY total_profit ASC;

-- ─────────────────────────────────
-- Q6. Which are the top 15 states by revenue?
-- Useful for the USA shape map in the Power BI dashboard.
-- ─────────────────────────────────
SELECT
    c.state,
    c.region,
    COUNT(DISTINCT c.customer_id)                                                   AS unique_customers,
    COUNT(DISTINCT o.order_id)                                                      AS orders,
    ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                        AS revenue,
    ROUND(SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)), 2)             AS profit
FROM orders o
JOIN products p  ON o.product_id  = p.product_id
JOIN customers c ON o.customer_id = c.customer_id
GROUP BY c.state, c.region
ORDER BY revenue DESC
LIMIT 15;

-- ─────────────────────────────────
-- Q7. What is the discount impact on revenue by category?
-- Compares revenue at full list price vs actual (post-discount) revenue.
-- ─────────────────────────────────
SELECT
    p.category,
    ROUND(SUM(o.qty * p.unit_price), 2)                                            AS list_price_revenue,
    ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                        AS actual_revenue,
    ROUND(SUM(o.qty * p.unit_price * o.discount), 2)                               AS discount_given,
    ROUND(
        SUM(o.qty * p.unit_price * o.discount) * 100.0
        / NULLIF(SUM(o.qty * p.unit_price), 0),
    2)                                                                              AS discount_as_pct_of_list
FROM orders o
JOIN products p ON o.product_id = p.product_id
GROUP BY p.category
ORDER BY discount_given DESC;
