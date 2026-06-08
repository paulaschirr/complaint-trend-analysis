## Quarterly Complaint Analysis Pipeline

### Overview

In high‑stakes, low‑volume datasets, over‑interpreting changes is a real business risk. Apparent trends often reflect natural variation rather than genuinely significant shifts, but can still drive decisions and actions. This project demonstrates an end-to-end R pipeline for analysing quarterly changes in customer complaint data. It applies statistical testing and model‑based estimation to distinguish meaningful change from noise, helping teams focus on genuine shifts in complaint categories and medium+ risks.


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


## Output
The pipeline produces two datasets:
- Category distribution changes  
- Priority shift (model-based and observed)

These outputs are designed to be consumed directly by reporting tools.


## Integration with Reporting

The pipeline is designed to integrate upstream of any analytics or reporting platform.

It can:
- run independently (e.g. scheduled via a VM or task scheduler)
- run within a platform (e.g. Microsoft Fabric)

Outputs are written as simple CSV files, allowing downstream tools (Power BI, Tableau, etc.) to pick them up for visualisation without transformation.


## Example Dataset

The included dataset is synthetic and designed to mimic real-world complaint data:

- ~5000 records  
- 20 categories (including some low-frequency categories)  
- Uneven distribution across categories  
- Subtle shifts between quarters  

It also includes small data quality issues (e.g. missing values, future-dated record) to demonstrate robustness.

## Example Interpretation

The charts below have been created using the output data from this pipeline and illustrate how observed changes can differ from statistically meaningful changes.

### Category Shifts

![Category Shifts](plot_cat.png)

- Some categories change slightly quarter-to-quarter, but most differences fall within expected random variation.  
- Only **Service Quality** shows a statistically significant increase, suggesting a genuine shift in the underlying category mix.  
- Other movements (e.g. a decrease in **Billing Issues**) may appear notable but are likely noise.

### Priority Shifts (Medium+ Complaints)

![Priority Shifts](plot_risk.png)

- Several categories show noteworthy increases or decreases in higher-priority complaints (e.g. **Fraud/Scam Concerns**).  
- However, large confidence intervals indicate high uncertainty due to the low number of records per category, meaning the statistical model indicates that all except one are likely due to natural fluctuation.
- Only **Technical Errors** shows a statistically meaningful increase in medium+ priority complaints.


### Key Takeaway

Not all observed changes are meaningful. This approach helps distinguish **real shifts** that warrant investigation from **random variation** that should not drive decisions. 

By combining observed data with model-based uncertainty, the pipeline reduces the risk of overinterpreting noise in low-volume, multi-category datasets. This highlights meaningful changes while avoiding overinterpretation of variation that is likely just noise.

## Running the Pipeline

1. Clone the repository  
2. Ensure your working directory is the project root  
3. Ensure a dataset exists at `data/input_data.csv`  
4. Run:

```r
source("scripts/pipeline.R")
```

### Dependencies
Packages dplyr, tidyr & MASS

