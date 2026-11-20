# IGN topographic background with a selectable embedded terrain fallback.
add_local_basemap <- function(map, raster = NULL) {
  map <- leaflet::addWMSTiles(map,
    baseUrl = "https://www.ign.es/wms-inspire/mapa-raster",
    layers = "mtn_rasterizado", group = "IGN topographic",
    options = leaflet::WMSTileOptions(format = "image/png", transparent = FALSE,
                                      version = "1.1.1"),
    attribution = "&copy; <a href='https://www.ign.es/'>Instituto Geográfico Nacional de España</a>")
  if (is.null(raster)) {
    path <- getOption("sierra.dem_path", "data/spatial/terrain_dem.tif")
    if (!file.exists(path)) {
      warning("Local terrain unavailable; IGN background requires internet access.")
      return(map)
    }
    raster <- terra::rast(path)
  }
  pal <- leaflet::colorNumeric(
    c("#d9e8be", "#a9c581", "#d6c590", "#b69571", "#ece8df"),
    domain = terra::values(raster), na.color = "transparent")
  map <- leaflet::addRasterImage(map, raster, colors = pal,
                                 opacity = 1, group = "Local terrain")
  map <- leaflet::addLegend(map, position = "topleft", pal = pal,
                     values = terra::values(raster), title = "Elevation (m)",
                     group = "Local terrain")
  leaflet::hideGroup(map, "Local terrain")
}
