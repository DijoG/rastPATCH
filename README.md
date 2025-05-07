The **rastPATCH** package provides two functions: *TILES()* and *terraTILESpatches()*. 
The *TILES()* function uses a Python (2D arrays) script for fast tiling of a huge raster with user-defined overlap between the tiles.
Core of the *terraTILESpatches()* function is the C++-backed *terra::patches()* on the tiles processed by *TILES()*.

### Dependencies
reticulate, dplyr, terra, furrr, sf, parallelly, tictoc

### Installation

```r
devtools::install_github("DijoG/fastPATCH")
```
### Example

```r
require(fastPATCH)

result <- TILES(
  input_path = "D:/GTM/DEM_Wadis_cm1.tif",
  output_dir = "D:/GTM/test",
  tile_size = 2000,
  overlap = 20
)
```
**Terminal output:** 
Python script not found in package. Downloading from GitHub...
Installing Python package: rasterio...
Installing Python package: tqdm...

Starting tiling process:
    Input: DEM_Wadis_cm1.tif
    Output: D:/test/tiles
    Tile size: 2000px with 20px overlap
Creating overlapping tiles: 100%|██████████| 2296/2296 [03:17<00:00, 11.60it/s]

Success! Overlapping tiles saved to: D:\GTM\test\tiles
Total tiles created: 2296
Tile size: 2000px with 20px overlap
203.94 sec elapsed

Operation completed successfully:
Created 2296 tiles in 195.56 seconds

**Ignore warnings!**

```r
require(fastPATCH)

fresult <- terraTILESpatches(
  input_dir = result,                            # stored path to the processed tiles' directory
  output_path = paste0(result, "/test.geojson"), # or: /test.gpkg, /test.shp
  num_processes = NULL                           # NULL for automatic core detection capped at 10 cores
)
```
**Terminal output:** 
