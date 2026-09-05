/*
===============================================================================
Analytics: Customer Behaviour
===============================================================================
Answers: who are the customers, how do they segment, and what are they worth?

Run:  mysql -u root -p < analytics/03_customer_behaviour.sql
===============================================================================
*/

USE gold;

-- Demographic spread --------------------------------------------------------
SELECT gender, marital_status, COUNT(*) AS customers
FROM gold.dim_customers
GROUP BY gender, marital_status
ORDER BY customers DESC;

-- Age banding ---------------------------------------------------------------
SELECT age_band, COUNT(*) AS customers
FROM (
    SELECT customer_key,
           CASE WHEN birthdate IS NULL THEN 'Unknown'
                WHEN TIMESTAMPDIFF(YEAR, birthdate, CURDATE()) < 30 THEN 'Under 30'
                WHEN TIMESTAMPDIFF(YEAR, birthdate, CURDATE()) < 40 THEN '30-39'
                WHEN TIMESTAMPDIFF(YEAR, birthdate, CURDATE()) < 50 THEN '40-49'
                WHEN TIMESTAMPDIFF(YEAR, birthdate, CURDATE()) < 60 THEN '50-59'
                ELSE '60 and above'
           END AS age_band
    FROM gold.dim_customers
) AS banded
GROUP BY age_band
ORDER BY customers DESC;

-- Customer segmentation by value and tenure ---------------------------------
-- VIP / Regular / New is a standard RFM-style cut: lifespan separates loyal
-- customers from recent arrivals, spend separates high value from low.
SELECT segment,
       COUNT(*)                    AS customers,
       FORMAT(SUM(total_spend), 0) AS segment_revenue,
       FORMAT(AVG(total_spend), 0) AS avg_customer_value
FROM (
    SELECT
        c.customer_key,
        SUM(f.sales_amount) AS total_spend,
        CASE
            WHEN TIMESTAMPDIFF(MONTH, MIN(f.order_date), MAX(f.order_date)) >= 12
                 AND SUM(f.sales_amount) >  5000 THEN 'VIP'
            WHEN TIMESTAMPDIFF(MONTH, MIN(f.order_date), MAX(f.order_date)) >= 12
                 AND SUM(f.sales_amount) <= 5000 THEN 'Regular'
            ELSE 'New'
        END AS segment
    FROM gold.fact_sales AS f
    JOIN gold.dim_customers AS c ON f.customer_key = c.customer_key
    WHERE f.order_date IS NOT NULL
    GROUP BY c.customer_key
) AS seg
GROUP BY segment
ORDER BY SUM(total_spend) DESC;

-- Top 20 customers by lifetime value ----------------------------------------
SELECT
    CONCAT(c.first_name, ' ', c.last_name) AS customer,
    c.country,
    COUNT(DISTINCT f.order_number) AS orders,
    SUM(f.sales_amount)            AS lifetime_value,
    ROUND(SUM(f.sales_amount) / COUNT(DISTINCT f.order_number), 0) AS avg_order_value
FROM gold.fact_sales AS f
JOIN gold.dim_customers AS c ON f.customer_key = c.customer_key
GROUP BY c.customer_key, customer, c.country
ORDER BY lifetime_value DESC
LIMIT 20;
