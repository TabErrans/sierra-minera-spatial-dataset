# =========================================================
# Quick Leaflet map: total soil elements
# Required objects already in memory:
#   - datasets
#   - samples_master
# =========================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(stringr)
  library(readr)
  library(sf)
  library(leaflet)
  library(scales)
  library(htmltools)
})

# ---------------------------------------------------------
# 0) User settings
# ---------------------------------------------------------
elements <- c("Pb", "Zn", "As", "Cd")

element_config <- tibble::tribble(
  ~element, ~label,      ~search_regex,                                      ~threshold, ~unit,
  "Pb",     "Total Pb",  "(^pb$)|(^pb_)|(_pb$)|(_pb_)|plomo",                1000,       "mg/kg",
  "Zn",     "Total Zn",  "(^zn$)|(^zn_)|(_zn$)|(_zn_)|zinc",                 1000,       "mg/kg",
  "As",     "Total As",  "(^as$)|(^as_)|(_as$)|(_as_)|arsenico|arsénico",   100,        "mg/kg",
  "Cd",     "Total Cd",  "(^cd$)|(^cd_)|(_cd$)|(_cd_)|cadmio",              100,        "mg/kg"
)

# ---------------------------------------------------------
# 1) Minimal checks
# ---------------------------------------------------------
if (!exists("datasets")) stop("Object `datasets` not found in memory.")
if (!exists("samples_master")) stop("Object `samples_master` not found in memory.")

stopifnot(all(c("sample_id", "utm_x", "utm_y") %in% names(samples_master)))

missing_elements <- setdiff(elements, element_config$element)
if (length(missing_elements) > 0) {
  stop("Missing configuration for: ", paste(missing_elements, collapse = ", "))
}

# ---------------------------------------------------------
# 2) Sample ID normalizer
# ---------------------------------------------------------
normalize_sample_id <- function(id_raw){
  id_raw <- toupper(trimws(as.character(id_raw)))
  
  type   <- str_extract(id_raw, "[A-Z]+")
  number <- str_extract(id_raw, "[0-9]+") |> suppressWarnings() |> as.integer()
  
  if (is.na(type) || is.na(number)) return(NA_character_)
  
  type <- substr(type, 1, 1)
  paste0(number, type)
}

# ---------------------------------------------------------
# 3) Helper to detect the ID column
# ---------------------------------------------------------
pick_id_col <- function(nms){
  candidates <- c(
    "sample_id",
    "sample",
    "codigo_lab",
    "codigo_sondeo",
    "x1",
    "fase_a_acid_soluble"
  )
  hit <- intersect(candidates, nms)
  if (length(hit) == 0) return(NA_character_)
  hit[[1]]
}

# ---------------------------------------------------------
# 4) Select TOTAL SOIL METALS sheets
#    Includes:
#      - Metales_Totales
#      - Total_Hot_plate
#      - Total_Hot_Plate_ppm
#    Excludes:
#      - DTPA, BCR, Soluble, BAF, E, EI, vegetation datasets
# ---------------------------------------------------------
dataset_names <- names(datasets)
sheet_names <- sub("^.* :: ", "", dataset_names)

soil_total_idx <- str_detect(
  sheet_names,
  regex("^metales_totales$|^total_hot_plate$|^total_hot_plate_ppm$", ignore_case = TRUE)
)

soil_total_names <- dataset_names[soil_total_idx]

cat("Selected sheets for total soil elements:\n")
print(soil_total_names)

if (length(soil_total_names) == 0) {
  stop("No total soil metal sheets found in `datasets`.")
}

# ---------------------------------------------------------
# 5) Generic extractor for one element from one dataset
# ---------------------------------------------------------
extract_element_from_dataset <- function(df, dataset_name, element, label, search_regex){
  
  nms <- names(df)
  id_col <- pick_id_col(nms)
  
  if (is.na(id_col)) return(NULL)
  
  candidates <- nms[
    str_detect(nms, regex(search_regex, ignore_case = TRUE))
  ]
  
  candidates <- candidates[
    !str_detect(
      candidates,
      regex("dtpa|bcr|soluble|baf|gastric|gastro|percent|porc|%", ignore_case = TRUE)
    )
  ]
  
  if (length(candidates) == 0) return(NULL)
  
  value_col <- candidates[1]
  
  df %>%
    transmute(
      dataset    = dataset_name,
      element    = element,
      label      = label,
      value_src  = value_col,
      id_raw     = as.character(.data[[id_col]]),
      sample_id  = vapply(as.character(.data[[id_col]]), normalize_sample_id, character(1)),
      value      = readr::parse_number(as.character(.data[[value_col]]))
    ) %>%
    filter(!is.na(sample_id), !is.na(value))
}

# ---------------------------------------------------------
# 6) Build long table for all requested elements
# ---------------------------------------------------------
element_data_all <- purrr::map_dfr(
  elements,
  function(el){
    
    cfg <- element_config %>% filter(element == el) %>% slice(1)
    
    purrr::map_dfr(
      soil_total_names,
      ~extract_element_from_dataset(
        df           = datasets[[.x]],
        dataset_name = .x,
        element      = cfg$element,
        label        = cfg$label,
        search_regex = cfg$search_regex
      )
    )
  }
)

if (nrow(element_data_all) == 0) {
  stop("No valid rows could be extracted for the requested elements.")
}

cat("\nExtraction summary:\n")
print(
  element_data_all %>%
    count(element, dataset, sort = TRUE)
)

# ---------------------------------------------------------
# 7) Resolve duplicates per sample_id + element
# Rule:
#   keep first non-NA value
# ---------------------------------------------------------
element_conflicts <- element_data_all %>%
  group_by(element, sample_id) %>%
  summarise(
    n = n(),
    n_value_distinct = n_distinct(value),
    .groups = "drop"
  ) %>%
  filter(n > 1)

cat("\nConflicts by element + sample_id:\n")
print(element_conflicts)

element_data <- element_data_all %>%
  arrange(element, sample_id, dataset) %>%
  group_by(element, label, sample_id) %>%
  summarise(
    value = dplyr::first(value[!is.na(value)]),
    .groups = "drop"
  )

# ---------------------------------------------------------
# 8) Join with coordinates
# ---------------------------------------------------------
element_map <- samples_master %>%
  select(sample_id, utm_x, utm_y) %>%
  inner_join(element_data, by = "sample_id") %>%
  filter(!is.na(utm_x), !is.na(utm_y), !is.na(value)) %>%
  distinct(element, sample_id, .keep_all = TRUE)

cat("\nNumber of points with value + coordinates by element:\n")
print(element_map %>% count(element, sort = TRUE))

if (nrow(element_map) == 0) {
  stop("No points with coordinates after joining with `samples_master`.")
}

# ---------------------------------------------------------
# 9) Background layer: all sample coordinates
# ---------------------------------------------------------
all_pts_sf <- st_as_sf(
  samples_master %>% filter(!is.na(utm_x), !is.na(utm_y)),
  coords = c("utm_x", "utm_y"),
  crs = 25830,
  remove = FALSE
) %>%
  st_transform(4326)

# ---------------------------------------------------------
# 10) Build one sf object per element
# ---------------------------------------------------------
element_sf_list <- purrr::map(
  elements,
  function(el){
    df_el <- element_map %>% filter(element == el)
    if (nrow(df_el) == 0) return(NULL)
    
    st_as_sf(
      df_el,
      coords = c("utm_x", "utm_y"),
      crs = 25830,
      remove = FALSE
    ) %>%
      st_transform(4326)
  }
)

names(element_sf_list) <- elements
element_sf_list <- compact(element_sf_list)

if (length(element_sf_list) == 0) {
  stop("No spatial layers could be built for the requested elements.")
}

# ---------------------------------------------------------
# 11) Helper to add one element layer
# ---------------------------------------------------------
add_element_layer <- function(map, sf_obj, cfg_row){
  
  vals <- sf_obj$value
  threshold <- cfg_row$threshold[[1]]
  label_txt <- cfg_row$label[[1]]
  unit_txt <- cfg_row$unit[[1]]
  
  vals_capped <- pmin(vals, threshold)
  
  pal_low <- colorNumeric(
    palette = c("#2c7bb6", "#abd9e9", "#ffffbf", "#fdae61"),
    domain = range(vals_capped, na.rm = TRUE),
    na.color = "transparent"
  )
  
  point_col <- ifelse(
    vals > threshold,
    "#d7191c",
    pal_low(vals_capped)
  )
  
  log_vals <- suppressWarnings(log10(vals))
  
  if (sum(is.finite(log_vals)) > 1 &&
      length(unique(log_vals[is.finite(log_vals)])) > 1) {
    
    point_rad <- scales::rescale(
      log_vals,
      to = c(4, 10),
      from = range(log_vals, na.rm = TRUE)
    )
    
    point_rad[!is.finite(point_rad)] <- 6
    
  } else {
    point_rad <- rep(6, length(vals))
  }
  
  labs <- paste0(
    "<b>", sf_obj$sample_id, "</b>",
    "<br>", label_txt, ": ", round(sf_obj$value, 2), " ", unit_txt,
    "<br>", ifelse(
      sf_obj$value > threshold,
      paste0("⚠ Above ", threshold, " ", unit_txt),
      paste0("≤ ", threshold, " ", unit_txt)
    ),
    "<br>UTM X: ", round(sf_obj$utm_x, 0),
    "<br>UTM Y: ", round(sf_obj$utm_y, 0)
  )
  
  map %>%
    addCircleMarkers(
      data = sf_obj,
      lng = ~st_coordinates(geometry)[,1],
      lat = ~st_coordinates(geometry)[,2],
      radius = point_rad,
      stroke = TRUE,
      weight = 0.5,
      color = "white",
      fillOpacity = 0.9,
      fillColor = point_col,
      popup = labs,
      group = label_txt
    )
}


# ---------------------------------------------------------
# 12) Build map + dynamic legend
# ---------------------------------------------------------
active_cfg <- element_config %>%
  filter(element %in% names(element_sf_list))

overlay_groups <- c("All samples", active_cfg$label)

# Base map
map_obj <- leaflet() %>%
  addProviderTiles(providers$CartoDB.Positron) %>%
  addCircleMarkers(
    data = all_pts_sf,
    lng = ~st_coordinates(geometry)[,1],
    lat = ~st_coordinates(geometry)[,2],
    radius = 3,
    stroke = FALSE,
    fillOpacity = 0.25,
    fillColor = "grey60",
    group = "All samples"
  )

# Add element layers
for (el in names(element_sf_list)) {
  cfg <- active_cfg %>% filter(element == el) %>% slice(1)
  map_obj <- add_element_layer(map_obj, element_sf_list[[el]], cfg)
}

# Hide all thematic layers except the first one
if (nrow(active_cfg) > 1) {
  groups_to_hide <- active_cfg$label[-1]
  for (grp in groups_to_hide) {
    map_obj <- hideGroup(map_obj, grp)
  }
}

# Legend HTML builder
build_legend_html <- function(label_txt, el_code, threshold, unit_txt) {
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
        paste0("<strong>", label_txt, " (", el_code, ")</strong><br>")
      ),
      htmltools::tags$div(
        htmltools::tags$i(
          style = "background:#2c7bb6;width:12px;height:12px;display:inline-block;margin-right:6px;"
        ),
        "low"
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
        paste0("high (≤ ", threshold, " ", unit_txt, ")")
      ),
      htmltools::tags$div(
        htmltools::tags$i(
          style = "background:#d7191c;width:12px;height:12px;display:inline-block;margin-right:6px;"
        ),
        paste0("> ", threshold, " ", unit_txt)
      )
    )
  )
}

legend_list <- lapply(seq_len(nrow(active_cfg)), function(i) {
  cfg <- active_cfg %>% slice(i)
  build_legend_html(
    label_txt = cfg$label[[1]],
    el_code   = cfg$element[[1]],
    threshold = cfg$threshold[[1]],
    unit_txt  = cfg$unit[[1]]
  )
})

names(legend_list) <- active_cfg$label

# Initial legend = first visible thematic layer
initial_group <- active_cfg$label[[1]]

map_obj <- map_obj %>%
  addLayersControl(
    overlayGroups = overlay_groups,
    options = layersControlOptions(collapsed = FALSE)
  )

# Dynamic legend: update when layer changes
map_obj <- htmlwidgets::onRender(
  map_obj,
  sprintf("
    function(el, x) {
      var map = this;
      var legends = %s;
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

      map.on('overlayadd', function(e) {
        if (e.name !== 'All samples') {
          updateLegend(e.name);
        }
      });

      map.on('overlayremove', function(e) {
        if (e.name !== 'All samples') {
          var activeGroups = [];
          map.eachLayer(function(layer) {
            if (layer.options && layer.options.group && layer.options.group !== 'All samples') {
              activeGroups.push(layer.options.group);
            }
          });
        }
      });
    }
  ", jsonlite::toJSON(legend_list, auto_unbox = TRUE))
)

map_obj
