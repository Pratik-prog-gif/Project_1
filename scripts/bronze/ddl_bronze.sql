/*
===============================================================================
DDL: Bronze Layer
===============================================================================
Purpose:
    Defines the raw landing tables. Bronze stores source data AS-IS: no
    cleansing, no renaming, no type coercion beyond what is needed to land the
    value. Column names mirror the source system exactly so that any bronze row
    can be traced back to its CSV line.

    Date columns arriving from CRM sales as integers (e.g. 20101229) are kept
    as INT on purpose -- converting them here would discard the malformed
    values that the silver layer is responsible for reporting on and fixing.

Run:  mysql -u root -p < scripts/bronze/ddl_bronze.sql
===============================================================================
*/

USE bronze;

DROP TABLE IF EXISTS crm_cust_info;
CREATE TABLE crm_cust_info (
    cst_id              INT,
    cst_key             VARCHAR(50),
    cst_firstname       VARCHAR(50),
    cst_lastname        VARCHAR(50),
    cst_marital_status  VARCHAR(50),
    cst_gndr            VARCHAR(50),
    cst_create_date     DATE
);

DROP TABLE IF EXISTS crm_prd_info;
CREATE TABLE crm_prd_info (
    prd_id       INT,
    prd_key      VARCHAR(50),
    prd_nm       VARCHAR(100),
    prd_cost     INT,
    prd_line     VARCHAR(50),
    prd_start_dt DATE,
    prd_end_dt   DATE
);

DROP TABLE IF EXISTS crm_sales_details;
CREATE TABLE crm_sales_details (
    sls_ord_num  VARCHAR(50),
    sls_prd_key  VARCHAR(50),
    sls_cust_id  INT,
    sls_order_dt INT,
    sls_ship_dt  INT,
    sls_due_dt   INT,
    sls_sales    INT,
    sls_quantity INT,
    sls_price    INT
);

DROP TABLE IF EXISTS erp_cust_az12;
CREATE TABLE erp_cust_az12 (
    cid   VARCHAR(50),
    bdate DATE,
    gen   VARCHAR(50)
);

DROP TABLE IF EXISTS erp_loc_a101;
CREATE TABLE erp_loc_a101 (
    cid   VARCHAR(50),
    cntry VARCHAR(50)
);

DROP TABLE IF EXISTS erp_px_cat_g1v2;
CREATE TABLE erp_px_cat_g1v2 (
    id          VARCHAR(50),
    cat         VARCHAR(50),
    subcat      VARCHAR(50),
    maintenance VARCHAR(50)
);

SELECT 'Bronze tables created.' AS status;
