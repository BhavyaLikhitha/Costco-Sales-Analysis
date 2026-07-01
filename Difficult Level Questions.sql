-- ============================================================
-- Costco Sales Analysis: Difficult Level Business Questions
-- ============================================================

-- ─────────────────────────────────
-- Q1. Quarter-over-quarter revenue comparison for each year.
-- Which quarter is consistently the strongest?
-- ─────────────────────────────────
SELECT
    EXTRACT(YEAR    FROM o.order_date)::INT                                         AS year,
    EXTRACT(QUARTER FROM o.order_date)::INT                                         AS quarter,
    COUNT(DISTINCT o.order_id)                                                      AS orders,
    ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                        AS revenue,
    ROUND(SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)), 2)             AS profit,
    ROUND(
        SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)) * 100.0
        / NULLIF(SUM(o.qty * p.unit_price * (1 - o.discount)), 0),
    2)                                                                              AS margin_pct
FROM orders o
JOIN products p ON o.product_id = p.product_id
GROUP BY year, quarter
ORDER BY year, quarter;

-- ─────────────────────────────────
-- Q2. Which customers have purchased in at least 3 different years?
-- These are the high-loyalty, multi-year customers worth retaining.
-- ─────────────────────────────────
SELECT
    c.customer_id,
    c.customer_name,
    c.segment,
    c.region,
    COUNT(DISTINCT EXTRACT(YEAR FROM o.order_date)::INT)                            AS years_active,
    MIN(o.order_date)                                                               AS first_purchase,
    MAX(o.order_date)                                                               AS last_purchase,
    COUNT(DISTINCT o.order_id)                                                      AS total_orders,
    ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                        AS lifetime_revenue
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN products p  ON o.product_id  = p.product_id
GROUP BY c.customer_id, c.customer_name, c.segment, c.region
HAVING COUNT(DISTINCT EXTRACT(YEAR FROM o.order_date)::INT) >= 3
ORDER BY lifetime_revenue DESC;

-- ─────────────────────────────────
-- Q3. Which is the top product by revenue in each category?
-- Uses RANK() partitioned by category.
-- ─────────────────────────────────
WITH product_revenue AS (
    SELECT
        p.category,
        p.product_id,
        p.product_name,
        ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                    AS revenue,
        ROUND(SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)), 2)         AS profit
    FROM orders o
    JOIN products p ON o.product_id = p.product_id
    GROUP BY p.category, p.product_id, p.product_name
),
ranked AS (
    SELECT *,
           RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS revenue_rank
    FROM product_revenue
)
SELECT category, revenue_rank, product_id, product_name, revenue, profit
FROM ranked
WHERE revenue_rank <= 3
ORDER BY category, revenue_rank;

-- ─────────────────────────────────
-- Q4. Revenue at risk: how much revenue is lost to discounts above 40%?
-- Quantifies the cost of aggressive discounting by category.
-- ─────────────────────────────────
SELECT
    p.category,
    COUNT(*)                                                                        AS high_discount_lines,
    ROUND(SUM(o.qty * p.unit_price), 2)                                            AS list_revenue,
    ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                        AS actual_revenue,
    ROUND(SUM(o.qty * p.unit_price * o.discount), 2)                               AS revenue_lost,
    ROUND(AVG(o.discount) * 100, 1)                                                AS avg_discount_pct
FROM orders o
JOIN products p ON o.product_id = p.product_id
WHERE o.discount > 0.40
GROUP BY p.category
ORDER BY revenue_lost DESC;

-- ─────────────────────────────────
-- Q5. Which segment-region combination has the best and worst profit margin?
-- Highlights where to focus growth vs where to cut costs.
-- ─────────────────────────────────
WITH segment_region AS (
    SELECT
        c.segment,
        c.region,
        ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                    AS revenue,
        ROUND(SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)), 2)         AS profit
    FROM orders o
    JOIN products p  ON o.product_id  = p.product_id
    JOIN customers c ON o.customer_id = c.customer_id
    GROUP BY c.segment, c.region
)
SELECT
    segment,
    region,
    revenue,
    profit,
    ROUND(profit * 100.0 / NULLIF(revenue, 0), 2)                                  AS margin_pct,
    RANK() OVER (ORDER BY profit * 100.0 / NULLIF(revenue, 0) DESC)                AS margin_rank
FROM segment_region
ORDER BY margin_pct DESC;

-- ─────────────────────────────────
-- Q6. Pareto analysis: which products drive 80% of total revenue?
-- Identifies the vital few vs the trivial many.
-- ─────────────────────────────────
WITH product_rev AS (
    SELECT
        p.product_id,
        p.product_name,
        p.category,
        ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                    AS revenue
    FROM orders o
    JOIN products p ON o.product_id = p.product_id
    GROUP BY p.product_id, p.product_name, p.category
),
cumulative AS (
    SELECT *,
        ROW_NUMBER() OVER (ORDER BY revenue DESC)                                   AS rn,
        SUM(revenue) OVER ()                                                        AS total_revenue,
        SUM(revenue) OVER (ORDER BY revenue DESC
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)        AS cumulative_revenue
    FROM product_rev
)
SELECT
    rn,
    product_id,
    product_name,
    category,
    revenue,
    ROUND(cumulative_revenue * 100.0 / total_revenue, 1)                            AS cumulative_pct
FROM cumulative
WHERE cumulative_revenue - revenue < total_revenue * 0.80
ORDER BY rn;

-- ─────────────────────────────────
-- Q7. Which products are frequently ordered together?
-- Self-join on order_id to find co-occurring product pairs.
-- ─────────────────────────────────
SELECT
    a.product_id                                                                    AS product_a_id,
    pa.product_name                                                                 AS product_a_name,
    b.product_id                                                                    AS product_b_id,
    pb.product_name                                                                 AS product_b_name,
    COUNT(*)                                                                        AS co_occurrence_count
FROM orders a
JOIN orders b    ON  a.order_id = b.order_id
                AND a.product_id < b.product_id   -- avoid duplicates and self-pairs
JOIN products pa ON a.product_id = pa.product_id
JOIN products pb ON b.product_id = pb.product_id
GROUP BY a.product_id, pa.product_name, b.product_id, pb.product_name
HAVING COUNT(*) > 2
ORDER BY co_occurrence_count DESC
LIMIT 20;
