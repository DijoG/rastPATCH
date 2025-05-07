#' Fast raster tiling using Python's rasterio with overlap
#'
#' This function leverages a Python backend (`raster_tile.py`) to split large rasters
#' into smaller, overlapping tiles for efficient processing.
#'
#' @param input_path Path to input raster file (GeoTIFF)
#' @param output_dir Directory where tiles will be saved (creates "tiles" subdirectory)
#' @param tile_size Size of output tiles in pixels (default: 2000)
#' @param overlap Size of overlap (pixels) between tiles (default: 20)
#' @return Geotiff tiles in the automatically created 'tiles' tiles directory (invisibly), plus path string
#' @export
TILES <- function(input_path, output_dir, tile_size = 2000, overlap = 20) {
  
  # Validate R requirements
  required_pkgs = c("reticulate", "tictoc")
  missing_pkgs = required_pkgs[!sapply(required_pkgs, requireNamespace, quietly = TRUE)]
  if (length(missing_pkgs) > 0) {
    stop(paste("Required R packages missing:", paste(missing_pkgs, collapse = ", "),
               "\nInstall with: install.packages(c('", paste(missing_pkgs, collapse = "', '"), "'))"))
  }
  
  # Input validation
  if (!file.exists(input_path)) {
    stop(sprintf("Input file not found: %s", normalizePath(input_path, mustWork = FALSE)))
  }
  
  if (!dir.exists(output_dir)) {
    message(sprintf("Creating output directory: %s", output_dir))
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }
  
  # Get Python script path from package installation
  python_script_path <- system.file("python/raster_tile.py", package = "rastPATCH")
  if (python_script_path == "") {
    # Fallback: Try to download from GitHub if not found in package
    message("Python script not found in package. Downloading from GitHub...")
    python_dir = file.path(tempdir(), "rastPATCH", "python")
    dir.create(python_dir, recursive = TRUE, showWarnings = FALSE)
    python_script_path = file.path(python_dir, "raster_tile.py")
    
    tryCatch({
      utils::download.file(
        "https://raw.githubusercontent.com/DijoG/rastPATCH/main/python/raster_tile.py",
        python_script_path,
        quiet = TRUE
      )
    }, error = function(e) {
      stop("Failed to download Python script from GitHub. Please check internet connection.")
    })
  }
  
  if (!file.exists(python_script_path)) {
    stop(sprintf("Python script not found: %s", python_script_path))
  }
  
  # Initialize Python environment
  tryCatch({
    if (!reticulate::py_available()) {
      reticulate::py_config()
    }
    
    # Check/install Python packages
    required_py_pkgs <- c("rasterio", "numpy", "tqdm")
    for (pkg in required_py_pkgs) {
      if (!reticulate::py_module_available(pkg)) {
        message(sprintf("Installing Python package: %s...", pkg))
        reticulate::py_install(pkg)
      }
    }
  }, error = function(e) {
    stop(sprintf("Python environment setup failed: %s", e$message))
  })
  
  # Prepare paths
  input_path = normalizePath(input_path, winslash = "/")
  output_dir = normalizePath(output_dir, winslash = "/")
  python_script_path = normalizePath(python_script_path, winslash = "/")
  
  message(sprintf(
    paste("\nStarting tiling process:",
          "Input: %s",
          "Output: %s",
          "Tile size: %dpx with %dpx overlap",
          sep = "\n    "),
    basename(input_path),
    file.path(output_dir, "tiles"),
    tile_size,
    overlap
  ))
  
  tictoc::tic()
  
  # Execute Python code
  py_code <- sprintf(
    'import sys
from raster_tile import tile_raster_with_overlap

try:
    tile_raster_with_overlap(
        input_path = r"%s",
        output_dir = r"%s",
        tile_size = %d,
        overlap = %d
    )
except Exception as e:
    print("Python error:", str(e))
    raise e',
    input_path,
    output_dir,
    tile_size,
    overlap
  )
  
  # Add script directory to Python path
  reticulate::py_run_string(sprintf('import sys; sys.path.append(r"%s")', dirname(python_script_path)))
  
  tryCatch({
    reticulate::py_run_string(py_code)
  }, error = function(e) {
    stop(sprintf("Python execution failed: %s\nPython error: %s", 
                 e$message, 
                 reticulate::py_last_error()))
  })
  
  # Verify output
  tiles_dir <- file.path(output_dir, "tiles")
  if (!dir.exists(tiles_dir)) {
    stop(sprintf("Tile directory not created at: %s", tiles_dir))
  }
  
  n_tiles <- length(list.files(tiles_dir, pattern = "\\.tif$"))
  proc_time <- tictoc::toc()
  
  message(sprintf(
    paste("\nOperation completed successfully:",
          "Created %d tiles in %.1f seconds",
          "Output location: %s",
          sep = "\n"),
    n_tiles,
    proc_time$toc - proc_time$tic,
    tiles_dir
  ))
  
  invisible(tiles_dir)
}

#' Process raster tiles to create cleaned polygon patches
#'
#' @param input_dir Directory containing input raster tiles (.tif files)
#' @param output_path Output file path (supported formats: .shp, .gpkg, .geojson)
#' @param num_processes Number of parallel processes to use (NULL for automatic ~ max 10 cores)
#' @return gpkg or geojson or shp plus an sf object containing the patched/clumped polygons (invisibly)
#' @export
terraTILESpatches <- function(input_dir, output_path, num_processes = NULL) {
  
  # Check and install required packages
  required_pkgs = c("dplyr", "terra", "furrr", "sf", "parallelly", "tictoc")
  
  # Check which packages are not installed
  missing_pkgs = required_pkgs[!sapply(required_pkgs, requireNamespace, quietly = TRUE)]
  
  if (length(missing_pkgs) > 0) {
    message("Installing missing packages: ", paste(missing_pkgs, collapse = ", "))
    utils::install.packages(missing_pkgs, dependencies = TRUE)
  }
  
  # Load required packages quietly
  suppressPackageStartupMessages({
    require(dplyr, quietly = TRUE)
    require(terra, quietly = TRUE)
    require(furrr, quietly = TRUE)
    require(sf, quietly = TRUE)
    require(parallelly, quietly = TRUE)
    require(tictoc, quietly = TRUE)
  })
  
  tictoc::tic()
  
  # Validate output file extension
  output_ext = tolower(tools::file_ext(output_path))
  if (!output_ext %in% c("shp", "gpkg", "geojson")) {
    stop("Output file format must be one of: .shp, .gpkg, or .geojson")
  }
  
  # Set up parallel processing
  max_cores = min(parallelly::availableCores() - 2, 10)
  if (is.null(num_processes)) {
    cores = max_cores
  } else {
    cores = min(num_processes, max_cores)
  }
  
  # Get list of raster files
  raster_files = list.files(input_dir, pattern = "\\.tif$", full.names = TRUE)
  if (length(raster_files) == 0) {
    stop("No .tif files found in the input directory")
  }
  
  # Process function for individual rasters
  process_raster = function(file) {
    tryCatch({
      r = terra::rast(file) %>%
        terra::patches(directions = 8) %>%
        terra::as.polygons() %>%
        sf::st_as_sf() %>%
        dplyr::mutate(AREA_m2 = round(as.numeric(sf::st_area(geometry)), 2))
      return(r)
    }, error = function(e) {
      warning(paste("Failed to process file:", file, "\nError:", e$message))
      return(NULL)
    })
  }
  
  # Parallel processing with progress
  message(paste("Processing", length(raster_files), "raster files using", cores, "cores..."))
  future::plan(future::multisession, workers = cores)
  
  tictoc::tic()
  processed_polygons = furrr::future_map(raster_files, process_raster, 
                                         .progress = TRUE, 
                                         .options = furrr_options(seed = TRUE))
  processing_time = tictoc::toc()
  message(sprintf(
    "Processing completed in %.2f minutes", 
    as.numeric(gsub("[^0-9.-]", "", processing_time$callback_msg))/60
  ))
  
  # Return to sequential processing
  future::plan(sequential)
  
  # Remove any failed processing results (NULLs)
  processed_polygons = processed_polygons[!sapply(processed_polygons, is.null)]
  
  if (length(processed_polygons) == 0) {
    stop("No raster files were successfully processed")
  }
  
  # Combine all polygons
  message("Merging processed polygons...")
  combined_poly = dplyr::bind_rows(processed_polygons) 
  
  # Separate by geometry type (MULTIPOLYGON and POLYGON)
  message("Seperating polygons to multipolygons and polygons...")
  poly_multipoly = combined_poly %>% 
    dplyr::filter(sf::st_geometry_type(.) == "MULTIPOLYGON")
  
  poly_poly = combined_poly %>% 
    dplyr::filter(sf::st_geometry_type(.) == "POLYGON") %>%
    dplyr::mutate(patches = "non_merged")
  
  # Process multipolygons (check if any exist)
  message("Merging multipolygons...")
  if (nrow(poly_multipoly) > 0) {
    poly_multipoly_merged = poly_multipoly %>%
      dplyr::group_by(patches) %>%
      dplyr::summarise(geometry = sf::st_union(geometry)) %>%
      sf::st_cast("POLYGON") %>%
      dplyr::mutate(patches = "merged")
    
    # Harmonize columns before binding
    common_cols = intersect(names(poly_poly), names(poly_multipoly_merged))
    final_poly = 
      dplyr::bind_rows(
        poly_poly %>% dplyr::select(dplyr::all_of(common_cols)),
        poly_multipoly_merged %>% dplyr::select(dplyr::all_of(common_cols))
      ) 
  } else {
    final_poly = poly_poly
  }
  
  # Calculate final areas
  final_poly = 
    final_poly %>%
    dplyr::mutate(
      AREA_m2 = round(as.numeric(sf::st_area(geometry)), 2)
    )
  
  # Write output
  outdir = dirname(output_path)
  if (!dir.exists(outdir)) {
    dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
  }
  
  switch(output_ext,
         "shp" = sf::write_sf(final_poly, output_path),
         "gpkg" = sf::write_sf(final_poly, output_path, driver = "GPKG"),
         "geojson" = sf::write_sf(final_poly, output_path, driver = "GeoJSON")
  )
  
  # Final summary
  processing_time = tictoc::toc()
  message(sprintf(
    "\nDone! Processed %d/%d files in %.2f minutes\nOutput: %d features (avg %.2f m2)",
    length(processed_polygons), length(raster_files),
    as.numeric(gsub("[^0-9.-]", "", processing_time$callback_msg))/60,
    nrow(final_poly),
    mean(final_poly$AREA_m2, na.rm = TRUE)
  ))
  
  invisible(final_poly)
}
