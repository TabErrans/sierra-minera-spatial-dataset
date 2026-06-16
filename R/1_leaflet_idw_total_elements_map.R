# =========================================================
# Interpolate total soil elements with IDW + hillshade
# Purpose:
#   - Interpolate total element concentrations in soil using IDW
#   - Overlay interpolated surfaces on a DEM-derived hillshade
#   - Display the result in an interactive Leaflet map
#
# Required objects already in memory:
#   - element_map   (long table with: sample_id, utm_x, utm_y, element, label, value)
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
  library(purrr)
  library(tibble)
})

# ---------------------------------------------------------
# 0) User settings
# ---------------------------------------------------------
elements <- c("Pb", "Zn", "As", "Cd")

element_config <- tibble::tribble(
  ~element, ~label,      ~threshold, ~upper_cap, ~unit,
  "Pb",     "Total Pb",  1000,       2000,       "mg/kg",
  "Zn",     "Total Zn",  1000,       2000,       "mg/kg",
  "As",     "Total As",  100,        200,        "mg/kg",
  "Cd",     "Total Cd",  10,         20,         "mg/kg"
)

# interpolation parameters
dem_zoom   <- 12
grid_res   <- 250
idp_power  <- 3.0
dem_agg    <- 2

# ---------------------------------------------------------
# 1) Minimal checks
# ---------------------------------------------------------
if (!exists("element_map")) stop("Object `element_map` not found in memory.")
if (!exists("samples_master")) stop("Object `samples_master` not found in memory.")

required_cols <- c("sample_id", "utm_x", "utm_y", "element", "label", "value")
stopifnot(all(required_cols %in% names(element_map)))
stopifnot(all(c("sample_id", "utm_x", "utm_y") %in% names(samples_master)))

missing_elements <- setdiff(elements, element_config$element)
if (length(missing_elements) > 0) {
  stop("Missing configuration for: ", paste(missing_elements, collapse = ", "))
}

element_map_use <- element_map %>%
  filter(element %in% elements) %>%
  filter(!is.na(utm_x), !is.na(utm_y), !is.na(value))

if (nrow(element_map_use) == 0) {
  stop("No rows available in `element_map` for requested elements.")
}

cat("Points by element:\n")
print(element_map_use %>% count(element, sort = TRUE))

# ---------------------------------------------------------
# 2) Global interpolation area from all selected elements
# ---------------------------------------------------------
all_points_sf <- st_as_sf(
  element_map_use,
  coords = c("utm_x", "utm_y"),
  crs = 25830,
  remove = FALSE
)

bb <- st_bbox(all_points_sf)

bb_poly <- st_as_sfc(bb) |>
  st_as_sf() |>
  st_set_crs(25830)

bb_vect <- terra::vect(bb_poly)

# ---------------------------------------------------------
# 3) Download DEM once
# ---------------------------------------------------------
dem_raw <- elevatr::get_elev_raster(
  locations = bb_poly,
  z = dem_zoom,
  clip = "locations"
)

dem <- terra::rast(dem_raw)

# ---------------------------------------------------------
# 4) Base raster template
# ---------------------------------------------------------
r_template <- terra::rast(
  ext = terra::ext(bb_vect),
  resolution = grid_res,
  crs = "EPSG:25830"
)

grid_sf <- st_as_sf(terra::as.points(r_template, values = FALSE))

# ---------------------------------------------------------
# 5) Build hillshade once
# ---------------------------------------------------------
dem_ll <- terra::project(dem, "EPSG:4326")
dem_ll <- terra::aggregate(dem_ll, fact = dem_agg, fun = mean)

slp <- terra::terrain(dem_ll, v = "slope", unit = "radians")
asp <- terra::terrain(dem_ll, v = "aspect", unit = "radians")
hs  <- terra::shade(slp, asp, angle = 45, direction = 315)

pal_hs <- colorNumeric(
  palette = gray.colors(256, start = 0, end = 1),
  domain = values(hs),
  na.color = "transparent"
)

# ---------------------------------------------------------
# 6) All coordinates as grey background layer
# ---------------------------------------------------------
all_samples_sf <- st_as_sf(
  samples_master %>% filter(!is.na(utm_x), !is.na(utm_y)),
  coords = c("utm_x", "utm_y"),
  crs = 25830,
  remove = FALSE
) %>%
  st_transform(4326)

# ---------------------------------------------------------
# 7) Helper: interpolate one element
# ---------------------------------------------------------
interpolate_element <- function(df_el, cfg_row, grid_sf, bb_vect) {
  
  el_code    <- cfg_row$element[[1]]
  label_txt  <- cfg_row$label[[1]]
  threshold  <- cfg_row$threshold[[1]]
  upper_cap  <- cfg_row$upper_cap[[1]]
  unit_txt   <- cfg_row$unit[[1]]
  
  if (nrow(df_el) < 3) {
    warning("Skipping ", el_code, ": fewer than 3 points.")
    return(NULL)
  }
  
  pts_sf <- st_as_sf(
    df_el,
    coords = c("utm_x", "utm_y"),
    crs = 25830,
    remove = FALSE
  )
  
  pts_sf$value_vis <- pmin(pts_sf$value, upper_cap)
  
  idw_out <- gstat::idw(
    formula = value_vis ~ 1,
    locations = pts_sf,
    newdata = grid_sf,
    idp = idp_power
  )
  
  grid_out <- grid_sf
  grid_out$pred <- idw_out$var1.pred
  
  xyz <- cbind(st_coordinates(grid_out), pred = grid_out$pred)
  
  r_idw <- terra::rast(
    xyz,
    type = "xyz",
    crs = "EPSG:25830"
  )
  
  r_idw <- terra::crop(r_idw, bb_vect)
  r_idw_ll <- terra::project(r_idw, "EPSG:4326")
  r_idw_plot <- terra::clamp(r_idw_ll, lower = 0, upper = upper_cap)
  
  pts_ll <- st_transform(pts_sf, 4326)
  
  point_col <- case_when(
    pts_ll$value < threshold ~ "#2c7bb6",
    pts_ll$value < upper_cap ~ "#fdae61",
    TRUE                     ~ "#d7191c"
  )
  
  point_rad <- case_when(
    pts_ll$value < threshold ~ 5,
    pts_ll$value < upper_cap ~ 7,
    TRUE                     ~ 9
  )
  
  labs <- paste0(
    "<b>", pts_ll$sample_id, "</b>",
    "<br>", label_txt, ": ", round(pts_ll$value, 2), " ", unit_txt
  )
  
  pal_raster <- colorNumeric(
    palette = c("#2c7bb6", "#abd9e9", "#ffffbf", "#fdae61", "#d7191c"),
    domain = c(0, upper_cap),
    na.color = "transparent"
  )
  
  list(
    element     = el_code,
    label       = label_txt,
    threshold   = threshold,
    upper_cap   = upper_cap,
    unit        = unit_txt,
    points_sf   = pts_ll,
    point_col   = point_col,
    point_rad   = point_rad,
    point_labs  = labs,
    raster      = r_idw_plot,
    pal_raster  = pal_raster
  )
}

# ---------------------------------------------------------
# 8) Build interpolation products for all elements
# ---------------------------------------------------------
element_layers <- map(
  elements,
  function(el) {
    cfg <- element_config %>% filter(element == el) %>% slice(1)
    df_el <- element_map_use %>% filter(element == el)
    
    interpolate_element(
      df_el    = df_el,
      cfg_row  = cfg,
      grid_sf  = grid_sf,
      bb_vect  = bb_vect
    )
  }
)

names(element_layers) <- elements
element_layers <- compact(element_layers)

if (length(element_layers) == 0) {
  stop("No element layers could be built.")
}

# ---------------------------------------------------------
# 9) Build Leaflet map + dynamic legend
# ---------------------------------------------------------

# Active config only for elements successfully interpolated
active_cfg <- element_config %>%
  filter(element %in% names(element_layers))

# Group names
overlay_groups <- c(
  "Relief",
  "All samples",
  unlist(map(active_cfg$element, ~c(
    paste0("Interpolated ", .x),
    paste0("Soil ", .x)
  )))
)

# Base map
map_obj <- leaflet() %>%
  addProviderTiles(providers$CartoDB.Positron) %>%
  addRasterImage(
    hs,
    colors = pal_hs,
    opacity = 0.45,
    group = "Relief"
  ) %>%
  addCircleMarkers(
    data = all_samples_sf,
    lng = ~st_coordinates(geometry)[,1],
    lat = ~st_coordinates(geometry)[,2],
    radius = 2.5,
    stroke = FALSE,
    fillOpacity = 0.15,
    fillColor = "grey50",
    group = "All samples"
  )

# Add element layers
for (el in names(element_layers)) {
  obj <- element_layers[[el]]
  
  raster_group <- paste0("Interpolated ", el)
  point_group  <- paste0("Soil ", el)
  
  map_obj <- map_obj %>%
    addRasterImage(
      obj$raster,
      colors = obj$pal_raster,
      opacity = 0.60,
      group = raster_group
    ) %>%
    addCircleMarkers(
      data = obj$points_sf,
      lng = ~st_coordinates(geometry)[,1],
      lat = ~st_coordinates(geometry)[,2],
      radius = obj$point_rad,
      stroke = TRUE,
      weight = 0.7,
      color = "white",
      fillOpacity = 0.95,
      fillColor = obj$point_col,
      popup = obj$point_labs,
      group = point_group
    )
}

# Hide all thematic layers except first element
if (nrow(active_cfg) > 1) {
  first_el <- active_cfg$element[[1]]
  
  groups_to_hide <- unlist(map(active_cfg$element[-1], ~c(
    paste0("Interpolated ", .x),
    paste0("Soil ", .x)
  )))
  
  for (grp in groups_to_hide) {
    map_obj <- hideGroup(map_obj, grp)
  }
}

# Legend HTML builder
build_interp_legend_html <- function(label_txt, el_code, threshold, upper_cap, unit_txt) {
  as.character(
    htmltools::tags$div(
      style = paste(
        "background: white;",
        "padding: 8px 10px;",
        "border: 1px solid #ccc;",
        "border-radius: 4px;",
        "box-shadow: 0 1px 4px rgba(0,0,0,0.2);",
        "font-size: 12px;",
        "line-height: 1.4;"
      ),
      htmltools::HTML(
        paste0("<strong>", label_txt, "</strong><br>")
      ),
      htmltools::tags$div(
        htmltools::tags$i(
          style = "background:#2c7bb6;width:12px;height:12px;display:inline-block;margin-right:6px;"
        ),
        paste0("low")
      ),
      htmltools::tags$div(
        htmltools::tags$i(
          style = "background:#abd9e9;width:12px;height:12px;display:inline-block;margin-right:6px;"
        ),
        "moderate-low"
      ),
      htmltools::tags$div(
        htmltools::tags$i(
          style = "background:#ffffbf;width:12px;height:12px;display:inline-block;margin-right:6px;"
        ),
        "moderate"
      ),
      htmltools::tags$div(
        htmltools::tags$i(
          style = "background:#fdae61;width:12px;height:12px;display:inline-block;margin-right:6px;"
        ),
        paste0("high (< ", upper_cap, " ", unit_txt, ")")
      ),
      htmltools::tags$div(
        htmltools::tags$i(
          style = "background:#d7191c;width:12px;height:12px;display:inline-block;margin-right:6px;"
        ),
        paste0("capped at ", upper_cap, " ", unit_txt)
      ),
      htmltools::tags$hr(style = "margin:6px 0;"),
      htmltools::tags$div(
        htmltools::HTML("<strong>Point classes</strong>")
      ),
      htmltools::tags$div(
        htmltools::tags$span(
          style = "display:inline-block;width:12px;height:12px;border-radius:50%;background:#2c7bb6;margin-right:6px;"
        ),
        paste0("< ", threshold, " ", unit_txt)
      ),
      htmltools::tags$div(
        htmltools::tags$span(
          style = "display:inline-block;width:12px;height:12px;border-radius:50%;background:#fdae61;margin-right:6px;"
        ),
        paste0(threshold, "–", upper_cap, " ", unit_txt)
      ),
      htmltools::tags$div(
        htmltools::tags$span(
          style = "display:inline-block;width:12px;height:12px;border-radius:50%;background:#d7191c;margin-right:6px;"
        ),
        paste0("> ", upper_cap, " ", unit_txt)
      )
    )
  )
}

# One legend per element, shared by raster + point groups
legend_list <- lapply(seq_len(nrow(active_cfg)), function(i) {
  cfg <- active_cfg %>% slice(i)
  build_interp_legend_html(
    label_txt = cfg$label[[1]],
    el_code   = cfg$element[[1]],
    threshold = cfg$threshold[[1]],
    upper_cap = cfg$upper_cap[[1]],
    unit_txt  = cfg$unit[[1]]
  )
})

# Name each legend twice: one for raster group, one for point group
legend_keys <- unlist(map(active_cfg$element, function(el) {
  c(paste0("Interpolated ", el), paste0("Soil ", el))
}))

legend_values <- unlist(map(legend_list, ~rep(.x, 2)))
legend_map <- as.list(legend_values)
names(legend_map) <- legend_keys

# Initial visible thematic layer
initial_group <- paste0("Interpolated ", active_cfg$element[[1]])

map_obj <- map_obj %>%
  addLayersControl(
    overlayGroups = overlay_groups,
    options = layersControlOptions(collapsed = FALSE)
  )

map_obj <- htmlwidgets::onRender(
  map_obj,
  sprintf("
    function(el, x) {
      var map = this;
      var legends = %s;
      var initialGroup = %s;
      var currentLegendControl = null;

      function removeLegend() {
        if (currentLegendControl !== null) {
          map.removeControl(currentLegendControl);
          currentLegendControl = null;
        }
      }

      function updateLegend(groupName) {
        removeLegend();

        if (legends[groupName]) {
          currentLegendControl = L.control({position: 'bottomleft'});
          currentLegendControl.onAdd = function(map) {
            var div = L.DomUtil.create('div');
            div.innerHTML = legends[groupName];
            return div;
          };
          currentLegendControl.addTo(map);
        }
      }

      updateLegend(initialGroup);

      map.on('overlayadd', function(e) {
        if (e.name !== 'Relief' && e.name !== 'All samples') {
          updateLegend(e.name);
        }
      });
    }
  ",
          jsonlite::toJSON(legend_map, auto_unbox = TRUE),
          jsonlite::toJSON(initial_group, auto_unbox = TRUE))
)

map_obj
