-- 1. STAR SCHEMA SETUP
DROP TABLE IF EXISTS fact_sales;
DROP TABLE IF EXISTS dim_customer;
DROP TABLE IF EXISTS dim_product;
DROP TABLE IF EXISTS dim_date;

CREATE TABLE dim_date (
    date_id DATE PRIMARY KEY,
    year INT NOT NULL,
    month INT NOT NULL,
    month_name VARCHAR(20) NOT NULL,
    quarter INT NOT NULL
);

CREATE TABLE dim_product (
    product_id SERIAL PRIMARY KEY,
    product_name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL,
    unit_price DECIMAL(10, 2) NOT NULL
);

CREATE TABLE dim_customer (
    customer_id SERIAL PRIMARY KEY,
    customer_name VARCHAR(100) NOT NULL,
    region VARCHAR(50) NOT NULL
);

CREATE TABLE fact_sales (
    sale_id SERIAL PRIMARY KEY,
    date_id DATE REFERENCES dim_date(date_id),
    product_id INT REFERENCES dim_product(product_id),
    customer_id INT REFERENCES dim_customer(customer_id),
    quantity INT NOT NULL,
    total_amount DECIMAL(12, 2) NOT NULL
);

-- 2. SAMPLE DATA INSERTION
INSERT INTO dim_date (date_id, year, month, month_name, quarter) VALUES
('2026-01-15', 2026, 1, 'January', 1),
('2026-02-15', 2026, 2, 'February', 1),
('2026-03-15', 2026, 3, 'March', 1);

INSERT INTO dim_product (product_name, category, unit_price) VALUES
('Laptop', 'Electronics', 1200.00),
('Mouse', 'Electronics', 25.00),
('Desk Chair', 'Furniture', 150.00);

INSERT INTO dim_customer (customer_name, region) VALUES
('Alice Smith', 'North'),
('Bob Jones', 'East'),
('Charlie Brown', 'West');

INSERT INTO fact_sales (date_id, product_id, customer_id, quantity, total_amount) VALUES
('2026-01-15', 1, 1, 1, 1200.00),
('2026-01-20', 2, 2, 4, 100.00),
('2026-02-10', 3, 3, 2, 300.00),
('2026-02-18', 1, 2, 2, 2400.00),
('2026-03-05', 2, 1, 10, 250.00),
('2026-03-12', 3, 1, 1, 150.00);

-- 3. WINDOW FUNCTION RANKINGS
SELECT 
    p.category,
    p.product_name,
    SUM(f.total_amount) AS total_revenue,
    RANK() OVER (PARTITION BY p.category ORDER BY SUM(f.total_amount) DESC) AS revenue_rank,
    DENSE_RANK() OVER (PARTITION BY p.category ORDER BY SUM(f.total_amount) DESC) AS revenue_dense_rank
FROM fact_sales f
JOIN dim_product p ON f.product_id = p.product_id
GROUP BY p.category, p.product_name;

-- 4. MONTH-OVER-MONTH (MoM) REPORT USING CTES
WITH monthly_sales AS (
    SELECT 
        d.year,
        d.month,
        d.month_name,
        SUM(f.total_amount) AS current_month_revenue
    FROM fact_sales f
    JOIN dim_date d ON f.date_id = d.date_id
    GROUP BY d.year, d.month, d.month_name
)
SELECT 
    year,
    month_name,
    current_month_revenue,
    LAG(current_month_revenue, 1) OVER (ORDER BY year, month) AS previous_month_revenue,
    ROUND(
        (current_month_revenue - LAG(current_month_revenue, 1) OVER (ORDER BY year, month)) 
        / NULLIF(LAG(current_month_revenue, 1) OVER (ORDER BY year, month), 0) * 100, 2
    ) AS mom_growth_percentage
FROM monthly_sales;

-- 5. ROLLUP AGGREGATIONS
SELECT 
    COALESCE(p.category, 'All Categories') AS category,
    COALESCE(c.region, 'All Regions') AS region,
    SUM(f.total_amount) AS total_sales
FROM fact_sales f
JOIN dim_product p ON f.product_id = p.product_id
JOIN dim_customer c ON f.customer_id = c.customer_id
GROUP BY ROLLUP(p.category, c.region)
ORDER BY p.category, c.region;

-- 6. EXPLAIN OPTIMIZATION & INDEXES
CREATE INDEX idx_fact_sales_date ON fact_sales(date_id);
CREATE INDEX idx_fact_sales_product ON fact_sales(product_id);
CREATE INDEX idx_fact_sales_customer ON fact_sales(customer_id);

EXPLAIN ANALYZE
SELECT 
    c.region,
    p.category,
    SUM(f.total_amount) AS total_revenue
FROM fact_sales f
JOIN dim_customer c ON f.customer_id = c.customer_id
JOIN dim_product p ON f.product_id = p.product_id
GROUP BY c.region, p.category;