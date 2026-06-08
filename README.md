## Quarterly Complaint Analysis Pipeline

### Overview

This project demonstrates an end-to-end R pipeline for analysing quarterly changes in customer complaint data.

It is designed to address a common problem in business intelligence:

> **In low-volume datasets with many categories, apparent trends are often driven by random variation rather than real change.**

The pipeline combines statistical testing and model-based estimation to distinguish meaningful shifts from noise, helping teams focus on changes that matter.

---

## Problem Context

Complaint reporting typically involves:
- multiple categories
- relatively low counts per category
- periodic (e.g. quarterly) comparisons

This can lead to over-interpretation of small changes and reactive decision-making. This project shows how statistical methods can improve judgement in these scenarios.

---

## Pipeline Structure

### `pipeline.R`
- Entry point for the workflow  
- Determines the current reporting quarter  
- Prevents duplicate runs  
- Locates and standardises the input file  
- Triggers the analysis script  
- Writes logs  

### `quarterly_analysis.R`

**Data Processing**
- Parses and validates input data  
- Applies basic data quality checks  
- Filters to the two most recent completed quarters  
- Prepares category and priority fields  

**Analysis 1 – Category Distribution**
- Compares category proportions between quarters  
- Uses chi-square testing and effect size  
- Calculates per-category changes with confidence intervals  

**Analysis 2 – Priority Shift Modelling**
- Models changes in complaint priority (Low / Medium / High)  
- Uses ordinal logistic regression  
- Applies bootstrap estimation  
- Identifies meaningful changes in higher-priority complaints  

---

## Example Dataset

The included dataset is synthetic and designed to mimic real-world complaint data:

- ~5000 records  
- 20 categories (including some low-frequency categories)  
- Uneven distribution across categories  
- Subtle shifts between quarters  

It also includes small data quality issues (e.g. missing values, future-dated record) to demonstrate robustness.

---

## Running the Pipeline

1. Clone the repository  
2. Ensure your working directory is the project root  
3. Ensure a dataset exists at `data/input_data.csv`  
4. Run:

```r
source("scripts/pipeline.R")
