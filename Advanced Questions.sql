-- ============================================================
-- Costco Sales Analysis: Advanced Level Business Questions
-- Uses: Window Functions (LAG, RANK, SUM OVER), CTEs, NTILE
-- ============================================================

-- ─────────────────────────────────
-- Q1. Year-over-year revenue growth rate by region.
-- Uses LAG() to compare each year against the prior year per region.
-- ─────────────────────────────────
WITH yearly_revenue AS (
    SELECT
        c.region,
        EXTRACT(YEAR FROM o.order_date)::INT                                        AS year,
        ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                    AS revenue,
        ROUND(SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)), 2)         AS profit
    FROM orders o
    JOIN products p  ON o.product_id  = p.product_id
    JOIN customers c ON o.customer_id = c.customer_id
    GROUP BY c.region, year
)
SELECT
    region,
    year,
    revenue,
    LAG(revenue) OVER (PARTITION BY region ORDER BY year)                           AS prev_year_revenue,
    ROUND(
        (revenue - LAG(revenue) OVER (PARTITION BY region ORDER BY year)) * 100.0
        / NULLIF(LAG(revenue) OVER (PARTITION BY region ORDER BY year), 0),
    2)                                                                              AS yoy_growth_pct
FROM yearly_revenue
ORDER BY region, year;

-- ─────────────────────────────────
-- Q2. Cumulative (running total) revenue by month across all years.
-- Shows the overall business growth trajectory.
-- ─────────────────────────────────
WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC('month', o.order_date)::DATE                                     AS month,
        ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                    AS monthly_revenue
    FROM orders o
    JOIN products p ON o.product_id = p.product_id
    GROUP BY month
)
SELECT
    month,
    monthly_revenue,
    ROUND(SUM(monthly_revenue) OVER (ORDER BY month
                                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2) AS cumulative_revenue
FROM monthly_revenue
ORDER BY month;

-- ─────────────────────────────────
-- Q3. 3-month rolling average revenue.
-- Smooths out monthly spikes; ideal for the trend line in Power BI.
-- ─────────────────────────────────
WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC('month', o.order_date)::DATE                                     AS month,
        ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                    AS monthly_revenue
    FROM orders o
    JOIN products p ON o.product_id = p.product_id
    GROUP BY month
)
SELECT
    month,
    monthly_revenue,
    ROUND(AVG(monthly_revenue) OVER (
        ORDER BY month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2)                                                                           AS rolling_3mo_avg
FROM monthly_revenue
ORDER BY month;

-- ─────────────────────────────────
-- Q4. Revenue rank of every product within its category.
-- Full competitive ranking using DENSE_RANK partitioned by category.
-- ─────────────────────────────────
WITH product_metrics AS (
    SELECT
        p.category,
        p.product_id,
        p.product_name,
        SUM(o.qty)                                                                  AS qty_sold,
        ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                    AS revenue,
        ROUND(SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)), 2)         AS profit
    FROM orders o
    JOIN products p ON o.product_id = p.product_id
    GROUP BY p.category, p.product_id, p.product_name
)
SELECT
    category,
    DENSE_RANK() OVER (PARTITION BY category ORDER BY revenue DESC)                 AS revenue_rank,
    product_id,
    product_name,
    qty_sold,
    revenue,
    profit
FROM product_metrics
ORDER BY category, revenue_rank;

-- ─────────────────────────────────
-- Q5. Customer RFM segmentation (Recency, Frequency, Monetary).
-- Groups customers into behavior-based tiers using NTILE quintiles.
-- ─────────────────────────────────
WITH customer_metrics AS (
    SELECT
        o.customer_id,
        MAX(o.order_date)                                                           AS last_order_date,
        COUNT(DISTINCT o.order_id)                                                  AS frequency,
        ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                    AS monetary
    FROM orders o
    JOIN products p ON o.product_id = p.product_id
    GROUP BY o.customer_id
),
rfm_scored AS (
    SELECT *,
        CURRENT_DATE - last_order_date                                              AS recency_days,
        NTILE(5) OVER (ORDER BY CURRENT_DATE - last_order_date ASC)                AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC)                                     AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC)                                      AS m_score
    FROM customer_metrics
)
SELECT
    c.customer_id,
    c.customer_name,
    c.segment,
    c.region,
    rfm.recency_days,
    rfm.frequency,
    rfm.monetary,
    rfm.r_score,
    rfm.f_score,
    rfm.m_score,
    rfm.r_score + rfm.f_score + rfm.m_score                                        AS rfm_total,
    CASE
        WHEN rfm.r_score >= 4 AND rfm.f_score >= 4 AND rfm.m_score >= 4            THEN 'Champions'
        WHEN rfm.r_score >= 3 AND rfm.f_score >= 3                                 THEN 'Loyal Customers'
        WHEN rfm.r_score >= 4 AND rfm.f_score <= 2                                 THEN 'Recent Customers'
        WHEN rfm.r_score <= 2 AND rfm.m_score >= 4                                 THEN 'Big Spenders at Risk'
        WHEN rfm.r_score <= 2 AND rfm.f_score <= 2                                 THEN 'Lost Customers'
        ELSE                                                                              'Potential Loyalists'
    END                                                                             AS rfm_segment
FROM rfm_scored rfm
JOIN customers c ON rfm.customer_id = c.customer_id
ORDER BY rfm_total DESC;

-- ─────────────────────────────────
-- Q6. Cohort analysis: revenue and retention by first-purchase year.
-- Shows how each year's new customers performed in subsequent years.
-- ─────────────────────────────────
WITH first_purchase AS (
    SELECT customer_id,
           EXTRACT(YEAR FROM MIN(order_date))::INT                                  AS cohort_year
    FROM orders
    GROUP BY customer_id
),
cohort_data AS (
    SELECT
        fp.cohort_year,
        EXTRACT(YEAR FROM o.order_date)::INT                                        AS order_year,
        COUNT(DISTINCT o.customer_id)                                               AS active_customers,
        ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                    AS revenue
    FROM orders o
    JOIN products p       ON o.product_id  = p.product_id
    JOIN first_purchase fp ON o.customer_id = fp.customer_id
    GROUP BY fp.cohort_year, order_year
)
SELECT
    cohort_year,
    order_year,
    order_year - cohort_year                                                        AS years_since_first_purchase,
    active_customers,
    revenue
FROM cohort_data
ORDER BY cohort_year, order_year;

-- ─────────────────────────────────
-- Q7. Target vs Actual revenue performance by region and quarter.
-- Compares actual results against the benchmarks in sales_targets.
-- ─────────────────────────────────
WITH actuals AS (
    SELECT
        EXTRACT(YEAR    FROM o.order_date)::INT                                     AS year,
        EXTRACT(QUARTER FROM o.order_date)::INT                                     AS quarter,
        c.region,
        p.category,
        ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                    AS actual_revenue,
        ROUND(SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)), 2)         AS actual_profit
    FROM orders o
    JOIN products p  ON o.product_id  = p.product_id
    JOIN customers c ON o.customer_id = c.customer_id
    GROUP BY year, quarter, c.region, p.category
)
SELECT
    a.year,
    a.quarter,
    a.region,
    a.category,
    a.actual_revenue,
    t.target_revenue,
    ROUND(a.actual_revenue  - t.target_revenue, 2)                                 AS revenue_gap,
    ROUND((a.actual_revenue - t.target_revenue) * 100.0
          / NULLIF(t.target_revenue, 0), 2)                                         AS pct_vs_target,
    a.actual_profit,
    t.target_profit,
    ROUND(a.actual_profit - t.target_profit, 2)                                    AS profit_gap
FROM actuals a
JOIN sales_targets t
    ON  a.year     = t.year
    AND a.quarter  = t.quarter
    AND a.region   = t.region
    AND a.category = t.category
ORDER BY a.year, a.quarter, a.region;

-- ─────────────────────────────────
-- Q8. COVID impact analysis: pandemic era vs post-pandemic.
-- Splits the 5-year window into two eras for comparison.
-- ─────────────────────────────────
SELECT
    CASE
        WHEN EXTRACT(YEAR FROM o.order_date) IN (2020, 2021) THEN 'Pandemic (2020-2021)'
        ELSE 'Post-Pandemic (2022-2024)'
    END                                                                             AS era,
    c.region,
    p.category,
    COUNT(DISTINCT o.customer_id)                                                   AS unique_customers,
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
GROUP BY era, c.region, p.category
ORDER BY era DESC, revenue DESC;

-- ─────────────────────────────────
-- Q9. Customer lifetime value (CLV) ranking.
-- Projects 3-year future value based on average annual spend.
-- ─────────────────────────────────
WITH customer_yearly AS (
    SELECT
        o.customer_id,
        EXTRACT(YEAR FROM o.order_date)::INT                                        AS year,
        ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                    AS yearly_revenue
    FROM orders o
    JOIN products p ON o.product_id = p.product_id
    GROUP BY o.customer_id, year
)
SELECT
    c.customer_id,
    c.customer_name,
    c.segment,
    c.region,
    COUNT(DISTINCT cy.year)                                                         AS years_active,
    ROUND(SUM(cy.yearly_revenue), 2)                                                AS lifetime_revenue,
    ROUND(AVG(cy.yearly_revenue), 2)                                                AS avg_annual_revenue,
    ROUND(AVG(cy.yearly_revenue) * 3, 2)                                            AS projected_3yr_clv,
    RANK() OVER (ORDER BY SUM(cy.yearly_revenue) DESC)                             AS clv_rank
FROM customer_yearly cy
JOIN customers c ON cy.customer_id = c.customer_id
GROUP BY c.customer_id, c.customer_name, c.segment, c.region
ORDER BY lifetime_revenue DESC
LIMIT 30;

-- ─────────────────────────────────
-- Q10. Seasonal revenue heatmap by quarter across all years.
-- Pivots revenue into a quarter × year matrix to surface patterns.
-- ─────────────────────────────────
SELECT
    EXTRACT(QUARTER FROM o.order_date)::INT                                         AS quarter,
    ROUND(SUM(CASE WHEN EXTRACT(YEAR FROM o.order_date) = 2020
                   THEN o.qty * p.unit_price * (1 - o.discount) END), 2)           AS rev_2020,
    ROUND(SUM(CASE WHEN EXTRACT(YEAR FROM o.order_date) = 2021
                   THEN o.qty * p.unit_price * (1 - o.discount) END), 2)           AS rev_2021,
    ROUND(SUM(CASE WHEN EXTRACT(YEAR FROM o.order_date) = 2022
                   THEN o.qty * p.unit_price * (1 - o.discount) END), 2)           AS rev_2022,
    ROUND(SUM(CASE WHEN EXTRACT(YEAR FROM o.order_date) = 2023
                   THEN o.qty * p.unit_price * (1 - o.discount) END), 2)           AS rev_2023,
    ROUND(SUM(CASE WHEN EXTRACT(YEAR FROM o.order_date) = 2024
                   THEN o.qty * p.unit_price * (1 - o.discount) END), 2)           AS rev_2024
FROM orders o
JOIN products p ON o.product_id = p.product_id
GROUP BY quarter
ORDER BY quarter;
