# Project Requirements

## 1. Building the Data Warehouse (Data Engineering)

### Objective
Develop a modern data warehouse to consolidate sales data, enabling analytical
reporting and informed decision-making.

### Specifications

| # | Requirement | How it is met |
|---|---|---|
| 1 | **Data Sources** — import from two source systems (ERP and CRM) provided as CSV files | Six CSVs land in `dataset/source_crm/` and `dataset/source_erp/`, loaded by `scripts/bronze/load_bronze.sql` |
| 2 | **Data Quality** — cleanse and resolve quality issues prior to analysis | `silver.load_silver()` applies deduplication, trimming, code expansion, date repair and integrity correction; `tests/quality_checks_silver.sql` proves each rule held |
| 3 | **Integration** — combine both sources into a single, user-friendly model | The gold layer joins CRM and ERP on conformed keys into `dim_customers`, `dim_products`, `fact_sales` |
| 4 | **Scope** — latest dataset only, no historisation | All loads are full-refresh (`TRUNCATE` + `INSERT`); `dim_products` exposes current products only |
| 5 | **Documentation** — clear documentation of the data model | `docs/data_catalog.md` documents every gold field; `docs/data_architecture.md` documents the flow |

### Data quality issues found in the source, and their resolution

These were identified by profiling the raw CSVs before any code was written.

| Source | Issue | Resolution |
|---|---|---|
| `cust_info.csv` | `cst_id` duplicated across rows | Keep the most recent record per customer via `ROW_NUMBER()` ordered by `cst_create_date DESC` |
| `cust_info.csv` | Names padded with whitespace (`" Jon"`, `"Yang "`) | `TRIM()` on first and last name |
| `cust_info.csv` | Gender/marital status stored as single-letter codes | Expanded to `Male`/`Female`, `Single`/`Married`; unknowns become `n/a` |
| `prd_info.csv` | `prd_cost` blank on some rows | Defaulted to `0` so revenue maths never nulls out |
| `prd_info.csv` | `prd_key` is a composite of category id + product key | Split: chars 1–5 become `cat_id` (with `-` → `_`), chars 7+ become `prd_key` |
| `prd_info.csv` | `prd_end_dt` unreliable / blank | Recalculated as the day before the next start date for the same product |
| `prd_info.csv` | `prd_line` padded and coded (`"R "`) | Trimmed and expanded to `Road`/`Mountain`/`Touring`/`Other Sales` |
| `sales_details.csv` | Dates stored as integers (`20101229`) | Converted to `DATE`; 19 rows with zero/invalid values become `NULL` |
| `sales_details.csv` | `sales <> quantity * price` on some rows; negative prices | Recomputed from the identity, using `ABS(price)` |
| `CUST_AZ12.csv` | `cid` carries a `NAS` prefix absent from CRM | Prefix stripped so the key joins |
| `CUST_AZ12.csv` | Birthdates in the future | Set to `NULL` |
| `LOC_A101.csv` | `cid` contains hyphens absent from CRM | Hyphens removed |
| `LOC_A101.csv` | Country codes inconsistent (`DE`, `US`, `USA`, blank) | Normalised to full names; blanks become `n/a` |
| `prd_info.csv` vs `PX_CAT_G1V2.csv` | The systems disagree on one category code: CRM codes pedals `CO_PE`, ERP has only `CO_PD` (Components / Pedals). 7 products resolved to no category. | `CO_PE` remapped to `CO_PD` in silver — see assumption below |

### Assumptions

**`CO_PE` → `CO_PD`.** This mapping is inferred, not supplied by either source
system. The evidence: all seven affected products are named `... Pedal`
(`LL Mountain Pedal`, `Touring Pedal`, and so on), ERP's `CO_PD` is exactly
`Components / Pedals`, and no other ERP code is a plausible match. Left
unmapped, those products join to a `NULL` category and silently disappear from
every category-level report.

If this turns out to be wrong, the single `CASE` in `silver.load_silver()`
that performs it can be removed without touching anything else; quality check
14 in `tests/quality_checks_silver.sql` will then flag the 7 rows again.

### Known data characteristics (not defects)

These are reported by the informational section of the silver checks and are
deliberately left in the data:

- **15 customers born before 1924** (earliest 1916-02-10). Unusual but
  internally consistent. The ETL nulls only *impossible* birthdates — those in
  the future — rather than destroying real records on an arbitrary age cutoff.
- **19 sales rows with no usable order date.** The source integer was `0` or
  malformed. The date becomes `NULL`; the row's revenue is retained, so
  totals stay correct while time-series queries filter these out.

## 2. BI: Analytics & Reporting (Data Analysis)

### Objective
Develop SQL-based analytics delivering detailed insight into:

- **Customer Behaviour** — demographics, age bands, VIP/Regular/New segmentation, lifetime value (`analytics/03_customer_behaviour.sql`)
- **Product Performance** — category revenue share, top/bottom products, performance against category average, cost banding (`analytics/02_product_performance.sql`)
- **Sales Trends** — headline KPIs, monthly running totals and moving averages, year-over-year change, sales by country (`analytics/01_sales_trends.sql`)
