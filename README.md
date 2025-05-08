The **rastPATCH** package provides a two-step workflow for patching (clumping) large raster data. 
First, the *TILES()* function, powered by a Python script, efficiently creates overlapping tiles from the input raster. 
Second, the *terraTILESpatches()* function processes these tiles in parallel using the fast, C++-based *terra::patches()* function for identifying and defining patches.

### Dependencies
*reticulate*, *dplyr*, *terra*, *furrr*, *sf*, *parallelly*, *tictoc* are automatically installed (if any/all of them are missing).

### Installation

```r
devtools::install_github("DijoG/fastPATCH")
```
### Example

```r
require(fastPATCH)

result <- 
  TILES(
  input_path = "D:/GTM/DEM_Wadis_cm1.tif",
  output_dir = "D:/GTM/test",
  tile_size = 2000,
  overlap = 20
)
```
<ins>Terminal output:</ins><br/>
Python script not found in package. Downloading from GitHub...<br/>
Installing Python package: rasterio...<br/>
Installing Python package: tqdm...<br/>

Starting tiling process:<br/>
    Input: DEM_Wadis_cm1.tif<br/>
    Output: D:/test/tiles<br/>
    Tile size: 2000px with 20px overlap<br/>
Creating overlapping tiles: 100%|██████████| 2296/2296 [03:17<00:00, 11.60it/s]<br/>

Success! Overlapping tiles saved to: D:\GTM\test\tiles<br/>
Total tiles created: 2296<br/>
Tile size: 2000px with 20px overlap<br/>
195.56 sec elapsed<br/>

Operation completed successfully:<br/>
Created 2296 tiles in 195.56 seconds

**Ignore warnings!**

```r
fresult <- 
  terraTILESpatches(
  input_dir = result,                            # stored path to the tiled .tifs' directory
  output_path = paste0(result, "/test.geojson"), # or: /test.gpkg, /test.shp
  num_processes = NULL                           # NULL for automatic core detection capped at 10 cores
)
```
<ins>Terminal output:</ins><br/>
Processing 2296 raster files using 10 cores...<br/>
 Progress: ──────────────────────────────────────────── 100%5043.89 sec elapsed<br/>
Processing completed in 84.06 minutes<br/>
Merging processed polygons...<br/>
Seperating polygons to multipolygons and polygons...<br/>
Merging multipolygons...<br/>
9184.56 sec elapsed<br/>

Done! Processed 2296/2296 files in 153.08 minutes<br/>
Output: 10805900 features (avg 114.85 m2)<br/>

**Ignore warnings!**
