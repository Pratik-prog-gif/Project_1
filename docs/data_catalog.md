# Data Catalog — Gold Layer

The gold layer is the business-facing model. It contains two dimension views
and one fact view, organised as a star schema.

---

## gold.dim_customers

Customer dimension, integrating CRM master data with ERP demographics and
location.

**Grain:** one row per customer.

| Column | Type | Description |
|---|---|---|
| `customer_key` | INT | Surrogate key. Generated per load; use it to join to `fact_sales`. |
| `customer_id` | INT | Natural key from the CRM system (`cst_id`). |
| `customer_number` | VARCHAR(50) | Alphanumeric business identifier (e.g. `AW00011000`). This is the key that conforms CRM and ERP. |
| `first_name` | VARCHAR(50) | Given name, trimmed. |
| `last_name` | VARCHAR(50) | Family name, trimmed. |
| `country` | VARCHAR(50) | Country of residence, normalised to a full name (e.g. `Australia`, `United States`). `n/a` where unknown. Sourced from ERP `LOC_A101`. |
| `marital_status` | VARCHAR(50) | `Single`, `Married`, or `n/a`. |
| `gender` | VARCHAR(50) | `Male`, `Female`, or `n/a`. CRM is the master; ERP is used only as a fallback. |
| `birthdate` | DATE | Date of birth. `NULL` where unknown or implausible. Sourced from ERP `CUST_AZ12`. |
| `create_date` | DATE | When the customer record was created in CRM. |

---

## gold.dim_products

Product dimension, integrating CRM product master data with the ERP category
hierarchy.

**Grain:** one row per *current* product. Historic product versions are
excluded (`prd_end_dt IS NULL`) so the fact join cannot fan out.

| Column | Type | Description |
|---|---|---|
| `product_key` | INT | Surrogate key. Generated per load; use it to join to `fact_sales`. |
| `product_id` | INT | Natural key from the CRM system (`prd_id`). |
| `product_number` | VARCHAR(50) | Business product code (e.g. `BK-R93R-62`). This is what sales rows reference. |
| `product_name` | VARCHAR(100) | Descriptive name, typically including model, colour and size. |
| `category_id` | VARCHAR(50) | Category code derived from the first five characters of the source `prd_key` (e.g. `CO_RF`). Joins to the ERP category file. |
| `category` | VARCHAR(50) | Top-level classification (e.g. `Bikes`, `Accessories`, `Components`). |
| `subcategory` | VARCHAR(50) | Finer classification (e.g. `Road Bikes`, `Bike Racks`). |
| `maintenance` | VARCHAR(50) | `Yes`/`No` — whether the product requires maintenance. |
| `cost` | INT | Base cost. `0` where the source supplied no value. |
| `product_line` | VARCHAR(50) | `Road`, `Mountain`, `Touring`, `Other Sales`, or `n/a`. |
| `start_date` | DATE | Date the product became available. |

---

## gold.fact_sales

Sales fact, one row per product line on an order.

**Grain:** one row per order line (`order_number` + `product_key`).

| Column | Type | Description |
|---|---|---|
| `order_number` | VARCHAR(50) | Sales order identifier (e.g. `SO43697`). Repeats across the lines of a multi-product order. |
| `product_key` | INT | Foreign key to `dim_products`. |
| `customer_key` | INT | Foreign key to `dim_customers`. |
| `order_date` | DATE | When the order was placed. `NULL` where the source value was invalid. |
| `shipping_date` | DATE | When the order shipped. |
| `due_date` | DATE | When payment was due. |
| `sales_amount` | INT | Line revenue in whole currency units. Guaranteed to equal `quantity * price`. |
| `quantity` | INT | Units ordered on this line. |
| `price` | INT | Unit price in whole currency units. Always positive. |

### Measures

| Measure | Expression |
|---|---|
| Total revenue | `SUM(sales_amount)` |
| Units sold | `SUM(quantity)` |
| Order count | `COUNT(DISTINCT order_number)` |
| Average order value | `SUM(sales_amount) / COUNT(DISTINCT order_number)` |
| Average selling price | `AVG(price)` |

### Notes for analysts

- `sales_amount` is stored per line, not per order. Aggregating by
  `order_number` without `SUM` will undercount multi-line orders.
- `order_date` is nullable. Time-series queries should filter
  `WHERE order_date IS NOT NULL` to avoid a spurious null bucket.
- Surrogate keys are regenerated on every load. Do not persist them outside
  the warehouse or use them as stable external identifiers — use
  `customer_number` and `product_number` for that.
