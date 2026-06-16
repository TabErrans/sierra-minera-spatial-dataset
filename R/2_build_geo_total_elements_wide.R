# ============================================================
# 0_build_geo_total_elements_wide.R
#
# Objective:
#   - Load or create samples_master
#   - Add elevation values from a DEM
#   - Load total_elements_wide
#   - Join coordinates, elevation and total metal concentrations
# ============================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(sf)
  library(terra)
  library(elevatr)
})

# -------------------------
# 0) Configuration
# -------------------------
crs_utm <- 25830

dir.create("data_processed", showWarnings = FALSE)

# -------------------------
# 1) Load or create samples_master
# -------------------------
if (file.exists("data_processed/samples_master.csv")) {
  
  samples_master <- readr::read_csv(
    "data_processed/samples_master.csv",
    show_col_types = FALSE
  )
  
} else {
  
  source("scripts/0_build_samples_master.R")
  
  readr::write_csv(
    samples_master,
    "data_processed/samples_master.csv"
  )
}

# Keep only samples with valid coordinates for spatial analyses
samples_master <- samples_master %>%
  filter(has_coords)

# -------------------------
# 2) Add elevation values
# -------------------------
samples_sf <- samples_master %>%
  sf::st_as_sf(
    coords = c("utm_x", "utm_y"),
    crs = crs_utm,
    remove = FALSE
  )

area_wgs84 <- samples_sf %>%
  sf::st_union() %>%
  sf::st_buffer(1500) %>%
  sf::st_bbox() %>%
  sf::st_as_sfc() %>%
  sf::st_sf(crs = crs_utm) %>%
  sf::st_transform(4326)

dem <- elevatr::get_elev_raster(
  locations = area_wgs84,
  z = 12,
  clip = "locations"
)

dem_utm <- terra::project(
  terra::rast(dem),
  paste0("EPSG:", crs_utm)
)

samples_vect <- terra::vect(
  samples_master,
  geom = c("utm_x", "utm_y"),
  crs = paste0("EPSG:", crs_utm)
)

elev <- terra::extract(
  dem_utm,
  samples_vect
)

samples_geo <- samples_master %>%
  mutate(
    elevation_m = elev[[2]]
  )

readr::write_csv(
  samples_geo,
  "data_processed/samples_geo.csv"
)

# -------------------------
# 3) Load total elements table
# -------------------------
total_elements_wide <- readr::read_csv(
  "data_processed/total_elements_wide.csv",
  show_col_types = FALSE
)

if (!"sample_id" %in% names(total_elements_wide)) {
  stop(
    "total_elements_wide.csv does not contain a sample_id column. ",
    "Please check the column names."
  )
}

# -------------------------
# 4) Join geospatial data and chemistry
# -------------------------
geo_total_elements_wide <- samples_geo %>%
  left_join(total_elements_wide, by = "sample_id") %>%
  arrange(type, number)

# -------------------------
# 5) Save outputs
# -------------------------
readr::write_csv(
  geo_total_elements_wide,
  "data_processed/geo_total_elements_wide.csv"
)

saveRDS(
  geo_total_elements_wide,
  "data_processed/geo_total_elements_wide.rds"
)

# -------------------------
# 6) Console summary
# -------------------------
message("=== GEO + TOTAL ELEMENTS WIDE ===")
message("Rows: ", nrow(geo_total_elements_wide))
message("Samples with coordinates: ", sum(geo_total_elements_wide$has_coords, na.rm = TRUE))
message("Samples with elevation: ", sum(!is.na(geo_total_elements_wide$elevation_m)))
message("Columns: ", ncol(geo_total_elements_wide))

print(names(geo_total_elements_wide))
