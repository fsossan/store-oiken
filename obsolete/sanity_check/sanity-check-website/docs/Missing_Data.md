# Missing Data

The OIKEN dataset contains gaps in several line parameters that are essential for load flow
analysis. This page describes the nature of these gaps and the methodology used to address them.

---

## Imputation Methodology

Missing line parameters — resistance (R), reactance (X), ampacity, and length are addressed
through a unified two-tier imputation approach applied during data preprocessing:

**Tier 1 — Cross-section available:**
When the cable cross-sectional area is known, the nearest matching entry in the lookup table
is used to fill missing R, X, and ampacity values. Note that copper (Cu) and aluminium (Al)
cables are not currently distinguished in the imputation and the match is based on cross-section
alone.

**Tier 2 — Cross-section missing:**
When the cross-sectional area is also absent, hardcoded default values are applied to all
missing electrical parameters.

**Length:**
Missing line lengths are always filled with a default value of 1 meter, regardless of whether
cross-section data is available, as length is not covered by the lookup table.

---

## Further Detail

| Document | Link |
|---|---|
| Line Parameter Summary | [View Summary](Line_parameter_summary.md) |
| Line Parameter Details | [View Details](Line_parameter_details.html) |
| Lookup Table | [View Lookup Table](lookup_table_avg.md) |
