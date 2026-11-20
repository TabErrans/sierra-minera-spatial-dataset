# One R session preserves the objects shared by the original scripts.
args <- commandArgs(trailingOnly = TRUE)
target <- args[[1]]
report <- args[[2]]
options(timeout = 60, sierra.map_output_dir = file.path(report, "terrain_3d"))
if (file.exists("data/spatial/terrain_dem.tif"))
  options(sierra.dem_path = "data/spatial/terrain_dem.tif")
steps <- c(master = "0_build_samples_master.R",
           leaflet = "1_map_total_elements_leaflet.R",
           geo = "2_build_geo_total_elements_wide.R",
           idw = "1_leaflet_idw_total_elements_map.R",
           terrain = "1_map_pb_terrain_3d.R")
deps <- list(master = character(), leaflet = "master", geo = "leaflet",
             idw = "leaflet", terrain = "geo")
needed <- function(x) unique(c(unlist(lapply(deps[[x]], needed)), x))
selected <- if (target == "all") names(steps) else needed(target)
state <- setNames(rep("NOT_RUN", length(steps)), names(steps))
results <- data.frame(step = character(), status = character(), detail = character())
for (step in selected) {
  blocked <- deps[[step]][state[deps[[step]]] != "PASS"]
  detail <- ""
  if (length(blocked)) {
    state[[step]] <- "BLOCKED"
    detail <- paste("Failed prerequisite:", paste(blocked, collapse = ", "))
  } else {
    state[[step]] <- tryCatch({
      if (step == "master" && !length(list.files("data/raw", pattern = "\\.(xlsx|xls)$")))
        stop("No Excel inputs in data/raw/. Supply the archived source spreadsheets.")
      if (step == "geo") {
        dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
        readr::write_csv(samples_master, "data/processed/samples_master.csv")
        totals <- tidyr::pivot_wider(element_data, id_cols = "sample_id",
                                    names_from = "element", values_from = "value")
        readr::write_csv(totals, "data/processed/total_elements_wide.csv")
      }
      source(file.path("scripts", steps[[step]]), local = .GlobalEnv)
      if (step == "master" && !nrow(samples_master)) stop("Empty sample master table")
      if (step %in% c("leaflet", "idw")) {
        htmlwidgets::saveWidget(map_obj, file.path(report, paste0(step, ".html")),
                                selfcontained = FALSE)
      }
      "PASS"
    }, error = function(e) {
      detail <<- conditionMessage(e)
      "FAIL"
    })
  }
  cat(sprintf("\n[%s] %s %s\n", state[[step]], step, detail))
  results <- rbind(results, data.frame(step = step, status = state[[step]], detail = detail))
  write.table(results, file.path(report, "summary.tsv"), sep = "\t",
              row.names = FALSE, quote = TRUE)
}
cat("\nPASS means script execution completed; browser tiles and visual quality are not tested.\n")
quit(status = if (all(state[selected] == "PASS")) 0L else 1L)
