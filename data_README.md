# Dataset

This project uses the public **CMS Medicare Provider Fraud Detection** dataset.

**Source:** [Healthcare Provider Fraud Detection Analysis — Kaggle](https://www.kaggle.com/datasets/rohitrox/healthcare-provider-fraud-detection-analysis)

## Files Used

| File | Description |
|---|---|
| `Train-*.csv` | Provider-level fraud labels |
| `Train_Inpatientdata-*.csv` | Inpatient claims |
| `Train_Outpatientdata-*.csv` | Outpatient claims |
| `Train_Beneficiarydata-*.csv` | Beneficiary demographic and chronic condition data |

## Setup

1. Download the 4 CSV files above from the Kaggle link.
2. Place them in a local `data/raw/` folder in this project (this folder is excluded from version control via `.gitignore`).
3. Update `src/etl/config.py` → `SOURCE_DIR` to point at your local `data/raw/` path.
4. Run the ETL pipeline as described in the main [README](../README.md#setup-instructions).

The dataset itself is not included in this repository, consistent with standard practice for projects built on third-party data — only the source link and processing code are provided.
