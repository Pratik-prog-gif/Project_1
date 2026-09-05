/*
===============================================================================
Quality Checks: Gold Layer
===============================================================================
Purpose:
    Verifies the star schema is safe to report on: surrogate keys are unique,
    the fact table joins cleanly to both dimensions, and no measure is orphaned.

How to read the output:
    Every violations count must be 0.

Run:  mysql -u root -p < tests/quality_checks_gold.sql
===============================================================================
*/

USE gold;

-- 1. Surrogate key uniqueness in dim_customers.
SELECT 'dim_customers: duplicate customer_key' AS check_name,
       COUNT(*) AS violations
FROM (
    SELECT customer_key FROM gold.dim_customers
    GROUP BY customer_key HAVING COUNT(*) > 1
) AS d;

-- 2. Surrogate key uniqueness in dim_products.
SELECT 'dim_products: duplicate product_key' AS check_name,
       COUNT(*) AS violations
FROM (
    SELECT product_key FROM gold.dim_products
    GROUP BY product_key HAVING COUNT(*) > 1
) AS d;

-- 3. Natural key uniqueness -- a duplicated product_number would fan out the
--    fact join and silently double-count revenue.
SELECT 'dim_products: duplicate product_number' AS check_name,
       COUNT(*) AS violations
FROM (
    SELECT product_number FROM gold.dim_products
    GROUP BY product_number HAVING COUNT(*) > 1
) AS d;

-- 4. Fact-to-dimension integrity: no fact row may fail to find a dimension.
SELECT 'fact_sales: unmatched customer_key' AS check_name,
       COUNT(*) AS violations
FROM gold.fact_sales
WHERE customer_key IS NULL;

SELECT 'fact_sales: unmatched product_key' AS check_name,
       COUNT(*) AS violations
FROM gold.fact_sales
WHERE product_key IS NULL;

-- 5. Measures must be present and positive.
SELECT 'fact_sales: invalid measures' AS check_name,
       COUNT(*) AS violations
FROM gold.fact_sales
WHERE sales_amount IS NULL OR sales_amount <= 0
   OR quantity     IS NULL OR quantity     <= 0
   OR price        IS NULL OR price        <= 0;

-- 6. Dimension vocabularies must stay closed.
SELECT 'dim_customers: unexpected gender' AS check_name,
       COUNT(*) AS violations
FROM gold.dim_customers
WHERE gender NOT IN ('Male', 'Female', 'n/a');
