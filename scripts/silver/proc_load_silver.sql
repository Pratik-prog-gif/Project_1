/*
===============================================================================
Procedure: silver.load_silver()  (bronze -> silver)
===============================================================================
Purpose:
    Performs the ETL that turns raw bronze rows into cleansed, conformed silver
    rows. Full-refresh: every table is truncated and rebuilt.

Cleansing rules applied, and why each is needed:

  crm_cust_info
    * Deduplication. cst_id repeats in the source; ROW_NUMBER() keeps only the
      most recent record per customer (latest cst_create_date).
    * Whitespace. Names arrive padded (" Jon", "Yang ") -- TRIM removes it.
    * Coded values expanded. 'S'/'M' -> Single/Married, 'F'/'M' -> Female/Male.
      Anything unrecognised or NULL becomes 'n/a' rather than a silent NULL, so
      downstream reports never render a blank dimension member.

  crm_prd_info
    * prd_key is a composite. Characters 1-5 are the ERP category id (with '-'
      swapped for '_' to match erp_px_cat_g1v2.id); characters 7+ are the true
      product key that sales rows reference.
    * The two systems disagree on one category code: CRM uses CO_PE for pedals,
      ERP uses CO_PD. CO_PE is remapped to CO_PD so those products resolve to
      Components / Pedals instead of dropping out of category reporting.
    * NULL prd_cost becomes 0 -- a missing cost must not null out a revenue
      calculation.
    * prd_end_dt in the source is unreliable. It is recalculated as the day
      before the next start date for the same product, producing a clean,
      gapless slowly-changing-dimension timeline.

  crm_sales_details
    * Dates arrive as integers (20101229). Values that are zero, negative or
      not exactly 8 digits are invalid and become NULL.
    * Integrity rule: sales = quantity * price. Where the stored sales value is
      missing, non-positive or disagrees with that identity, it is recomputed.
      A negative price is treated as a sign error and its absolute value used.
    * A missing or non-positive price is derived back from sales / quantity.

  erp_cust_az12
    * cid carries a 'NAS' prefix that must be stripped to match crm cst_key.
    * Birthdates in the future are impossible and become NULL.

  erp_loc_a101
    * cid contains hyphens absent from the CRM key; they are removed.
    * Country codes are normalised ('DE' -> Germany, 'US'/'USA' -> United
      States); blanks become 'n/a'.

Run:     mysql -u root -p < scripts/silver/proc_load_silver.sql
Execute: CALL silver.load_silver();
===============================================================================
*/

USE silver;

DROP PROCEDURE IF EXISTS load_silver;

DELIMITER //

CREATE PROCEDURE load_silver()
BEGIN
    DECLARE v_start DATETIME;

    -- Mirror of SQL Server's TRY/CATCH: report the failure, roll back, then
    -- re-raise so the caller's exit code reflects it.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET v_start = NOW();
    START TRANSACTION;

    -- ============================================================ CRM =======
    TRUNCATE TABLE silver.crm_cust_info;
    INSERT INTO silver.crm_cust_info (
        cst_id, cst_key, cst_firstname, cst_lastname,
        cst_marital_status, cst_gndr, cst_create_date
    )
    SELECT
        cst_id,
        cst_key,
        TRIM(cst_firstname),
        TRIM(cst_lastname),
        CASE UPPER(TRIM(cst_marital_status))
             WHEN 'S' THEN 'Single'
             WHEN 'M' THEN 'Married'
             ELSE 'n/a'
        END,
        CASE UPPER(TRIM(cst_gndr))
             WHEN 'F' THEN 'Female'
             WHEN 'M' THEN 'Male'
             ELSE 'n/a'
        END,
        cst_create_date
    FROM (
        SELECT bci.*,
               ROW_NUMBER() OVER (
                   PARTITION BY cst_id
                   ORDER BY cst_create_date DESC
               ) AS flag_last
        FROM bronze.crm_cust_info AS bci
        WHERE cst_id IS NOT NULL
    ) AS ranked
    WHERE flag_last = 1;

    TRUNCATE TABLE silver.crm_prd_info;
    INSERT INTO silver.crm_prd_info (
        prd_id, cat_id, prd_key, prd_nm, prd_cost,
        prd_line, prd_start_dt, prd_end_dt
    )
    SELECT
        prd_id,
        -- Conform the category code across the two systems. CRM codes pedals
        -- as CO_PE; ERP has no such id and uses CO_PD ("Components / Pedals").
        -- All seven affected products are named "... Pedal", so the codes
        -- denote the same subcategory. Without this mapping those products
        -- join to no category at all and fall out of category reporting.
        CASE REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_')
             WHEN 'CO_PE' THEN 'CO_PD'
             ELSE REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_')
        END                                          AS cat_id,
        SUBSTRING(prd_key, 7)                        AS product_key,
        prd_nm,
        IFNULL(prd_cost, 0),
        CASE UPPER(TRIM(prd_line))
             WHEN 'M' THEN 'Mountain'
             WHEN 'R' THEN 'Road'
             WHEN 'S' THEN 'Other Sales'
             WHEN 'T' THEN 'Touring'
             ELSE 'n/a'
        END,
        prd_start_dt,
        DATE_SUB(
            LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt),
            INTERVAL 1 DAY
        )                                            AS prd_end_dt
    FROM bronze.crm_prd_info;

    TRUNCATE TABLE silver.crm_sales_details;
    INSERT INTO silver.crm_sales_details (
        sls_ord_num, sls_prd_key, sls_cust_id,
        sls_order_dt, sls_ship_dt, sls_due_dt,
        sls_sales, sls_quantity, sls_price
    )
    SELECT
        sls_ord_num,
        sls_prd_key,
        sls_cust_id,
        CASE WHEN sls_order_dt IS NULL OR sls_order_dt <= 0
                  OR LENGTH(CAST(sls_order_dt AS CHAR)) <> 8 THEN NULL
             ELSE STR_TO_DATE(CAST(sls_order_dt AS CHAR), '%Y%m%d')
        END,
        CASE WHEN sls_ship_dt IS NULL OR sls_ship_dt <= 0
                  OR LENGTH(CAST(sls_ship_dt AS CHAR)) <> 8 THEN NULL
             ELSE STR_TO_DATE(CAST(sls_ship_dt AS CHAR), '%Y%m%d')
        END,
        CASE WHEN sls_due_dt IS NULL OR sls_due_dt <= 0
                  OR LENGTH(CAST(sls_due_dt AS CHAR)) <> 8 THEN NULL
             ELSE STR_TO_DATE(CAST(sls_due_dt AS CHAR), '%Y%m%d')
        END,
        CASE WHEN sls_sales IS NULL OR sls_sales <= 0
                  OR sls_sales <> sls_quantity * ABS(sls_price)
             THEN sls_quantity * ABS(sls_price)
             ELSE sls_sales
        END,
        sls_quantity,
        CASE WHEN sls_price IS NULL OR sls_price <= 0
             THEN sls_sales / NULLIF(sls_quantity, 0)
             ELSE sls_price
        END
    FROM bronze.crm_sales_details;

    -- ============================================================ ERP =======
    TRUNCATE TABLE silver.erp_cust_az12;
    INSERT INTO silver.erp_cust_az12 (cid, bdate, gen)
    SELECT
        CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4) ELSE cid END,
        CASE WHEN bdate > CURDATE() THEN NULL ELSE bdate END,
        CASE WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
             WHEN UPPER(TRIM(gen)) IN ('M', 'MALE')   THEN 'Male'
             ELSE 'n/a'
        END
    FROM bronze.erp_cust_az12;

    TRUNCATE TABLE silver.erp_loc_a101;
    INSERT INTO silver.erp_loc_a101 (cid, cntry)
    SELECT
        REPLACE(cid, '-', ''),
        CASE WHEN TRIM(cntry) = 'DE'               THEN 'Germany'
             WHEN TRIM(cntry) IN ('US', 'USA')     THEN 'United States'
             WHEN cntry IS NULL OR TRIM(cntry) = '' THEN 'n/a'
             ELSE TRIM(cntry)
        END
    FROM bronze.erp_loc_a101;

    TRUNCATE TABLE silver.erp_px_cat_g1v2;
    INSERT INTO silver.erp_px_cat_g1v2 (id, cat, subcat, maintenance)
    SELECT TRIM(id), TRIM(cat), TRIM(subcat), TRIM(maintenance)
    FROM bronze.erp_px_cat_g1v2;

    COMMIT;

    SELECT CONCAT('Silver load finished in ',
                  TIMESTAMPDIFF(SECOND, v_start, NOW()), ' s') AS status;
END//

DELIMITER ;

SELECT 'Procedure silver.load_silver() created.' AS status;
