# Dataset

This project uses the public **CMS Medicare Provider Fraud Detection** dataset.

**Source:** [Healthcare Provider Fraud Detection Analysis — Kaggle](https://www.kaggle.com/datasets/rohitrox/healthcare-provider-fraud-detection-analysis)

## Files Used

| File | Description |
|---|---|
| `Train-1542865627584.csv` | Provider-level fraud labels |
| `Train_Inpatientdata-1542865627584.csv` | Inpatient claims |
| `Train_Outpatientdata-1542865627584.csv` | Outpatient claims |
| `Train_Beneficiarydata-1542865627584.csv` | Beneficiary demographic and chronic condition data |

## Setup

1. Download the 4 CSV files from the Kaggle link above
2. Place them in a local `data/raw/` folder (excluded from version control via .gitignore)
3. Update `src/etl/config.py` → `SOURCE_DIR` to point at your local `data/raw/` path
4. Run the ETL pipeline as described in the main README
