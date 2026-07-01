-- ============================================================
-- Costco Sales Analysis: Database Schema (PostgreSQL)
-- Dataset: 793 customers | 1,618 products | ~16,024 order lines | 2020-2024
-- ============================================================

-- Drop in reverse dependency order
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS sales_targets;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;

-- ─────────────────────────────────
-- CUSTOMERS
-- Source: Costco Datasets/customers.csv (793 rows)
-- Country-City is a combined field; split on import into country + city
-- ─────────────────────────────────
CREATE TABLE customers (
    customer_id   VARCHAR(15)  PRIMARY KEY,
    customer_name VARCHAR(100) NOT NULL,
    segment       VARCHAR(20)  NOT NULL,   -- Consumer | Corporate | Home Office
    country       VARCHAR(50),
    city          VARCHAR(100),
    state         VARCHAR(50),
    postal_code   VARCHAR(10),
    region        VARCHAR(20)              -- Central | East | South | West
);

-- ─────────────────────────────────
-- PRODUCTS
-- Source: Costco Datasets/products.csv (1,618 rows)
-- unit_price and cogs are cleaned from '$x.xx ' format on import
-- ─────────────────────────────────
CREATE TABLE products (
    product_id   VARCHAR(15)   PRIMARY KEY,
    product_name VARCHAR(200)  NOT NULL,
    category     VARCHAR(50)   NOT NULL,   -- Electronics | Technology | Furniture | etc.
    sub_category VARCHAR(50),
    unit_price   NUMERIC(10,2) NOT NULL,   -- list price per unit (before discount)
    cogs         NUMERIC(10,2) NOT NULL    -- cost of goods sold per unit
);

-- ─────────────────────────────────
-- ORDERS
-- Source: Costco Datasets/global sales/2020-2024.csv (~16,024 rows combined)
-- Each row = one line item (one product in an order)
-- An order_id appears multiple times when a customer buys multiple products in one order
-- Revenue formula : qty * unit_price * (1 - discount)
-- Profit formula  : qty * (unit_price * (1 - discount) - cogs)
-- ─────────────────────────────────
CREATE TABLE orders (
    order_id    INTEGER       NOT NULL,
    order_date  DATE          NOT NULL,
    ship_date   DATE,
    ship_mode   VARCHAR(30),               -- First Class | Second Class | Standard Class | Same Day
    customer_id VARCHAR(15)   NOT NULL REFERENCES customers(customer_id),
    product_id  VARCHAR(15)   NOT NULL REFERENCES products(product_id),
    qty         INTEGER       NOT NULL DEFAULT 1,
    discount    NUMERIC(4,2)  NOT NULL DEFAULT 0,  -- 0.00–1.00 (e.g. 0.20 = 20% off)
    PRIMARY KEY (order_id, product_id)
);

-- ─────────────────────────────────
-- SALES TARGETS
-- Reference table for Target vs Actual dashboard analysis
-- Populated manually or via upsert_sales_target() procedure
-- ─────────────────────────────────
CREATE TABLE sales_targets (
    target_id      SERIAL        PRIMARY KEY,
    year           SMALLINT      NOT NULL,
    quarter        SMALLINT      NOT NULL CHECK (quarter BETWEEN 1 AND 4),
    region         VARCHAR(20)   NOT NULL,
    category       VARCHAR(50)   NOT NULL,
    target_revenue NUMERIC(12,2) NOT NULL,
    target_profit  NUMERIC(12,2) NOT NULL,
    UNIQUE (year, quarter, region, category)
);

-- ============================================================
-- IMPORT INSTRUCTIONS (run from psql as superuser)
-- Run from the directory containing the Costco Datasets folder.
-- Adjust paths to absolute paths if needed.
-- ============================================================

-- Step 1: Load customers (split combined Country-City column)
/*
CREATE TEMP TABLE customers_stage (
    customer_id   TEXT,
    customer_name TEXT,
    segment       TEXT,
    country_city  TEXT,
    state         TEXT,
    postal_code   TEXT,
    region        TEXT
);

\COPY customers_stage FROM 'Costco Datasets/customers.csv' CSV HEADER;

INSERT INTO customers (customer_id, customer_name, segment, country, city, state, postal_code, region)
SELECT
    TRIM(customer_id),
    TRIM(customer_name),
    TRIM(segment),
    TRIM(SPLIT_PART(country_city, '-', 1)) AS country,
    TRIM(SPLIT_PART(country_city, '-', 2)) AS city,
    TRIM(state),
    TRIM(postal_code),
    TRIM(region)
FROM customers_stage;

DROP TABLE customers_stage;
*/

-- Step 2: Load products (strip $ signs and whitespace from price columns)
/*
CREATE TEMP TABLE products_stage (
    product_id   TEXT,
    product_name TEXT,
    category     TEXT,
    sub_category TEXT,
    unit_price   TEXT,
    cogs         TEXT
);

\COPY products_stage FROM 'Costco Datasets/products.csv' CSV HEADER;

INSERT INTO products (product_id, product_name, category, sub_category, unit_price, cogs)
SELECT
    TRIM(product_id),
    TRIM(product_name),
    TRIM(category),
    TRIM(sub_category),
    REPLACE(TRIM(unit_price), '$', '')::NUMERIC,
    REPLACE(TRIM(cogs), '$', '')::NUMERIC
FROM products_stage;

DROP TABLE products_stage;
*/

-- Step 3: Load all five yearly sales files into one orders table
/*
\COPY orders (order_id, order_date, ship_date, ship_mode, customer_id, product_id, qty, discount)
  FROM 'Costco Datasets/global sales/2020.csv' CSV HEADER;

\COPY orders (order_id, order_date, ship_date, ship_mode, customer_id, product_id, qty, discount)
  FROM 'Costco Datasets/global sales/2021.csv' CSV HEADER;

\COPY orders (order_id, order_date, ship_date, ship_mode, customer_id, product_id, qty, discount)
  FROM 'Costco Datasets/global sales/2022.csv' CSV HEADER;

\COPY orders (order_id, order_date, ship_date, ship_mode, customer_id, product_id, qty, discount)
  FROM 'Costco Datasets/global sales/2023.csv' CSV HEADER;

\COPY orders (order_id, order_date, ship_date, ship_mode, customer_id, product_id, qty, discount)
  FROM 'Costco Datasets/global sales/2024.csv' CSV HEADER;
*/

-- Step 4: Seed sales_targets with sample quarterly benchmarks
-- Targets represent ~10-15% growth expectations over prior year actuals
/*
INSERT INTO sales_targets (year, quarter, region, category, target_revenue, target_profit) VALUES
  (2021, 1, 'East',    'Technology',     50000, 18000),
  (2021, 1, 'West',    'Technology',     42000, 15000),
  (2021, 1, 'Central', 'Technology',     33000, 12000),
  (2021, 1, 'South',   'Technology',     28000,  9000),
  (2022, 1, 'East',    'Electronics',    60000, 20000),
  (2022, 1, 'West',    'Electronics',    52000, 17000),
  (2022, 1, 'Central', 'Electronics',    40000, 13000),
  (2022, 1, 'South',   'Electronics',    34000, 11000),
  (2024, 4, 'West',    'Computers',      95000, 35000),
  (2024, 4, 'East',    'Computers',      88000, 32000);
  -- Extend for all year/quarter/region/category combinations as needed
*/
