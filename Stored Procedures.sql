-- ============================================================
-- Costco Sales Analysis: Stored Procedures & Functions (PostgreSQL PL/pgSQL)
-- ============================================================

-- ─────────────────────────────────
-- FUNCTION 1: generate_quarterly_report
-- Returns a region-level sales report for a given quarter,
-- comparing current performance to the same quarter the prior year.
--
-- Usage: SELECT * FROM generate_quarterly_report(2024, 3);
-- ─────────────────────────────────
CREATE OR REPLACE FUNCTION generate_quarterly_report(
    p_year    INT,
    p_quarter INT
)
RETURNS TABLE (
    region           TEXT,
    cur_revenue      NUMERIC,
    cur_profit       NUMERIC,
    cur_orders       BIGINT,
    py_revenue       NUMERIC,
    py_profit        NUMERIC,
    yoy_revenue_pct  NUMERIC,
    yoy_profit_pct   NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_start  DATE;
    v_end    DATE;
    v_py_start DATE;
    v_py_end   DATE;
BEGIN
    v_start    := DATE_TRUNC('quarter',
                    MAKE_DATE(p_year, (p_quarter - 1) * 3 + 1, 1))::DATE;
    v_end      := (v_start + INTERVAL '3 months' - INTERVAL '1 day')::DATE;
    v_py_start := (v_start    - INTERVAL '1 year')::DATE;
    v_py_end   := (v_end      - INTERVAL '1 year')::DATE;

    RETURN QUERY
    WITH cur AS (
        SELECT
            c.region                                                                AS rgn,
            ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)               AS rev,
            ROUND(SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)), 2)    AS prof,
            COUNT(DISTINCT o.order_id)::BIGINT                                    AS ord_cnt
        FROM orders o
        JOIN products p  ON o.product_id  = p.product_id
        JOIN customers c ON o.customer_id = c.customer_id
        WHERE o.order_date BETWEEN v_start AND v_end
        GROUP BY c.region
    ),
    py AS (
        SELECT
            c.region                                                                AS rgn,
            ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)               AS rev,
            ROUND(SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)), 2)    AS prof
        FROM orders o
        JOIN products p  ON o.product_id  = p.product_id
        JOIN customers c ON o.customer_id = c.customer_id
        WHERE o.order_date BETWEEN v_py_start AND v_py_end
        GROUP BY c.region
    )
    SELECT
        cur.rgn,
        cur.rev,
        cur.prof,
        cur.ord_cnt,
        COALESCE(py.rev,  0),
        COALESCE(py.prof, 0),
        ROUND((cur.rev  - COALESCE(py.rev,  0)) * 100.0
              / NULLIF(COALESCE(py.rev,  0), 0), 2),
        ROUND((cur.prof - COALESCE(py.prof, 0)) * 100.0
              / NULLIF(COALESCE(py.prof, 0), 0), 2)
    FROM cur
    LEFT JOIN py ON cur.rgn = py.rgn
    ORDER BY cur.rev DESC;
END;
$$;

-- ─────────────────────────────────
-- PROCEDURE 2: upsert_sales_target
-- Inserts or updates a single sales target record.
-- Keeps the sales_targets table current without duplicates.
--
-- Usage: CALL upsert_sales_target(2025, 1, 'West', 'Electronics', 120000, 45000);
-- ─────────────────────────────────
CREATE OR REPLACE PROCEDURE upsert_sales_target(
    p_year           INT,
    p_quarter        INT,
    p_region         VARCHAR(20),
    p_category       VARCHAR(50),
    p_target_revenue NUMERIC,
    p_target_profit  NUMERIC
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_quarter NOT BETWEEN 1 AND 4 THEN
        RAISE EXCEPTION 'Quarter must be between 1 and 4, got: %', p_quarter;
    END IF;

    INSERT INTO sales_targets (year, quarter, region, category, target_revenue, target_profit)
    VALUES (p_year, p_quarter, p_region, p_category, p_target_revenue, p_target_profit)
    ON CONFLICT (year, quarter, region, category)
    DO UPDATE SET
        target_revenue = EXCLUDED.target_revenue,
        target_profit  = EXCLUDED.target_profit;

    RAISE NOTICE 'Target upserted: Q% % | % | % → Revenue: $%, Profit: $%',
        p_quarter, p_year, p_region, p_category,
        p_target_revenue, p_target_profit;
END;
$$;

-- ─────────────────────────────────
-- FUNCTION 3: get_customer_profile
-- Returns a single-row summary of a customer's full purchase history.
-- Useful for customer service lookups and account reviews.
--
-- Usage: SELECT * FROM get_customer_profile('CUST-1');
-- ─────────────────────────────────
CREATE OR REPLACE FUNCTION get_customer_profile(
    p_customer_id VARCHAR(15)
)
RETURNS TABLE (
    customer_name    TEXT,
    segment          TEXT,
    region           TEXT,
    state            TEXT,
    total_orders     BIGINT,
    total_qty        BIGINT,
    total_revenue    NUMERIC,
    total_profit     NUMERIC,
    first_purchase   DATE,
    last_purchase    DATE,
    years_active     BIGINT,
    favorite_category TEXT,
    top_product      TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM customers WHERE customer_id = p_customer_id) THEN
        RAISE EXCEPTION 'Customer % not found.', p_customer_id;
    END IF;

    RETURN QUERY
    WITH purchase_stats AS (
        SELECT
            COUNT(DISTINCT o.order_id)::BIGINT                                     AS ord_cnt,
            SUM(o.qty)::BIGINT                                                     AS qty_total,
            ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)               AS rev,
            ROUND(SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)), 2)    AS prof,
            MIN(o.order_date)                                                      AS first_ord,
            MAX(o.order_date)                                                      AS last_ord,
            COUNT(DISTINCT EXTRACT(YEAR FROM o.order_date))::BIGINT               AS yr_active
        FROM orders o
        JOIN products p ON o.product_id = p.product_id
        WHERE o.customer_id = p_customer_id
    ),
    fav_category AS (
        SELECT p.category
        FROM orders o
        JOIN products p ON o.product_id = p.product_id
        WHERE o.customer_id = p_customer_id
        GROUP BY p.category
        ORDER BY SUM(o.qty * p.unit_price * (1 - o.discount)) DESC
        LIMIT 1
    ),
    top_prod AS (
        SELECT p.product_name
        FROM orders o
        JOIN products p ON o.product_id = p.product_id
        WHERE o.customer_id = p_customer_id
        GROUP BY p.product_name
        ORDER BY SUM(o.qty * p.unit_price * (1 - o.discount)) DESC
        LIMIT 1
    )
    SELECT
        c.customer_name::TEXT,
        c.segment::TEXT,
        c.region::TEXT,
        c.state::TEXT,
        ps.ord_cnt,
        ps.qty_total,
        ps.rev,
        ps.prof,
        ps.first_ord,
        ps.last_ord,
        ps.yr_active,
        fc.category::TEXT,
        tp.product_name::TEXT
    FROM customers c
    CROSS JOIN purchase_stats ps
    CROSS JOIN fav_category   fc
    CROSS JOIN top_prod       tp
    WHERE c.customer_id = p_customer_id;
END;
$$;

-- ─────────────────────────────────
-- FUNCTION 4: flag_low_margin_products
-- Returns all products whose realized profit margin falls below
-- the given threshold. Used for pricing and discount policy reviews.
--
-- Usage: SELECT * FROM flag_low_margin_products(20.0);
--        SELECT * FROM flag_low_margin_products(10.0);  -- stricter threshold
-- ─────────────────────────────────
CREATE OR REPLACE FUNCTION flag_low_margin_products(
    p_min_margin_pct NUMERIC DEFAULT 20.0
)
RETURNS TABLE (
    product_id       TEXT,
    product_name     TEXT,
    category         TEXT,
    sub_category     TEXT,
    avg_discount_pct NUMERIC,
    revenue          NUMERIC,
    profit           NUMERIC,
    margin_pct       NUMERIC,
    total_line_items BIGINT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.product_id::TEXT,
        p.product_name::TEXT,
        p.category::TEXT,
        p.sub_category::TEXT,
        ROUND(AVG(o.discount) * 100, 1)                                            AS avg_disc,
        ROUND(SUM(o.qty * p.unit_price * (1 - o.discount)), 2)                    AS rev,
        ROUND(SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)), 2)         AS prof,
        ROUND(
            SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)) * 100.0
            / NULLIF(SUM(o.qty * p.unit_price * (1 - o.discount)), 0),
        2)                                                                          AS marg,
        COUNT(*)::BIGINT                                                            AS lines
    FROM orders o
    JOIN products p ON o.product_id = p.product_id
    GROUP BY p.product_id, p.product_name, p.category, p.sub_category
    HAVING
        SUM(o.qty * (p.unit_price * (1 - o.discount) - p.cogs)) * 100.0
        / NULLIF(SUM(o.qty * p.unit_price * (1 - o.discount)), 0) < p_min_margin_pct
    ORDER BY marg ASC;
END;
$$;
