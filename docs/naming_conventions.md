# Naming Conventions

Consistent naming is what lets a reader infer a table's layer, its source
system and its role without opening it.

## General rules

- `snake_case` throughout: lowercase words separated by underscores.
- English only.
- Never use a reserved SQL keyword as an object name.

## Layers

Each Medallion layer is its own MySQL database, so the layer is always the
first qualifier in a fully-qualified name.

| Layer | Database | Contents |
|---|---|---|
| Bronze | `bronze` | Raw source tables, unmodified |
| Silver | `silver` | Cleansed and standardised tables |
| Gold | `gold` | Business-ready views (star schema) |

## Table naming

### Bronze and Silver — `<sourcesystem>_<entity>`

The source system prefix is mandatory, because the same entity exists in both
systems and the prefix is what keeps them apart.

- `<sourcesystem>` — `crm` or `erp`
- `<entity>` — the exact source table/file name, unchanged

Examples:
- `crm_cust_info` — customer information from CRM
- `erp_px_cat_g1v2` — product categories from ERP

Bronze and silver deliberately keep the *source's* cryptic names (`az12`,
`g1v2`). Renaming them there would break traceability back to the source file;
renaming belongs in gold.

### Gold — `<category>_<entity>`

The source prefix is dropped, because gold is integrated and business-facing;
a name like `dim_customers` should not leak which system the data came from.

| Prefix | Meaning | Examples |
|---|---|---|
| `dim_` | Dimension table | `dim_customers`, `dim_products` |
| `fact_` | Fact table | `fact_sales` |
| `report_` | Aggregated reporting object | `report_customers` |

## Column naming

### Surrogate keys — `<table>_key`

Every dimension's surrogate key ends in `_key`.

- `customer_key` — surrogate key of `dim_customers`

### Technical columns — `dwh_<column>`

Warehouse-generated metadata carries a `dwh_` prefix so it can never be
confused with a source-supplied value.

- `dwh_create_date` — when the warehouse materialised the row

### Business columns

In gold, columns are renamed to plain business language: `cst_firstname`
becomes `first_name`, `sls_sales` becomes `sales_amount`.

## Stored procedures

Load procedures follow `load_<layer>`:

- `silver.load_silver()`
