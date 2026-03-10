# =========================================================
# 03_interpolate_total_pb_idw_leaflet.R
# Purpose:
#   - Interpolate total Pb concentrations in soil using IDW
#   - Overlay the interpolated surface on a DEM-derived hillshade
#   - Display the result in an interactive Leaflet map
#
# Required objects already in memory:
#   - pb_map
#   - samples_master
# =========================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(sf)
  library(terra)
  library(gstat)
  library(leaflet)
  library(scales)
  library(elevatr)
})

# ---------------------------------------------------------
# 0) Minimal checks
# ---------------------------------------------------------
if (!exists("pb_map")) stop("Object `pb_map` not found in memory.")
if (!exists("samples_master")) stop("Object `samples_master` not found in memory.")

# ---------------------------------------------------------
# 1) Convert Pb points to sf
# ---------------------------------------------------------
pb_sf <- st_as_sf(
  pb_map,
  coords = c("utm_x", "utm_y"),
  crs = 25830,
  remove = FALSE
)

# ---------------------------------------------------------
# 2) Interpolation area: bounding box
# ---------------------------------------------------------
bb <- st_bbox(pb_sf)

bb_poly <- st_as_sfc(bb) |>
  st_as_sf() |>
  st_set_crs(25830)

bb_vect <- terra::vect(bb_poly)

# ---------------------------------------------------------
# 2b) Download DEM
# ---------------------------------------------------------
dem_raw <- elevatr::get_elev_raster(
  locations = bb_poly,
  z = 12,
  clip = "locations"
)

dem <- terra::rast(dem_raw)

# ---------------------------------------------------------
# 3) Create base raster template
# ---------------------------------------------------------
r_template <- terra::rast(
  ext = terra::ext(bb_vect),
  resolution = 250,
  crs = "EPSG:25830"
)

# ---------------------------------------------------------
# 4) Continuous IDW interpolation in mg/kg
# ---------------------------------------------------------
grid_sf <- st_as_sf(terra::as.points(r_template, values = FALSE))

pb_sf$pb_vis <- pmin(pb_sf$pb, 2000)

idw_out <- gstat::idw(
  formula = pb_vis ~ 1,
  locations = pb_sf,
  newdata = grid_sf,
  idp = 3.0
)

# ---------------------------------------------------------
# 5) Convert prediction to raster
# ---------------------------------------------------------
grid_sf$pb_idw <- idw_out$var1.pred

xyz <- cbind(st_coordinates(grid_sf), pb_idw = grid_sf$pb_idw)

r_idw <- terra::rast(
  xyz,
  type = "xyz",
  crs = "EPSG:25830"
)

r_idw <- terra::crop(r_idw, bb_vect)

# ---------------------------------------------------------
# 6) Reproject to WGS84 for Leaflet
# ---------------------------------------------------------
r_idw_ll <- terra::project(r_idw, "EPSG:4326")
pb_sf_ll <- st_transform(pb_sf, 4326)

all_pts_sf <- st_as_sf(
  samples_master %>% filter(!is.na(utm_x), !is.na(utm_y)),
  coords = c("utm_x", "utm_y"),
  crs = 25830,
  remove = FALSE
) %>%
  st_transform(4326)

# ---------------------------------------------------------
# 6b) DEM and hillshade for Leaflet
# ---------------------------------------------------------
dem_ll <- terra::project(dem, "EPSG:4326")
dem_ll <- terra::crop(dem_ll, terra::ext(r_idw_ll))

# Optional: reduce resolution if rendering is too heavy
dem_ll <- terra::aggregate(dem_ll, fact = 2, fun = mean)

slp <- terra::terrain(dem_ll, v = "slope", unit = "radians")
asp <- terra::terrain(dem_ll, v = "aspect", unit = "radians")
hs  <- terra::shade(slp, asp, angle = 45, direction = 315)

# ---------------------------------------------------------
# 7) Pb visualization
# ---------------------------------------------------------
r_idw_plot <- terra::clamp(r_idw_ll, lower = 0, upper = 2000)

pal_raster <- colorNumeric(
  palette = c(
    "#2c7bb6",
    "#abd9e9",
    "#ffffbf",
    "#fdae61",
    "#d7191c"
  ),
  domain = c(0, 2000),
  na.color = "transparent"
)

# Grayscale palette for hillshade
pal_hs <- colorNumeric(
  palette = gray.colors(256, start = 0, end = 1),
  domain = values(hs),
  na.color = "transparent"
)

# ---------------------------------------------------------
# 8) Point styling by visual risk class
# ---------------------------------------------------------
point_col <- case_when(
  pb_sf_ll$pb < 1000 ~ "#2c7bb6",
  pb_sf_ll$pb < 2000 ~ "#fdae61",
  TRUE               ~ "#d7191c"
)

point_rad <- case_when(
  pb_sf_ll$pb < 1000 ~ 5,
  pb_sf_ll$pb < 2000 ~ 7,
  TRUE               ~ 9
)

id_col <- if ("sample_id" %in% names(pb_sf_ll)) "sample_id" else "codigo_lab"

labs <- paste0(
  "<b>", pb_sf_ll[[id_col]], "</b>",
  "<br>Total Pb: ", round(pb_sf_ll$pb, 2), " mg/kg"
)

# ---------------------------------------------------------
# 9) Leaflet map
# ---------------------------------------------------------
leaflet() %>%
  addProviderTiles(providers$CartoDB.Positron) %>%
  
  addRasterImage(
    hs,
    colors = pal_hs,
    opacity = 0.45,
    group = "Relief"
  ) %>%
  
  addRasterImage(
    r_idw_plot,
    colors = pal_raster,
    opacity = 0.60,
    group = "Interpolated Pb"
  ) %>%
  
  addCircleMarkers(
    data = all_pts_sf,
    lng = ~st_coordinates(geometry)[,1],
    lat = ~st_coordinates(geometry)[,2],
    radius = 2.5,
    stroke = FALSE,
    fillOpacity = 0.15,
    fillColor = "grey50",
    group = "All samples"
  ) %>%
  
  addCircleMarkers(
    data = pb_sf_ll,
    lng = ~st_coordinates(geometry)[,1],
    lat = ~st_coordinates(geometry)[,2],
    radius = point_rad,
    stroke = TRUE,
    weight = 0.7,
    color = "white",
    fillOpacity = 0.95,
    fillColor = point_col,
    popup = labs,
    group = "Soil Pb"
  ) %>%
  
  addLayersControl(
    overlayGroups = c("Relief", "Interpolated Pb", "All samples", "Soil Pb"),
    options = layersControlOptions(collapsed = FALSE)
  ) %>%
  
  addLegend(
    position = "bottomright",
    pal = pal_raster,
    values = c(0, 2000),
    title = "Interpolated Pb (mg/kg)",
    labFormat = labelFormat(suffix = " mg/kg"),
    opacity = 1
  )
