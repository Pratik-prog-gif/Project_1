/*
===============================================================================
Initialise the Data Warehouse
===============================================================================
Purpose:
    Creates the three Medallion layers. SQL Server models layers as *schemas*
    inside one database; MySQL has no schema-below-database concept, so each
    layer is created as its own database. This keeps every qualified name
    identical to the reference design (e.g. bronze.crm_cust_info).

WARNING:
    This script DROPS the bronze, silver and gold databases if they exist.
    All data in them is permanently lost. Take a backup before running.

Run:  mysql -u root -p < scripts/init_database.sql
===============================================================================
*/

DROP DATABASE IF EXISTS bronze;
DROP DATABASE IF EXISTS silver;
DROP DATABASE IF EXISTS gold;

CREATE DATABASE bronze DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE DATABASE silver DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE DATABASE gold   DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

SELECT 'Databases bronze, silver, gold created.' AS status;
