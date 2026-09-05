/*
===============================================================================
DDL: Gold Layer  (business-ready star schema)
===============================================================================
Purpose:
    Exposes the analytical model as views over silver. Views rather than tables
    because gold here is a presentation layer: it adds no new data, only
    conformed naming, integrated sources and surrogate keys, so materialising
    it would duplicate storage and add a refresh step for no benefit.

Model:
    fact_sales (transactions)
      |-- dim_customers  via customer_key
      +-- dim_products   via product_key

Integration decisions:
    * Gender is mastered by CRM. The ERP value is used only where CRM has none,
      which is why the CASE falls through to erp_cust_az12 rather than
      preferring it or concatenating the two.
    * dim_products exposes CURRENT products only (prd_end_dt IS NULL). Historic
      product versions remain in silver for auditability but would otherwise
      fan out the fact join and double-count revenue.
    * Surrogate keys are generated with ROW_NUMBER(). They are stable for a
      given load but regenerate on refresh -- acceptable because the fact view
      resolves them at query time rather than storing them.

Run:  mysql -u root -p < scripts/gold/ddl_gold.sql
===============================================================================
*/

USE gold;

-- ------------------------------------------------------- dim_customers -----
CREATE OR REPLACE VIEW gold.dim_customers AS
SELECT
    ROW_NUMBER() OVER (ORDER BY ci.cst_id)  AS customer_key,
    ci.cst_id                               AS customer_id,
    ci.cst_key                              AS customer_number,
    ci.cst_firstname                        AS first_name,
    ci.cst_lastname                         AS last_name,
    la.cntry                                AS country,
    ci.cst_marital_status                   AS marital_status,
    CASE WHEN ci.cst_gndr <> 'n/a' THEN ci.cst_gndr
         ELSE IFNULL(ca.gen, 'n/a')
    END                                     AS gender,
    ca.bdate                                AS birthdate,
    ci.cst_create_date                      AS create_date
FROM silver.crm_cust_info AS ci
LEFT JOIN silver.erp_cust_az12 AS ca ON ci.cst_key = ca.cid
LEFT JOIN silver.erp_loc_a101  AS la ON ci.cst_key = la.cid;

-- -------------------------------------------------------- dim_products -----
CREATE OR REPLACE VIEW gold.dim_products AS
SELECT
    ROW_NUMBER() OVER (ORDER BY pn.prd_start_dt, pn.prd_key) AS product_key,
    pn.prd_id        AS product_id,
    pn.prd_key       AS product_number,
    pn.prd_nm        AS product_name,
    pn.cat_id        AS category_id,
    pc.cat           AS category,
    pc.subcat        AS subcategory,
    pc.maintenance   AS maintenance,
    pn.prd_cost      AS cost,
    pn.prd_line      AS product_line,
    pn.prd_start_dt  AS start_date
FROM silver.crm_prd_info AS pn
LEFT JOIN silver.erp_px_cat_g1v2 AS pc ON pn.cat_id = pc.id
WHERE pn.prd_end_dt IS NULL;

-- ----------------------------------------------------------- fact_sales ----
CREATE OR REPLACE VIEW gold.fact_sales AS
SELECT
    sd.sls_ord_num   AS order_number,
    pr.product_key   AS product_key,
    cu.customer_key  AS customer_key,
    sd.sls_order_dt  AS order_date,
    sd.sls_ship_dt   AS shipping_date,
    sd.sls_due_dt    AS due_date,
    sd.sls_sales     AS sales_amount,
    sd.sls_quantity  AS quantity,
    sd.sls_price     AS price
FROM silver.crm_sales_details AS sd
LEFT JOIN gold.dim_products  AS pr ON sd.sls_prd_key = pr.product_number
LEFT JOIN gold.dim_customers AS cu ON sd.sls_cust_id = cu.customer_id;

SELECT 'Gold views created: dim_customers, dim_products, fact_sales.' AS status;
