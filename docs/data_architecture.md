# Data Architecture

The warehouse follows the **Medallion Architecture**: three layers, each with a
single responsibility, each consuming only the layer below it.

```mermaid
flowchart LR
    subgraph SRC["Sources"]
        CRM["CRM<br/>cust_info<br/>prd_info<br/>sales_details"]
        ERP["ERP<br/>CUST_AZ12<br/>LOC_A101<br/>PX_CAT_G1V2"]
    end

    subgraph BRZ["Bronze — Raw"]
        B["6 tables, as-is<br/>no transformation"]
    end

    subgraph SLV["Silver — Cleansed"]
        S["6 tables<br/>deduplicated, trimmed,<br/>typed, standardised"]
    end

    subgraph GLD["Gold — Business-Ready"]
        D1["dim_customers"]
        D2["dim_products"]
        F["fact_sales"]
    end

    subgraph BI["Consumption"]
        R["SQL analytics<br/>BI / reporting"]
    end

    CRM -->|LOAD DATA LOCAL INFILE| B
    ERP -->|LOAD DATA LOCAL INFILE| B
    B -->|silver.load_silver| S
    S -->|CREATE VIEW| D1
    S -->|CREATE VIEW| D2
    S -->|CREATE VIEW| F
    D1 --> R
    D2 --> R
    F --> R
```

## Layer responsibilities

| | Bronze | Silver | Gold |
|---|---|---|---|
| **Purpose** | Faithful landing zone | Cleansing and conforming | Business consumption |
| **Object type** | Tables | Tables | Views |
| **Transformation** | None | Dedup, trim, type-cast, standardise, derive, repair | Joins, renames, surrogate keys |
| **Data model** | As-is from source | As-is from source | Star schema |
| **Load** | Full refresh, truncate + insert | Full refresh, truncate + insert | Recomputed on query |
| **Audience** | Data engineers | Data engineers, analysts | Analysts, business users |

### Why bronze transforms nothing

Bronze exists so that any warehouse value can be traced back to the exact CSV
line it came from. The moment bronze cleans something, that audit trail is
gone and a bug in the cleansing rule becomes unprovable. This is why the CRM
sales dates stay as meaningless integers (`20101229`) in bronze — the invalid
values must survive long enough for silver to report on them.

### Why gold is views rather than tables

Gold adds no new data: it renames, joins and assigns surrogate keys. Making it
physical would duplicate storage and add a second refresh step that could fall
out of sync with silver. Views recompute on read and are always consistent
with the layer beneath them.

The trade-off is query cost — `fact_sales` joins two dimension views on every
read. At this data volume (~60k fact rows) that is immaterial. At a volume
where it mattered, the fix would be to materialise gold into tables loaded by
a `load_gold` procedure, keeping the same names so nothing downstream changes.

## Data flow

```mermaid
flowchart TD
    A1["cust_info.csv"] --> B1["bronze.crm_cust_info"] --> C1["silver.crm_cust_info"]
    A2["prd_info.csv"] --> B2["bronze.crm_prd_info"] --> C2["silver.crm_prd_info"]
    A3["sales_details.csv"] --> B3["bronze.crm_sales_details"] --> C3["silver.crm_sales_details"]
    A4["CUST_AZ12.csv"] --> B4["bronze.erp_cust_az12"] --> C4["silver.erp_cust_az12"]
    A5["LOC_A101.csv"] --> B5["bronze.erp_loc_a101"] --> C5["silver.erp_loc_a101"]
    A6["PX_CAT_G1V2.csv"] --> B6["bronze.erp_px_cat_g1v2"] --> C6["silver.erp_px_cat_g1v2"]

    C1 --> D1["gold.dim_customers"]
    C4 --> D1
    C5 --> D1
    C2 --> D2["gold.dim_products"]
    C6 --> D2
    C3 --> D3["gold.fact_sales"]
    D1 --> D3
    D2 --> D3
```

## Star schema

`fact_sales` sits at the centre, with two conformed dimensions.

```mermaid
erDiagram
    dim_customers ||--o{ fact_sales : "customer_key"
    dim_products  ||--o{ fact_sales : "product_key"

    dim_customers {
        int customer_key PK
        int customer_id
        varchar customer_number
        varchar first_name
        varchar last_name
        varchar country
        varchar marital_status
        varchar gender
        date birthdate
        date create_date
    }
    dim_products {
        int product_key PK
        int product_id
        varchar product_number
        varchar product_name
        varchar category_id
        varchar category
        varchar subcategory
        varchar maintenance
        int cost
        varchar product_line
        date start_date
    }
    fact_sales {
        varchar order_number
        int product_key FK
        int customer_key FK
        date order_date
        date shipping_date
        date due_date
        int sales_amount
        int quantity
        int price
    }
```

## Key integration decisions

**Customer keys differ across all three sources.** CRM uses `AW00011000`, ERP
customer uses `NASAW00011000`, ERP location uses `AW-00011000`. Silver strips
the `NAS` prefix and the hyphens so all three conform to the CRM key, which is
the master.

**Gender is mastered by CRM.** Both systems carry it and they disagree. The
gold layer takes the CRM value and falls back to ERP only where CRM has none,
rather than preferring ERP or trying to reconcile the two.

**Product category is derived, not supplied.** The link between CRM products
and ERP categories is not an explicit foreign key — it is embedded in the first
five characters of `prd_key`. Silver extracts it into `cat_id` and converts the
separator so it matches `erp_px_cat_g1v2.id`.
