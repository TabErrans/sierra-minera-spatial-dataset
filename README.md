# Sierra Minera Soil Dataset – Spatial Pipeline

This repository contains the data integration pipeline used to construct a spatial master table of soil samples from the Sierra Minera mining district (Cartagena–La Unión, SE Spain).

The pipeline was developed to integrate heterogeneous laboratory datasets and historical spreadsheets associated with soil geochemistry studies of the mining district.

The resulting dataset enables reproducible spatial analysis and mapping of trace elements in soils of the Sierra Minera.

---

# Table of Contents

- Overview
- Context
- Workflow
- Script
- Data Availability
- Data Sources
- Status

---

# Overview

The purpose of this repository is to build a reproducible spatial dataset from heterogeneous soil geochemistry spreadsheets.

The pipeline performs the following steps:

1. Load heterogeneous Excel datasets  
2. Normalize field sample identifiers  
3. Extract UTM coordinates  
4. Resolve duplicated coordinate entries  
5. Build a reproducible spatial master table  

The resulting master table allows consistent spatial analysis of soil geochemistry data from the Sierra Minera.

---

# Context

The datasets originate from soil studies conducted in the Sierra Minera mining district.

Part of the material derives from laboratory datasets associated with research carried out by **José Matías Peñas Castejón** and collaborators.

The present pipeline reorganizes these heterogeneous sources into a reproducible spatial dataset suitable for open scientific analysis.

---

# Script

The main script of the pipeline is:

```

R/01_build_samples_master.R

```

This script builds the master table containing the following fields:

```

sample_id
type
number
utm_x
utm_y

```

The script loads multiple heterogeneous spreadsheets and harmonizes the identifiers and coordinates into a unified dataset.

---

# Data Availability

The raw soil geochemistry datasets used in this repository are archived in Zenodo:

https://doi.org/10.5281/zenodo.18940847

This repository contains the data integration pipeline used to construct a reproducible spatial master table from those original datasets.

---

# Data Sources

The pipeline integrates several heterogeneous laboratory spreadsheets and soil datasets associated with geochemical studies in the Sierra Minera mining district (Cartagena–La Unión, SE Spain).

The current repository processes data from the following source files:

- `Totales_Suelos.xlsx` — total elemental concentrations in soils  
- `DTPA_AGRICOLAS_NATURALES.xlsx` — DTPA-extractable trace elements in agricultural soils  
- `Suelos_Agricolas_Inma_UBM_BARGE_BCR.xlsx` — sequential extraction data (BCR method)  
- `TABLA_RESULTADOS_SUELOS_URBANOS.xlsx` — analytical results from urban soil samples  
- `Laboratorio_SYNALAB_todos_los_resultados_por_capa_sellado.xlsx` — laboratory reports with analytical results by soil layer  
- `ALEDO GUILLERMO BUENO.xls` — historical spreadsheet containing additional soil measurements  

These files originate from laboratory analyses and research datasets compiled during soil geochemistry studies of the Sierra Minera.

The material derives from datasets associated with research carried out by **José Matías Peñas Castejón** and collaborators.

The repository does not modify the original raw spreadsheets.  
Instead, the pipeline reads and harmonizes these heterogeneous sources to construct a reproducible spatial master dataset.

---

# Status

Initial data integration pipeline.

Future developments will include additional scripts to generate spatial objects and maps derived from the master dataset.
