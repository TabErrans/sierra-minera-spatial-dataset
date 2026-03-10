# ============================================================
# 01_build_samples_master.R
# Purpose:
#   - Load all Excel files (data_raw/*.xlsx)
#   - Extract field sample IDs (L/G)
#   - Normalize IDs (01L == 1L)
#   - Extract UTM coordinates (utm_x/utm_y or x2/x3 in BCR sheets)
#   - Build master table: sample_id + utm_x + utm_y
#
# Outputs in memory:
#   - samples_ids         : occurrences of IDs per dataset
#   - samples_coords_all  : occurrences of coordinates per dataset
#   - samples_coords      : selected coordinate (majority vote) per sample_id
#   - samples_master      : unique table (sample_id, type, number, utm_x, utm_y, flags)
# ============================================================

suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
  library(janitor)
  library(stringr)
  library(purrr)
  library(tidyr)
  library(readr)
  library(tibble)
})

# -------------------------
# 0) Configuration
# -------------------------
data_dir <- "data_raw"
excel_files <- list.files(data_dir, pattern = "\\.(xlsx|xls)$", full.names = TRUE)

# -------------------------
# 1) Inventory (file + sheet)
# -------------------------
inventory <- purrr::map_dfr(excel_files, function(fp){
  tibble(
    file  = basename(fp),
    path  = fp,
    sheet = excel_sheets(fp)
  )
})

# Exclude derived sheet (previously identified as transformation of totals)
inventory <- inventory %>%
  filter(!(file == "Totales_Suelos.xlsx" & sheet == "Suelos_Contaminados"))

# -------------------------
# 2) Helper functions
# -------------------------

# Convert strings like "685497", "685.497" or "UTM X" to numeric
to_num <- function(x) readr::parse_number(as.character(x))

# Identify which column contains the sample ID depending on dataset
pick_id_col <- function(nms){
  candidates <- c("sample", "codigo_lab", "x1", "fase_a_acid_soluble", "codigo_sondeo") 
  hit <- intersect(candidates, nms)
  if (length(hit) == 0) return(NA_character_)
  hit[[1]]
}

# Normalize raw ID to sample_id (L/G format)
# - extract number
# - extract letter
# - remove leading zeros
normalize_sample_id <- function(id_raw){
  
  id_raw <- toupper(trimws(as.character(id_raw)))
  
  type   <- str_extract(id_raw, "[A-Z]+")
  number <- str_extract(id_raw, "[0-9]+") |> suppressWarnings() |> as.integer()
  
  if (is.na(type) || is.na(number)) return(NA_character_)
  
  type <- substr(type,1,1)
  
  paste0(number, type)
}

# Read a sheet and attach metadata
read_one_sheet <- function(path, file, sheet){
  read_excel(path, sheet = sheet, col_names = TRUE) %>%
    clean_names() %>%
    mutate(source_file = file, source_sheet = sheet, .before = 1)
}

# Extract sample IDs (long table)
extract_ids <- function(df, dataset_name){
  
  id_col <- pick_id_col(names(df))
  if (is.na(id_col)) return(NULL)
  
  out <- df %>%
    transmute(
      dataset = dataset_name,
      id_raw  = as.character(.data[[id_col]])
    ) %>%
    mutate(
      sample_id = vapply(id_raw, normalize_sample_id, character(1)),
      number = str_extract(sample_id, "[0-9]+") |> suppressWarnings() |> as.integer(),
      type   = str_extract(sample_id, "[A-Z]")
    ) %>%
    filter(!is.na(sample_id))
  
  out
}

# Extract coordinates if available
# Supports:
#   - utm_x / utm_y
#   - BCR format: x2 / x3 (header embedded in rows)
extract_coords <- function(df, dataset_name){
  
  nms <- names(df)
  
  if (all(c("utm_x","utm_y") %in% nms)) {
    
    df <- df %>% mutate(
      utm_x = to_num(utm_x),
      utm_y = to_num(utm_y)
    )
    
  } else if (all(c("x2","x3") %in% nms)) {
    
    df <- df %>%
      mutate(
        utm_x = to_num(x2),
        utm_y = to_num(x3)
      ) %>%
      filter(!is.na(utm_x), !is.na(utm_y))
    
  } else {
    
    return(NULL)
    
  }
  
  id_col <- pick_id_col(nms)
  if (is.na(id_col)) return(NULL)
  
  df %>%
    transmute(
      dataset = dataset_name,
      id_raw  = as.character(.data[[id_col]]),
      utm_x   = utm_x,
      utm_y   = utm_y
    ) %>%
    mutate(
      sample_id = vapply(id_raw, normalize_sample_id, character(1))
    ) %>%
    filter(!is.na(sample_id)) %>%
    filter(!is.na(utm_x), !is.na(utm_y))
}

# -------------------------
# 3) Load datasets
# -------------------------
datasets <- purrr::pmap(
  list(inventory$path, inventory$file, inventory$sheet),
  read_one_sheet
)

dataset_names <- paste0(
  tools::file_path_sans_ext(inventory$file),
  " :: ",
  inventory$sheet
)

names(datasets) <- dataset_names

# -------------------------
# 4) Extract IDs
# -------------------------
samples_ids <- purrr::imap_dfr(datasets, extract_ids)

samples_unique <- samples_ids %>%
  distinct(sample_id, number, type) %>%
  arrange(type, number)

# -------------------------
# 5) Extract coordinates
# -------------------------
samples_coords_all <- purrr::imap_dfr(datasets, extract_coords) %>%
  mutate(
    utm_x_r = round(utm_x, 0),
    utm_y_r = round(utm_y, 0),
    coord_key = paste0(utm_x_r, "_", utm_y_r)
  )

# -------------------------
# 6) Choose coordinate by majority vote
# -------------------------
samples_coords <- samples_coords_all %>%
  count(sample_id, coord_key, utm_x_r, utm_y_r, name = "n_votes") %>%
  group_by(sample_id) %>%
  arrange(desc(n_votes), coord_key) %>%
  slice(1) %>%
  ungroup() %>%
  transmute(
    sample_id,
    utm_x = utm_x_r,
    utm_y = utm_y_r,
    coord_key,
    n_votes
  )

# Report: samples with multiple coordinates
n_coordinate_versions <- samples_coords_all %>%
  distinct(sample_id, coord_key) %>%
  count(sample_id, name = "n_distinct_coords") %>%
  filter(n_distinct_coords > 1) %>%
  arrange(desc(n_distinct_coords))

# Report: coordinates shared by multiple sample IDs
coord_duplicates <- samples_coords %>%
  group_by(coord_key) %>%
  mutate(coord_has_multiple_ids = n() > 1) %>%
  ungroup() %>%
  filter(coord_has_multiple_ids) %>%
  arrange(coord_key, sample_id)

# -------------------------
# 7) Final master table
# -------------------------
samples_master <- samples_unique %>%
  left_join(samples_coords, by = "sample_id") %>%
  mutate(
    has_coords = !is.na(utm_x) & !is.na(utm_y)
  ) %>%
  arrange(type, number)

# -------------------------
# 8) Quick summary
# -------------------------
message("=== SUMMARY ===")
message("Unique samples (IDs): ", nrow(samples_unique))
message("Samples with coordinates: ", sum(samples_master$has_coords, na.rm = TRUE))

message("\nSamples by type:")
print(samples_master %>% count(type))

message("\nSamples requiring coordinate review: ", nrow(n_coordinate_versions))
message("Duplicate coordinates (same coord used by multiple IDs): ", nrow(coord_duplicates))
