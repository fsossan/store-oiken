# Temporal Analysis: sc1_2040

**Analysis Date:** 28-May-2026 15:54:24

## SFOE Scenario Context

**Scenario:** Scénario 1 - Référence (ZÉRO Base)

**Planning Year:** 2040

### National Projections

| Indicator | Value |
|-----------|-------|
| National Population | 9970300 |
| PV Installed Capacity | 24070 MW |
| Total Installed Capacity | 45540 MW |
| EV Fleet | 2940 thousand vehicles |

### From Global to Local: Sion & Sierre

| Indicator | Value |
|-----------|-------|
| Population Sion & Sierre | 110103 |
| Population Share (national) | 1.10% |
| LV Networks in Portfolio | 1116 |
| Peak Demand Factor | 6% |
| Total Installed Demand (based on the demand factor) | 81.7 MW |
| Total PV Allocated to LV Networks | 288.4 MWp |
| Total EVs Allocated to LV Networks | 35242 vehicles |

## Summary Statistics

| Metric | Value |
|--------|-------|
| Networks Analyzed | 1036 |
| Total Demand of Analyzed Networks | 88.7 MW |
| Total PV of Analyzed Networks | 288.4 MWp |
| Total EVs of Analyzed Networks | 35242 |
| Fully Converged (all timesteps) | 1025 (98.9%) |
| Partial/Non-Converged | 11 |
| [Networks Requiring Reinforcement](temporal_reinforcement_sc1_2040.md) | [284 (27.4%)](temporal_reinforcement_sc1_2040.md) |
| [Networks Meeting Operational Goals](temporal_compliant_sc1_2040.md) | [752 (72.6%)](temporal_compliant_sc1_2040.md) |

## DER Hosting: Compliant vs Reinforcement Needed

| Indicator | Needs Reinforcement | Meets Operational Goals |
|-----------|--------------------|--------------------------|
| PV Capacity | 113.9 MWp (39.5%) | 174.5 MWp (60.5%) |
| EV Count | 13909 (39.5%) | 21333 (60.5%) |

> **Key insight:** Networks requiring reinforcement represent 27.4% of the portfolio but host 39.5% of allocated PV capacity and 39.5% of EVs — highlighting the correlation between DER penetration and grid stress.


## Violation Breakdown

| Violation Type | Networks Affected |
|----------------|-------------------|
| At least one violation | 284 (27.4%) |
| Undervoltage (<0.9 p.u.) | 147 |
| Overvoltage (>1.1 p.u.) | 45 |
| Line Overload (OL) | 263 |
| Transformer Congestion (TC) | 163 |

## Numerical Quality

- **Average LF convergence rate:** 99.8%
- **Minimum LF convergence rate:** 82.3%
- **Networks with partial non-convergence:** 11

> Networks with non-converging timesteps are flagged in the network tables.
