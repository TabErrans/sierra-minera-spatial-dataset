# =========================================================
# Quick Leaflet map: Total Pb in soil
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
})

# ---------------------------------------------------------
# 0) Minimal checks
# ---------------------------------------------------------
if (!exists("datasets")) stop("Object `datasets` not found in memory.")
if (!exists("samples_master")) stop("Object `samples_master` not found in memory.")

stopifnot(all(c("sample_id", "utm_x", "utm_y") %in% names(samples_master)))

# ---------------------------------------------------------
# 1) Sample ID normalizer
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
# 2) Helper to detect the ID column
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
# 3) Select TOTAL SOIL METALS sheets
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

cat("Selected sheets for total Pb in soil:\n")
print(soil_total_names)

if (length(soil_total_names) == 0) {
  stop("No total soil metal sheets found in `datasets`.")
}

# ---------------------------------------------------------
# 4) Extract Pb from a dataset
# ---------------------------------------------------------
extract_pb_from_dataset <- function(df, dataset_name){
  
  nms <- names(df)
  id_col <- pick_id_col(nms)
  
  if (is.na(id_col)) return(NULL)
  
  pb_candidates <- nms[
    str_detect(
      nms,
      regex("(^pb$)|(^pb_)|(_pb$)|(_pb_)|plomo", ignore_case = TRUE)
    )
  ]
  
  pb_candidates <- pb_candidates[
    !str_detect(pb_candidates, regex("dtpa|bcr|soluble|baf|gastric|gastro|percent|porc|%", ignore_case = TRUE))
  ]
  
  if (length(pb_candidates) == 0) return(NULL)
  
  pb_col <- pb_candidates[1]
  
  df %>%
    transmute(
      dataset   = dataset_name,
      pb_source = pb_col,
      id_raw    = as.character(.data[[id_col]]),
      sample_id = vapply(as.character(.data[[id_col]]), normalize_sample_id, character(1)),
      pb        = readr::parse_number(as.character(.data[[pb_col]]))
    ) %>%
    filter(!is.na(sample_id), !is.na(pb))
}

# ---------------------------------------------------------
# 5) Build long Pb table
# ---------------------------------------------------------
met_pb_all <- purrr::map_dfr(
  soil_total_names,
  ~extract_pb_from_dataset(datasets[[.x]], .x)
)

if (nrow(met_pb_all) == 0) {
  stop("Candidate sheets found, but no valid Pb rows could be extracted.")
}

cat("\nPb extraction summary:\n")
print(
  met_pb_all %>%
    count(dataset, sort = TRUE)
)

# ---------------------------------------------------------
# 6) Resolve duplicates per sample_id
# Rule:
#   keep first non-NA Pb value
# ---------------------------------------------------------
met_pb_conflicts <- met_pb_all %>%
  group_by(sample_id) %>%
  summarise(
    n = n(),
    n_pb_distinct = n_distinct(pb),
    .groups = "drop"
  ) %>%
  filter(n > 1)

cat("\nPb conflicts by sample_id:\n")
print(met_pb_conflicts)

met_pb <- met_pb_all %>%
  arrange(sample_id, dataset) %>%
  group_by(sample_id) %>%
  summarise(
    pb = dplyr::first(pb[!is.na(pb)]),
    .groups = "drop"
  )

# ---------------------------------------------------------
# 7) Join Pb with coordinates
# ---------------------------------------------------------
pb_map <- samples_master %>%
  select(sample_id, utm_x, utm_y) %>%
  inner_join(met_pb, by = "sample_id") %>%
  filter(!is.na(utm_x), !is.na(utm_y), !is.na(pb)) %>%
  distinct(sample_id, .keep_all = TRUE)

cat("\nNumber of points with Pb + coordinates:", nrow(pb_map), "\n")

if (nrow(pb_map) == 0) {
  stop("No points with Pb and coordinates after joining with `samples_master`.")
}

# ---------------------------------------------------------
# 8) All coordinates as grey background layer
# ---------------------------------------------------------
all_pts_sf <- st_as_sf(
  samples_master %>% filter(!is.na(utm_x), !is.na(utm_y)),
  coords = c("utm_x", "utm_y"),
  crs = 25830,
  remove = FALSE
) %>%
  st_transform(4326)

# ---------------------------------------------------------
# 9) Convert Pb data to sf
# ---------------------------------------------------------
pb_sf <- st_as_sf(
  pb_map,
  coords = c("utm_x", "utm_y"),
  crs = 25830,
  remove = FALSE
) %>%
  st_transform(4326)

# ---------------------------------------------------------
# 10) Colors and point sizes
#     > 1000 mg/kg = red
# ---------------------------------------------------------
threshold_pb <- 1000

pb_capped <- pmin(pb_sf$pb, threshold_pb)

pal_low <- colorNumeric(
  palette = c("#2c7bb6", "#abd9e9", "#ffffbf", "#fdae61"),
  domain = range(pb_capped, na.rm = TRUE),
  na.color = "transparent"
)

point_col <- ifelse(
  pb_sf$pb > threshold_pb,
  "#d7191c",
  pal_low(pb_sf$pb)
)

point_rad <- rescale(
  log10(pb_sf$pb),
  to = c(4, 10),
  from = range(log10(pb_sf$pb), na.rm = TRUE)
)

labs <- paste0(
  "<b>", pb_sf$sample_id, "</b>",
  "<br>Total Pb: ", round(pb_sf$pb, 2), " mg/kg",
  "<br>", ifelse(pb_sf$pb > threshold_pb, "⚠ Above 1000 mg/kg", "≤ 1000 mg/kg"),
  "<br>UTM X: ", round(pb_sf$utm_x, 0),
  "<br>UTM Y: ", round(pb_sf$utm_y, 0)
)

# ---------------------------------------------------------
# 11) Map
# ---------------------------------------------------------
leaflet() %>%
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
  ) %>%
  
  addCircleMarkers(
    data = pb_sf,
    lng = ~st_coordinates(geometry)[,1],
    lat = ~st_coordinates(geometry)[,2],
    radius = point_rad,
    stroke = TRUE,
    weight = 0.5,
    color = "white",
    fillOpacity = 0.9,
    fillColor = point_col,
    popup = labs,
    group = "Total Pb in soil"
  ) %>%
  
  addLayersControl(
    overlayGroups = c("All samples", "Total Pb in soil"),
    options = layersControlOptions(collapsed = FALSE)
  ) %>%
  
  addLegend(
    position = "bottomright",
    colors = c("#2c7bb6", "#abd9e9", "#ffffbf", "#fdae61", "#d7191c"),
    labels = c("low", "moderate-low", "moderate", "high (≤1000)", ">1000 mg/kg"),
    title = "Total Pb in soil",
    opacity = 1
  )
