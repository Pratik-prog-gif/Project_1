/*
===============================================================================
Load: Bronze Layer  (Source CSV -> bronze)
===============================================================================
Purpose:
    Full-refresh load of the six source files. Each table is TRUNCATEd and
    reloaded; the project scope is "latest snapshot only", so no historisation
    is attempted.

Why LOCAL INFILE:
    The server's secure-file-priv is restricted to its own Uploads directory,
    so a plain LOAD DATA INFILE cannot read the repo. LOCAL sends the file from
    the client instead, which requires local_infile=ON on the server and
    --local-infile=1 on the client.

Why every column goes through a @variable:
    The server runs with STRICT_TRANS_TABLES and NO_ZERO_DATE. An empty CSV
    field ('') assigned straight to an INT or DATE column is an ERROR, not a
    warning, and aborts the load. Reading into a @variable and applying
    NULLIF() turns those blanks into proper NULLs.

Line endings:
    All six source files are CRLF. Without LINES TERMINATED BY '\r\n' the final
    column of every row would retain a trailing carriage return.

Run from the REPOSITORY ROOT (paths below are relative to it):
    mysql --local-infile=1 -u root -p < scripts/bronze/load_bronze.sql
===============================================================================
*/

SET @start_batch = NOW();
USE bronze;

-- ---------------------------------------------------------------- CRM ------
SELECT '>> Loading crm_cust_info' AS step;
TRUNCATE TABLE crm_cust_info;
LOAD DATA LOCAL INFILE 'dataset/source_crm/cust_info.csv'
INTO TABLE crm_cust_info
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(@cst_id, @cst_key, @cst_firstname, @cst_lastname,
 @cst_marital_status, @cst_gndr, @cst_create_date)
SET cst_id             = NULLIF(@cst_id, ''),
    cst_key            = NULLIF(@cst_key, ''),
    cst_firstname      = NULLIF(@cst_firstname, ''),
    cst_lastname       = NULLIF(@cst_lastname, ''),
    cst_marital_status = NULLIF(@cst_marital_status, ''),
    cst_gndr           = NULLIF(@cst_gndr, ''),
    cst_create_date    = NULLIF(@cst_create_date, '');

SELECT '>> Loading crm_prd_info' AS step;
TRUNCATE TABLE crm_prd_info;
LOAD DATA LOCAL INFILE 'dataset/source_crm/prd_info.csv'
INTO TABLE crm_prd_info
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(@prd_id, @prd_key, @prd_nm, @prd_cost, @prd_line, @prd_start_dt, @prd_end_dt)
SET prd_id       = NULLIF(@prd_id, ''),
    prd_key      = NULLIF(@prd_key, ''),
    prd_nm       = NULLIF(@prd_nm, ''),
    prd_cost     = NULLIF(@prd_cost, ''),
    prd_line     = NULLIF(@prd_line, ''),
    prd_start_dt = NULLIF(@prd_start_dt, ''),
    prd_end_dt   = NULLIF(@prd_end_dt, '');

SELECT '>> Loading crm_sales_details' AS step;
TRUNCATE TABLE crm_sales_details;
LOAD DATA LOCAL INFILE 'dataset/source_crm/sales_details.csv'
INTO TABLE crm_sales_details
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(@sls_ord_num, @sls_prd_key, @sls_cust_id, @sls_order_dt, @sls_ship_dt,
 @sls_due_dt, @sls_sales, @sls_quantity, @sls_price)
SET sls_ord_num  = NULLIF(@sls_ord_num, ''),
    sls_prd_key  = NULLIF(@sls_prd_key, ''),
    sls_cust_id  = NULLIF(@sls_cust_id, ''),
    sls_order_dt = NULLIF(@sls_order_dt, ''),
    sls_ship_dt  = NULLIF(@sls_ship_dt, ''),
    sls_due_dt   = NULLIF(@sls_due_dt, ''),
    sls_sales    = NULLIF(@sls_sales, ''),
    sls_quantity = NULLIF(@sls_quantity, ''),
    sls_price    = NULLIF(@sls_price, '');

-- ---------------------------------------------------------------- ERP ------
SELECT '>> Loading erp_cust_az12' AS step;
TRUNCATE TABLE erp_cust_az12;
LOAD DATA LOCAL INFILE 'dataset/source_erp/CUST_AZ12.csv'
INTO TABLE erp_cust_az12
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(@cid, @bdate, @gen)
SET cid   = NULLIF(@cid, ''),
    bdate = NULLIF(@bdate, ''),
    gen   = NULLIF(@gen, '');

SELECT '>> Loading erp_loc_a101' AS step;
TRUNCATE TABLE erp_loc_a101;
LOAD DATA LOCAL INFILE 'dataset/source_erp/LOC_A101.csv'
INTO TABLE erp_loc_a101
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(@cid, @cntry)
SET cid   = NULLIF(@cid, ''),
    cntry = NULLIF(@cntry, '');

SELECT '>> Loading erp_px_cat_g1v2' AS step;
TRUNCATE TABLE erp_px_cat_g1v2;
LOAD DATA LOCAL INFILE 'dataset/source_erp/PX_CAT_G1V2.csv'
INTO TABLE erp_px_cat_g1v2
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(@id, @cat, @subcat, @maintenance)
SET id          = NULLIF(@id, ''),
    cat         = NULLIF(@cat, ''),
    subcat      = NULLIF(@subcat, ''),
    maintenance = NULLIF(@maintenance, '');

-- ------------------------------------------------------------- Summary -----
SELECT 'crm_cust_info'     AS table_name, COUNT(*) AS rows_loaded FROM crm_cust_info
UNION ALL SELECT 'crm_prd_info',        COUNT(*) FROM crm_prd_info
UNION ALL SELECT 'crm_sales_details',   COUNT(*) FROM crm_sales_details
UNION ALL SELECT 'erp_cust_az12',       COUNT(*) FROM erp_cust_az12
UNION ALL SELECT 'erp_loc_a101',        COUNT(*) FROM erp_loc_a101
UNION ALL SELECT 'erp_px_cat_g1v2',     COUNT(*) FROM erp_px_cat_g1v2;

SELECT CONCAT('Bronze load finished in ',
              TIMESTAMPDIFF(SECOND, @start_batch, NOW()), ' s') AS status;
