# Chicago Construction Permit Activity Analysis (2019 to 2024)

**Author:** Sivaram Konasani · Finance & Business Analytics, Indiana University Kelley School of Business
**Stack:** Python · SQL · pandas · Chicago Data Portal API
**Data source:** City of Chicago Building Permits, data.cityofchicago.org (236,847 records)

---

## View the interactive dashboard

### [Launch dashboard →](https://skonasani.github.io/Chicago-Permits-Analysis/Dashboard.html)

The dashboard includes five KPI cards, annual permit volume and value trends, work type breakdown, new construction YoY growth by building type, top 10 community areas by volume, and a neighborhood value table with materials demand signals.

---

## Why I built this

During my internship at US Gypsum Corp. (USG), I spent a summer building Power BI dashboards and SQL reporting pipelines across a $1.1B industrial project portfolio. USG's core business is building materials, drywall goes into every permitted building in Chicago. I tracked procurement KPIs, vendor spend, and cost savings internally, but had no visibility into where construction demand was actually originating in the market.

That question stayed with me. After the internship I pulled the City of Chicago's public building permit dataset to answer it directly, where is construction activity concentrated, which project types are growing, and what does the permit trend signal about near-term materials demand?

This project is the result. A full analysis pipeline from raw CSV ingestion through SQL transformation to a stakeholder-ready dashboard, built with the same workflow I would use on the job.

---

## Business questions answered

1. Is Chicago construction activity recovering post-pandemic, and at what rate?
2. Which community areas are seeing the highest permit volume and value growth?
3. Is the mix shifting toward new construction vs. renovation, and why does that matter for materials suppliers?
4. Which neighborhoods represent the highest-value emerging demand corridors?

---

## Architecture

```
Chicago Data Portal API
        │
        ▼
  [ Python ingest ]
   notebooks/01_ingest.py
   - Pulls raw permit CSV via Socrata API
   - Schema validation
   - Saves to data/raw/permits_raw.csv
        │
        ▼
  [ SQL transforms ]
   sql/02_transform.sql
   - YoY permit volume change per community area
   - Rolling 3-month permit averages
   - Permit value aggregations by type and ward
   - New construction share trending over time
   - Outlier detection and data quality checks
   - Materials demand signal scoring
        │
        ▼
  [ Dashboard ]
   Dashboard.html
   - 5 KPI cards
   - Annual trend (dual axis: volume + value)
   - Work type donut chart
   - New construction YoY by building type
   - Top 10 community areas by volume
   - Neighborhood value table with demand signals
```

---

## Repository structure

```
Chicago-Permits-Analysis/
├── sql/
│   └── 02_transform.sql        # YoY, rolling avg, share calcs, outlier detection, demand scoring
├── notebooks/
│   └── 01_ingest.py            # Data ingestion from Chicago Data Portal
├── Dashboard.html              # Standalone interactive dashboard
├── Requirements.txt
└── README.md
```

---

## Key findings

| Finding | Metric | Signal |
|---|---|---|
| Post-pandemic rebound | +14.2% permit volume YoY in 2024 | Sustained demand |
| Project value surge | +22.1% estimated value YoY | Large projects accelerating |
| New construction share | 31.4% of total, up 3.1 pp | Raw materials demand rising |
| Top growth market | Loop: +31.2% YoY | Commercial construction resurgence |
| Materials demand window | 6 to 9 month forward visibility | Procurement planning opportunity |

**Bottom line:** The shift toward new construction (which consumes 3 to 4x more raw materials than renovation) combined with the Loop's commercial resurgence creates a clear forward demand signal for building materials suppliers. A procurement team with this data in Q1 can start sourcing conversations in Q2 ahead of peak summer construction season.

---

## Setup

```bash
git clone https://github.com/skonasani/Chicago-Permits-Analysis.git
cd Chicago-Permits-Analysis
pip install -r Requirements.txt

# Pull data from Chicago Data Portal (free, no API key needed)
python notebooks/01_ingest.py
```

---

## Connection to professional experience

| This project | USG internship |
|---|---|
| Chicago Data Portal API ingestion | Oracle ERP data pipelines |
| SQL YoY and rolling average transforms | Power BI KPI reporting |
| Community area demand scoring | Vendor and budget KPI tracking |
| Materials demand forward signal | NPV and cost-benefit forecasting |
| Stakeholder-ready dashboard | Leadership reporting packages |

The methodology is the same. The data source is public instead of proprietary.

---

*Data: City of Chicago Data Portal, Building Permits dataset. All figures derived from public records.*

