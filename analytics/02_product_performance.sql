/*
===============================================================================
Analytics: Product Performance
===============================================================================
Answers: which categories and products drive revenue, and which underperform?

Run:  mysql -u root -p < analytics/02_product_performance.sql
===============================================================================
*/

USE gold;

-- Category contribution to total revenue -----------------------------------
-- Ranking by share rather than absolute value is what makes the concentration
-- of revenue in a few categories visible.
SELECT
    p.category,
    SUM(f.sales_amount) AS total_sales,
    ROUND(100.0 * SUM(f.sales_amount)
          / SUM(SUM(f.sales_amount)) OVER (), 2) AS pct_of_total
FROM gold.fact_sales AS f
JOIN gold.dim_products AS p ON f.product_key = p.product_key
GROUP BY p.category
ORDER BY total_sales DESC;

-- Top 10 products by revenue -----------------------------------------------
SELECT * FROM (
    SELECT p.product_name, p.category, SUM(f.sales_amount) AS total_sales,
           RANK() OVER (ORDER BY SUM(f.sales_amount) DESC) AS revenue_rank
    FROM gold.fact_sales AS f
    JOIN gold.dim_products AS p ON f.product_key = p.product_key
    GROUP BY p.product_name, p.category
) AS ranked
WHERE revenue_rank <= 10
ORDER BY revenue_rank;

-- Bottom 10 products by revenue --------------------------------------------
SELECT * FROM (
    SELECT p.product_name, p.category, SUM(f.sales_amount) AS total_sales,
           RANK() OVER (ORDER BY SUM(f.sales_amount) ASC) AS worst_rank
    FROM gold.fact_sales AS f
    JOIN gold.dim_products AS p ON f.product_key = p.product_key
    GROUP BY p.product_name, p.category
) AS ranked
WHERE worst_rank <= 10
ORDER BY worst_rank;

-- Product performance against its own category average ---------------------
-- Comparing each product to its own category avoids penalising inherently
-- cheap categories, which a flat revenue ranking would do.
SELECT
    p.product_name,
    p.category,
    SUM(f.sales_amount) AS product_sales,
    ROUND(AVG(SUM(f.sales_amount)) OVER (PARTITION BY p.category), 0) AS category_avg,
    CASE
        WHEN SUM(f.sales_amount) > AVG(SUM(f.sales_amount)) OVER (PARTITION BY p.category)
             THEN 'Above Average'
        WHEN SUM(f.sales_amount) < AVG(SUM(f.sales_amount)) OVER (PARTITION BY p.category)
             THEN 'Below Average'
        ELSE 'At Average'
    END AS performance
FROM gold.fact_sales AS f
JOIN gold.dim_products AS p ON f.product_key = p.product_key
GROUP BY p.product_name, p.category
ORDER BY p.category, product_sales DESC;

-- Product segmentation by cost band ----------------------------------------
SELECT cost_band, COUNT(*) AS products
FROM (
    SELECT product_key,
           CASE WHEN cost <  100 THEN 'Below 100'
                WHEN cost <  500 THEN '100-499'
                WHEN cost < 1000 THEN '500-999'
                ELSE '1000 and above'
           END AS cost_band
    FROM gold.dim_products
) AS banded
GROUP BY cost_band
ORDER BY products DESC;
