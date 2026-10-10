# One-shot Loadflow Analysis Results

_Combined analysis of all LV networks_

## Overall Summary

- **Networks analyzed:** 1081
- **Total load:** 87 MW

## Network Classification

### Convergence Status

- **Converged:** 1058 (97.9%) → [📋 View list](converged_networks.md)
- **Non-converged:** 23 (2.1%) → [📋 View list](non_converged_networks.md)
- **Converged load:** 84 MW

### Converged Network Health

- **✅ Healthy networks:** 856 (80.9%) → [📋 View list](healthy_networks.md)
- **⚠️ Networks with violations:** 202 (19.1%) → [📋 View list](violation_networks.md)
  - Load affected: 27 MW (32.4% of converged load)

## Convergence Statistics

**Iterations to converge:**

- Mean: 7.8
- Median: 8
- Maximum: 40

## Voltage Quality

### Network-Level Statistics

- **Mean minimum voltage:** 0.960 p.u.
- **Lowest voltage:** 0.565 p.u.
- **Mean maximum voltage:** 1.000 p.u.
- **Highest voltage:** 1.000 p.u.

### Voltage Violations

| Severity | Threshold | Networks | Percentage |
|----------|-----------|----------|------------|
| 🔴 Critical Low | < 0.9 p.u. | 106 | 10.0% |
| 🟡 Warning Low | 0.9-0.95 p.u. | 177 | 16.7% |
| 🟡 Warning High | 1.05-1.1 p.u. | 0 | 0.0% |
| 🔴 Critical High | > 1.1 p.u. | 0 | 0.0% |

## Line Overloads

### Network-Level

- **Networks with overloaded lines:** 172 (16.3%)
- **Networks with severe overloads (>110%):** 155 (14.7%)
- **Networks with critical overloads (>120%):** 127 (12.0%)

### Line-Level

- **Total overloaded lines:** 422 (6.6% of all lines)
- **Average overloads per affected network:** 2.5

## System Losses

- **Total losses:** 2779 kW (3.3% of load)
- **Average per network:** 3.0 kW
- **Median per network:** 1.1 kW
- **Maximum per network:** 66.5 kW

## Visualizations

![Loadflow Analysis](One_shot_loadflow_analysis.png)

## Top Problem Networks

### Top 10 Networks by Voltage Drop

| Rank | Network ID | Min Voltage (p.u.) | Voltage Drop (p.u.) | Overloaded Lines |
|------|------------|-------------------|---------------------|------------------|
| 1 | 570 | 0.565 | 0.435 | 4 |
| 2 | 442 | 0.586 | 0.414 | 10 |
| 3 | 5490 | 0.589 | 0.411 | 6 |
| 4 | 617 | 0.627 | 0.373 | 11 |
| 5 | 89685 | 0.677 | 0.323 | 7 |
| 6 | 350 | 0.678 | 0.322 | 4 |
| 7 | 619 | 0.702 | 0.298 | 12 |
| 8 | 308 | 0.704 | 0.296 | 4 |
| 9 | 93 | 0.715 | 0.285 | 2 |
| 10 | 407 | 0.724 | 0.276 | 4 |

### Top 10 Networks by Line Overloads

| Rank | Network ID | Overloaded Lines | Max Current (p.u.) | Min Voltage (p.u.) |
|------|------------|------------------|-------------------|--------------------|
| 1 | 554 | 14 | 2.07 | 0.831 |
| 2 | 619 | 12 | 6.43 | 0.702 |
| 3 | 617 | 11 | 2.84 | 0.627 |
| 4 | 442 | 10 | 3.02 | 0.586 |
| 5 | 74 | 8 | 1.90 | 0.769 |
| 6 | 468 | 8 | 1.57 | 0.881 |
| 7 | 392 | 7 | 1.48 | 0.763 |
| 8 | 89685 | 7 | 5.73 | 0.677 |
| 9 | 543 | 6 | 1.87 | 0.819 |
| 10 | 553 | 6 | 1.85 | 0.727 |

### Top 10 Networks by Lowest Voltage

| Rank | Network ID | Min Voltage (p.u.) | Voltage Drop (p.u.) | Overloaded Lines |
|------|------------|-------------------|---------------------|------------------|
| 1 | 570 | 0.565 | 0.435 | 4 |
| 2 | 442 | 0.586 | 0.414 | 10 |
| 3 | 5490 | 0.589 | 0.411 | 6 |
| 4 | 617 | 0.627 | 0.373 | 11 |
| 5 | 89685 | 0.677 | 0.323 | 7 |
| 6 | 350 | 0.678 | 0.322 | 4 |
| 7 | 619 | 0.702 | 0.298 | 12 |
| 8 | 308 | 0.704 | 0.296 | 4 |
| 9 | 93 | 0.715 | 0.285 | 2 |
| 10 | 407 | 0.724 | 0.276 | 4 |

### Top 10 Networks by Highest Current

| Rank | Network ID | Max Current (p.u.) | Overloaded Lines | Min Voltage (p.u.) |
|------|------------|-------------------|------------------|--------------------|
| 1 | 407 | 7.56 | 4 | 0.724 |
| 2 | 279 | 6.46 | 1 | 1.000 |
| 3 | 619 | 6.43 | 12 | 0.702 |
| 4 | 348 | 6.28 | 1 | 0.996 |
| 5 | 89685 | 5.73 | 7 | 0.677 |
| 6 | 570 | 5.73 | 4 | 0.565 |
| 7 | 474 | 5.57 | 3 | 0.834 |
| 8 | 92432 | 5.34 | 1 | 0.971 |
| 9 | 615 | 5.34 | 6 | 0.843 |
| 10 | 565 | 5.23 | 2 | 0.750 |

---

*Report generated: 13-Mar-2026 18:14:19*
