-- ============================================================
-- Costco Sales Analysis: Easy Level Business Questions
-- ============================================================
-- Revenue formula : qty * unit_price * (1 - discount)
-- Profit formula  : qty * (unit_price * (1 - discount) - cogs)
-- Margin formula  : Profit / Revenue * 100

-- ─────────────────────────────────
-- Q1. What are the overall sales KPIs?
-- Total revenue, total profit, units sold, and profit margin across all years.
-- ─────────────────────────────────
SELECT
    ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                        AS total_revenue,
    ROUND(SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)), 2)             AS total_profit,
    SUM(o.qty)                                                                      AS total_qty_sold,
    COUNT(DISTINCT o.order_id)                                                      AS total_orders,
    ROUND(
        SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)) * 100.0
        / NULLIF(SUM(o.qty * p.unit_price * (1 - o.discount)), 0),
    2)                                                                              AS profit_margin_pct
FROM orders o
JOIN products p ON o.product_id = p.product_id;

-- ─────────────────────────────────
-- Q2. What is the revenue and profit by region?
-- ─────────────────────────────────
SELECT
    c.region,
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
GROUP BY c.region
ORDER BY revenue DESC;

-- ─────────────────────────────────
-- Q3. What is the revenue and profit by customer segment?
-- ─────────────────────────────────
SELECT
    c.segment,
    COUNT(DISTINCT c.customer_id)                                                   AS unique_customers,
    COUNT(DISTINCT o.order_id)                                                      AS total_orders,
    ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                        AS revenue,
    ROUND(SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)), 2)             AS profit
FROM orders o
JOIN products p  ON o.product_id  = p.product_id
JOIN customers c ON o.customer_id = c.customer_id
GROUP BY c.segment
ORDER BY revenue DESC;

-- ─────────────────────────────────
-- Q4. What are the top 10 best-selling products by revenue?
-- ─────────────────────────────────
SELECT
    p.product_id,
    p.product_name,
    p.category,
    p.sub_category,
    SUM(o.qty)                                                                      AS total_qty_sold,
    ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                        AS revenue,
    ROUND(SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)), 2)             AS profit
FROM orders o
JOIN products p ON o.product_id = p.product_id
GROUP BY p.product_id, p.product_name, p.category, p.sub_category
ORDER BY revenue DESC
LIMIT 10;

-- ─────────────────────────────────
-- Q5. What is the revenue and profit by product category?
-- ─────────────────────────────────
SELECT
    p.category,
    COUNT(DISTINCT p.product_id)                                                    AS products_listed,
    COUNT(DISTINCT o.order_id)                                                      AS orders,
    SUM(o.qty)                                                                      AS qty_sold,
    ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                        AS revenue,
    ROUND(SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)), 2)             AS profit,
    ROUND(
        SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)) * 100.0
        / NULLIF(SUM(o.qty * p.unit_price * (1 - o.discount)), 0),
    2)                                                                              AS margin_pct
FROM orders o
JOIN products p ON o.product_id = p.product_id
GROUP BY p.category
ORDER BY revenue DESC;

-- ─────────────────────────────────
-- Q6. How are orders distributed across ship modes?
-- Includes average fulfillment time per mode.
-- ─────────────────────────────────
SELECT
    o.ship_mode,
    COUNT(DISTINCT o.order_id)                                                      AS total_orders,
    ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                        AS revenue,
    ROUND(AVG(o.ship_date - o.order_date), 1)                                      AS avg_ship_days
FROM orders o
JOIN products p ON o.product_id = p.product_id
WHERE o.ship_date IS NOT NULL
GROUP BY o.ship_mode
ORDER BY total_orders DESC;

-- ─────────────────────────────────
-- Q7. What is the annual sales performance from 2020 to 2024?
-- ─────────────────────────────────
SELECT
    EXTRACT(YEAR FROM o.order_date)::INT                                            AS year,
    COUNT(DISTINCT o.order_id)                                                      AS orders,
    COUNT(DISTINCT o.customer_id)                                                   AS active_customers,
    SUM(o.qty)                                                                      AS qty_sold,
    ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                        AS revenue,
    ROUND(SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)), 2)             AS profit
FROM orders o
JOIN products p ON o.product_id = p.product_id
GROUP BY year
ORDER BY year;
