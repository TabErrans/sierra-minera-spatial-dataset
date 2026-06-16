# ============================================================
# 1_map_pb_terrain_3d.R
#
# Objective:
#   - Render a reduced 3D terrain model of the Sierra Minera
#   - Overlay Pb sampling points
#   - Add official drainage network / ephemeral channels
#   - Export PNG snapshot and interactive HTML widget
# ============================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(sf)
  library(terra)
  library(rayshader)
  library(rgl)
  library(htmlwidgets)
})

# -------------------------
# 0) Configuration
# -------------------------
out_dir <- "outputs/maps_3d"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

crs_utm <- 25830
zscale_3d <- 10
agg_fact <- 4

hydrology_gpkg <- "data_raw/hydrology/IGR_HI_v1_ES070_Segura.gpkg"
hydrology_layer <- "hi_redtramo_l_es070"

png_out <- file.path(out_dir, "sierra_minera_terrain_3d_pb_points_ramblas.png")
html_out <- file.path(out_dir, "sierra_minera_terrain_3d_pb_points_ramblas.html")
legend_out <- file.path(out_dir, "sierra_minera_terrain_3d_pb_legend.png")

# -------------------------
# 1) Prepare Pb points
# -------------------------
pb_3d <- geo_total_elements_wide %>%
  filter(
    !is.na(Pb),
    Pb > 0,
    !is.na(utm_x),
    !is.na(utm_y),
    !is.na(elevation_m)
  ) %>%
  mutate(
    Pb_log = log10(Pb)
  )

pb_cols <- grDevices::hcl.colors(
  n = 100,
  palette = "YlOrRd",
  rev = FALSE
)

pb_index <- cut(
  pb_3d$Pb_log,
  breaks = 100,
  labels = FALSE,
  include.lowest = TRUE
)

point_cols <- pb_cols[pb_index]

# -------------------------
# 2) Build reduced terrain
# -------------------------
dem_3d_web <- terra::aggregate(
  dem_utm,
  fact = agg_fact,
  fun = mean,
  na.rm = TRUE
)

elmat_web <- rayshader::raster_to_matrix(dem_3d_web)

terrain_texture_web <- elmat_web %>%
  rayshader::sphere_shade(texture = "imhof1") %>%
  rayshader::add_shadow(
    rayshader::ray_shade(elmat_web, zscale = zscale_3d),
    0.5
  ) %>%
  rayshader::add_shadow(
    rayshader::ambient_shade(elmat_web),
    0.5
  )

# -------------------------
# 3) Load and crop official drainage network
# -------------------------
drainage <- sf::st_read(
  hydrology_gpkg,
  layer = hydrology_layer,
  quiet = TRUE
) %>%
  sf::st_transform(crs_utm)

dem_bbox <- sf::st_as_sfc(
  sf::st_bbox(
    c(
      xmin = terra::xmin(dem_3d_web),
      xmax = terra::xmax(dem_3d_web),
      ymin = terra::ymin(dem_3d_web),
      ymax = terra::ymax(dem_3d_web)
    ),
    crs = sf::st_crs(crs_utm)
  )
)

drainage_clip <- sf::st_crop(drainage, dem_bbox)

drainage_lines <- drainage_clip %>%
  sf::st_cast("MULTILINESTRING", warn = FALSE) %>%
  sf::st_cast("LINESTRING", warn = FALSE)

message("Drainage lines: ", nrow(drainage_lines))
message("Pb points: ", nrow(pb_3d))

# -------------------------
# 4) Export Pb legend as PNG
# -------------------------
png(
  filename = legend_out,
  width = 900,
  height = 300,
  res = 120
)

par(mar = c(4, 5, 3, 2))

legend_breaks <- pretty(pb_3d$Pb_log, n = 6)
legend_cols <- grDevices::hcl.colors(
  n = length(legend_breaks) - 1,
  palette = "YlOrRd",
  rev = FALSE
)

plot(
  NA,
  xlim = range(legend_breaks),
  ylim = c(0, 1),
  yaxt = "n",
  ylab = "",
  xlab = "log10(Pb concentration, mg/kg)",
  main = "Pb concentration colour scale"
)

for (i in seq_len(length(legend_breaks) - 1)) {
  rect(
    xleft = legend_breaks[i],
    xright = legend_breaks[i + 1],
    ybottom = 0,
    ytop = 1,
    col = legend_cols[i],
    border = NA
  )
}

axis(1, at = legend_breaks)
box()

dev.off()

# -------------------------
# 5) Open 3D scene
# -------------------------
rgl::open3d()
rgl::clear3d()

rayshader::plot_3d(
  hillshade = terrain_texture_web,
  heightmap = elmat_web,
  zscale = zscale_3d,
  windowsize = c(1200, 900),
  zoom = 0.75,
  phi = 45,
  theta = 35,
  background = "white",
  shadow = TRUE
)

# -------------------------
# 6) Draw drainage network as 3D paths
# -------------------------
for (i in seq_len(nrow(drainage_lines))) {
  
  coords_i <- sf::st_coordinates(drainage_lines[i, ]) %>%
    as.data.frame() %>%
    transmute(
      utm_x = X,
      utm_y = Y
    )
  
  if (nrow(coords_i) < 2) next
  
  coords_vect <- terra::vect(
    coords_i,
    geom = c("utm_x", "utm_y"),
    crs = paste0("EPSG:", crs_utm)
  )
  
  coords_i$elevation_m <- terra::extract(
    dem_3d_web,
    coords_vect
  )[, 2]
  
  coords_i <- coords_i %>%
    filter(!is.na(elevation_m))
  
  if (nrow(coords_i) < 2) next
  
  rayshader::render_path(
    extent = terra::ext(dem_3d_web),
    lat = coords_i$utm_y,
    long = coords_i$utm_x,
    altitude = coords_i$elevation_m + 6,
    zscale = zscale_3d,
    color = "deepskyblue2",
    linewidth = 3
  )
}

# -------------------------
# 7) Draw Pb sampling points
# -------------------------
rayshader::render_points(
  extent = terra::ext(dem_3d_web),
  lat = pb_3d$utm_y,
  long = pb_3d$utm_x,
  altitude = pb_3d$elevation_m + 12,
  zscale = zscale_3d,
  size = 12,
  color = point_cols
)

# -------------------------
# 8) Export snapshot and interactive widget
# -------------------------
rayshader::render_snapshot(
  filename = png_out,
  clear = FALSE
)

htmlwidgets::saveWidget(
  widget = rgl::rglwidget(),
  file = html_out,
  selfcontained = TRUE
)

message("Saved PNG: ", png_out)
message("Saved HTML widget: ", html_out)
message("Saved Pb legend: ", legend_out)
