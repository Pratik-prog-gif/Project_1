/*
===============================================================================
Analytics: Sales Trends
===============================================================================
Answers: how is the business performing over time, and where is growth coming
from? Runs against the gold star schema.

Run:  mysql -u root -p < analytics/01_sales_trends.sql
===============================================================================
*/

USE gold;

-- Headline KPIs ------------------------------------------------------------
SELECT 'Total Sales'      AS measure, FORMAT(SUM(sales_amount), 0) AS value FROM gold.fact_sales
UNION ALL SELECT 'Total Quantity',    FORMAT(SUM(quantity), 0)                FROM gold.fact_sales
UNION ALL SELECT 'Total Orders',      FORMAT(COUNT(DISTINCT order_number), 0) FROM gold.fact_sales
UNION ALL SELECT 'Total Customers',   FORMAT(COUNT(DISTINCT customer_key), 0) FROM gold.fact_sales
UNION ALL SELECT 'Total Products',    FORMAT(COUNT(*), 0)                     FROM gold.dim_products
UNION ALL SELECT 'Average Price',     FORMAT(AVG(price), 2)                   FROM gold.fact_sales;

-- Monthly trend with running total and moving average ----------------------
-- The window functions turn a flat monthly series into a cumulative growth
-- story, which is what a stakeholder actually asks for.
SELECT
    order_year,
    order_month,
    monthly_sales,
    SUM(monthly_sales) OVER (
        PARTITION BY order_year ORDER BY order_month
    ) AS running_total_ytd,
    ROUND(AVG(monthly_sales) OVER (
        ORDER BY order_year, order_month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 0) AS moving_avg_3m
FROM (
    SELECT YEAR(order_date)  AS order_year,
           MONTH(order_date) AS order_month,
           SUM(sales_amount) AS monthly_sales
    FROM gold.fact_sales
    WHERE order_date IS NOT NULL
    GROUP BY YEAR(order_date), MONTH(order_date)
) AS m
ORDER BY order_year, order_month;

-- Year-over-year performance -----------------------------------------------
SELECT
    order_year,
    yearly_sales,
    LAG(yearly_sales) OVER (ORDER BY order_year) AS prev_year_sales,
    yearly_sales - LAG(yearly_sales) OVER (ORDER BY order_year) AS yoy_change,
    CASE WHEN LAG(yearly_sales) OVER (ORDER BY order_year) IS NULL THEN NULL
         ELSE ROUND(100.0 * (yearly_sales - LAG(yearly_sales) OVER (ORDER BY order_year))
                    / LAG(yearly_sales) OVER (ORDER BY order_year), 1)
    END AS yoy_pct
FROM (
    SELECT YEAR(order_date) AS order_year, SUM(sales_amount) AS yearly_sales
    FROM gold.fact_sales
    WHERE order_date IS NOT NULL
    GROUP BY YEAR(order_date)
) AS y
ORDER BY order_year;

-- Sales by country ---------------------------------------------------------
SELECT c.country,
       SUM(f.sales_amount)            AS total_sales,
       COUNT(DISTINCT f.customer_key) AS customers,
       ROUND(SUM(f.sales_amount) / COUNT(DISTINCT f.customer_key), 0) AS sales_per_customer
FROM gold.fact_sales AS f
JOIN gold.dim_customers AS c ON f.customer_key = c.customer_key
GROUP BY c.country
ORDER BY total_sales DESC;
