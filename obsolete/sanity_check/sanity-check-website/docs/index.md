# OIKEN LV Network Sanity Check

---

## Overview

This documentation presents the results of an automated analysis of **1116 low-voltage (LV)
distribution networks** across the Sion and Sierre regions operated by OIKEN.

The analysis pipeline covers three sequential stages:

| Stage | Description |
|---|---|
| **1. Power Mix Analysis** | Pre-load flow characterization of DER penetration and loading |
| **2. One-Shot Load Flow** | Single-snapshot load flow validation under maximum loading |
| **3. Temporal Load Flow** | Time-series loadflow validation based on SFOE scenarios |

---

## Results

### Stage 1 — Power Mix Analysis

Pre-load flow statistics on network loading and distributed energy resource (DER) penetration,
based on the applied coincidence factors across all LV networks.

| Report | Link |
|---|---|
| Power Mix Analysis — All LV Networks | [View Report](all_LV_grid_power_mix_analysis.md) |

---

### Stage 2 — One-Shot Load Flow

One-shot load flow results under maximum loading conditions across all LV networks.
Networks that fail to converge or show violations in operational limits (nodal voltages, line amperage and transformer congestion) are flagged for further analysis.

| Report | Link |
|---|---|
| Load Flow Results — All LV Networks | [View Report](oneshot_lf_all_LV_networks.md) |
| Statistical Analysis | [View Analysis](One_shot_loadflow_analysis.md) |

---

### Stage 3 — Temporal Load Flow

Time-series load flow simulations at **15-minute resolution** using SFOE electricity
framework scenarios. Simulations are performed on networks that passed the one-shot load flow.

> **Scenario:** sc1_2040 — Scénario 1 - Référence (ZÉRO Base)
> **Year:** 2040 &nbsp;|&nbsp; **PV:** 24070 MW &nbsp;|&nbsp; **EV:** 2940 thousand units &nbsp;|&nbsp; 

| Report | Link |
|---|---|
| Temporal Load Flow Results | [sc1_2040 Report](temporal_analysis_sc1_2040.md) |

---

## Methodology

### Coincidence Factors

The maximum rated fuse current serves as the basis for network loading.
The following coincidence factors are applied as advised by OIKEN:

| Parameter | Factor |
|---|---|
| Demand | 0.06 |
| Generation (PV) | 0.00 |

### Missing Line Parameters Overview

Line characteristics and ampacity ratings absent from the OIKEN dataset have been
identified, compiled, and resolved using a lookup table approach.

| Document | Link |
|---|---|
| Missing Data Report | [View Report](Missing_Data.md) |

### Substation & Transformer Overview

Network-level substation characteristics including transformer counts, installed
capacity, and data quality flags across all LV networks.

| Document | Link |
|---|---|
| Substation Summary & Details | [View Report](Substation_summary.md) |
| Transformer Parameter Analysis | [View Report](Transformer_summary.md) |
| Transformer Parameter Details | [View Details](Transformer_details.md) |

---

## How to Navigate This Documentation

- Use the **stage links above** to explore results in sequence.
- **Network Search:** Enter a network ID in the search bar to locate a specific substation.
- **Voltage Violation Search:** Enter a voltage threshold (p.u.) to identify networks
  with under-voltage violations below that value.
