# Sierra Minera Soil Dataset – Spatial Pipeline

This repository contains the data integration pipeline used to construct a spatial master table of soil samples from the Sierra Minera (Cartagena–La Unión, SE Spain).

The pipeline was developed to integrate heterogeneous laboratory datasets and historical spreadsheets associated with soil geochemistry studies of the mining district.

The workflow:

1. Load heterogeneous Excel datasets
2. Normalize field sample identifiers
3. Extract UTM coordinates
4. Resolve duplicated coordinate entries
5. Build a reproducible spatial master table

The resulting dataset enables reproducible spatial analysis and mapping of trace elements in soils of the Sierra Minera.

---

## Context

The datasets originate from soil studies conducted in the Sierra Minera mining district.

Part of the material derives from laboratory datasets associated with research carried out by **José Matías** and collaborators.

The present pipeline reorganizes these heterogeneous sources into a reproducible spatial dataset suitable for open scientific analysis.

---

## Script

R/01_build_samples_master.R

Builds the master table:


sample_id
type
number
utm_x
utm_y


---

## Status

Initial data integration pipeline.
Further scripts will generate spatial objects and maps from the master dataset.
