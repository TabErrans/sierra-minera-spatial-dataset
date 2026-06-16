# Script code guide

This project uses thematic script codes rather than a strict linear workflow.
The numbering does not necessarily indicate execution order.
Instead, it groups scripts by function within the project.

## Code families

### 0_ Core / master / harmonization
Scripts for raw data loading, cleaning, harmonization, sample ID normalization,
coordinate resolution, and construction of shared master tables.

Examples:
- 0_build_samples_master.R

### 1_ Mapping / spatial visualization
Scripts for spatial products, maps, raster generation, IDW interpolation,
Leaflet outputs, and terrain-related visualization.

Examples:
- 1_map_total_elements_leaflet.R
- 1_idw_total_elements_leaflet.R

### 2_ Database / structured exports
Scripts for building database-oriented outputs from the master tables,
including exportable tabular structures for reuse in analysis, QA/QC,
and future integration.

Examples:
- 2_build_database_exports.R

### 8_ Exploratory / sandbox / temporary
Experimental scripts, tests, prototypes, or intermediate work that may be useful
but is not yet considered part of the stable workflow.

Examples:
- 8_test_coordinates.R
- 8_tmp_pb_surface.R

### 9_ Legacy / deprecated
Older scripts preserved for traceability, comparison, or historical reference.
These are not the preferred current workflow.

Examples:
- 9_legacy_arable.R
- 9_legacy_map_pb.R
- 9_legacy_raster_pb.R

## Naming convention

Pattern:

`[code]_[verb]_[object].R`

Examples:
- 0_build_samples_master.R
- 1_map_total_elements_leaflet.R
- 1_idw_total_elements_leaflet.R
- 2_build_database_exports.R
- 9_legacy_arable.R

## Notes

- Codes indicate script family, not mandatory execution order.
- The workflow is modular and may branch into multiple directions.
- New scripts should be assigned to the family that best reflects their role.
- If a script becomes outdated but is still worth keeping, move it to code 9_.
