/*
===============================================================================
Quality Checks: Silver Layer
===============================================================================
Purpose:
    Verifies that every cleansing rule in silver.load_silver() actually held.

How to read the output:
    Each check returns a single row with a violations count. EVERY count must
    be 0. A non-zero value means the corresponding rule failed and the silver
    load should not be promoted to gold.

Run:  mysql -u root -p < tests/quality_checks_silver.sql
===============================================================================
*/

USE silver;

-- 1. Primary key must be unique and never NULL.
SELECT 'crm_cust_info: duplicate or null cst_id' AS check_name,
       COUNT(*) AS violations
FROM (
    SELECT cst_id FROM silver.crm_cust_info
    GROUP BY cst_id HAVING COUNT(*) > 1 OR cst_id IS NULL
) AS d;

-- 2. No leading/trailing whitespace should survive cleansing.
SELECT 'crm_cust_info: untrimmed names' AS check_name,
       COUNT(*) AS violations
FROM silver.crm_cust_info
WHERE cst_firstname <> TRIM(cst_firstname)
   OR cst_lastname  <> TRIM(cst_lastname);

-- 3. Coded columns must only contain the expanded vocabulary.
SELECT 'crm_cust_info: unexpected gender/marital values' AS check_name,
       COUNT(*) AS violations
FROM silver.crm_cust_info
WHERE cst_gndr NOT IN ('Male', 'Female', 'n/a')
   OR cst_marital_status NOT IN ('Single', 'Married', 'n/a');

-- 4. Product key must be unique.
SELECT 'crm_prd_info: duplicate or null prd_id' AS check_name,
       COUNT(*) AS violations
FROM (
    SELECT prd_id FROM silver.crm_prd_info
    GROUP BY prd_id HAVING COUNT(*) > 1 OR prd_id IS NULL
) AS d;

-- 5. Cost is defaulted to 0, so it can never be NULL or negative.
SELECT 'crm_prd_info: null or negative cost' AS check_name,
       COUNT(*) AS violations
FROM silver.crm_prd_info
WHERE prd_cost IS NULL OR prd_cost < 0;

-- 6. The recalculated SCD timeline must never end before it starts.
SELECT 'crm_prd_info: end date before start date' AS check_name,
       COUNT(*) AS violations
FROM silver.crm_prd_info
WHERE prd_end_dt < prd_start_dt;

-- 7. Product line must only contain the expanded vocabulary.
SELECT 'crm_prd_info: unexpected product line' AS check_name,
       COUNT(*) AS violations
FROM silver.crm_prd_info
WHERE prd_line NOT IN ('Mountain', 'Road', 'Other Sales', 'Touring', 'n/a');

-- 8. Order date must not follow shipping or due date.
SELECT 'crm_sales_details: order date after ship/due date' AS check_name,
       COUNT(*) AS violations
FROM silver.crm_sales_details
WHERE sls_order_dt > sls_ship_dt
   OR sls_order_dt > sls_due_dt;

-- 9. The sales = quantity * price identity must now hold everywhere.
SELECT 'crm_sales_details: sales <> quantity * price' AS check_name,
       COUNT(*) AS violations
FROM silver.crm_sales_details
WHERE sls_sales <> sls_quantity * sls_price
   OR sls_sales IS NULL OR sls_quantity IS NULL OR sls_price IS NULL
   OR sls_sales <= 0 OR sls_quantity <= 0 OR sls_price <= 0;

-- 10. The 'NAS' prefix must be fully stripped from ERP customer ids.
SELECT 'erp_cust_az12: NAS prefix not stripped' AS check_name,
       COUNT(*) AS violations
FROM silver.erp_cust_az12
WHERE cid LIKE 'NAS%';

-- 11. A birthdate in the future is impossible, so this is a hard gate. The
--     ETL nulls such values; any survivor means the rule did not run.
SELECT 'erp_cust_az12: birthdate in the future' AS check_name,
       COUNT(*) AS violations
FROM silver.erp_cust_az12
WHERE bdate > CURDATE();

-- 12. Hyphens must be removed so the key joins to CRM.
SELECT 'erp_loc_a101: hyphen left in cid' AS check_name,
       COUNT(*) AS violations
FROM silver.erp_loc_a101
WHERE cid LIKE '%-%';

-- 13. Referential integrity: every ERP customer should match a CRM customer.
SELECT 'erp_cust_az12: orphaned against crm_cust_info' AS check_name,
       COUNT(*) AS violations
FROM silver.erp_cust_az12 AS ca
LEFT JOIN silver.crm_cust_info AS ci ON ca.cid = ci.cst_key
WHERE ci.cst_key IS NULL;

-- 14. Category ids extracted from prd_key must resolve against the ERP file.
--     This is what surfaced the CRM CO_PE / ERP CO_PD disagreement that
--     silver.load_silver() now reconciles.
SELECT 'crm_prd_info: cat_id not found in erp_px_cat_g1v2' AS check_name,
       COUNT(*) AS violations
FROM silver.crm_prd_info AS pn
LEFT JOIN silver.erp_px_cat_g1v2 AS pc ON pn.cat_id = pc.id
WHERE pc.id IS NULL;

/*
-------------------------------------------------------------------------------
 INFORMATIONAL -- not pass/fail
-------------------------------------------------------------------------------
 These report on the data rather than gate it. A non-zero count is expected and
 does not block promotion to gold.
-------------------------------------------------------------------------------
*/

-- Very old birthdates. The source genuinely contains customers born in the
-- 1910s and 1920s. They are unusual but internally consistent, so the ETL
-- deliberately leaves them intact rather than destroying real data; only
-- impossible (future) dates are nulled. Reported here for visibility.
SELECT 'INFO: birthdates before 1924' AS check_name,
       COUNT(*)   AS records,
       MIN(bdate) AS earliest
FROM silver.erp_cust_az12
WHERE bdate < '1924-01-01';

-- Sales rows whose order date could not be parsed from the source integer.
SELECT 'INFO: sales rows with no usable order date' AS check_name,
       COUNT(*) AS records
FROM silver.crm_sales_details
WHERE sls_order_dt IS NULL;
