args <- commandArgs(trailingOnly = TRUE)
dem_arg <- match("--dem", args)
if (!is.na(dem_arg)) {
  options(sierra.dem_path = args[[dem_arg + 1L]])
  args <- args[-c(dem_arg, dem_arg + 1L)]
}
if (!length(args)) stop("Select --2d, --3d, --idw, --csv or --all")
if ("--all" %in% args) args <- c("--2d", "--csv", "--idw", "--3d")
options(timeout = 60)
if (is.null(getOption("sierra.dem_path")) && file.exists("data/spatial/terrain_dem.tif"))
  options(sierra.dem_path = "data/spatial/terrain_dem.tif")
dir.create("outputs/maps", recursive = TRUE, showWarnings = FALSE)
run <- function(name) source(file.path("scripts", name), local = .GlobalEnv)
export_map <- function(name) {
  htmlwidgets::saveWidget(map_obj, normalizePath("outputs/maps") |> file.path(name),
                         selfcontained = FALSE)
  message("Saved outputs/maps/", name)
}
if (any(args %in% c("--2d", "--csv", "--idw"))) {
  if (!length(list.files("data/raw", pattern = "\\.(xlsx|xls)$")))
    stop("No source spreadsheets in data/raw/")
  run("0_build_samples_master.R")
  run("1_map_total_elements_leaflet.R")
}
if ("--2d" %in% args) export_map("total_elements.html")
if ("--csv" %in% args) {
  dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(samples_master, "data/processed/samples_master.csv")
  totals <- tidyr::pivot_wider(element_data, id_cols = "sample_id",
                              names_from = "element", values_from = "value")
  readr::write_csv(totals, "data/processed/total_elements_wide.csv")
  run("2_build_geo_total_elements_wide.R")
  message("Saved reusable tables in data/processed/")
}
if ("--idw" %in% args) {
  run("1_leaflet_idw_total_elements_map.R")
  export_map("total_elements_idw.html")
}
if ("--3d" %in% args) run("1_map_pb_terrain_3d.R")
