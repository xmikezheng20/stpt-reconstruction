# stpt-reconstruction

A lightweight MATLAB pipeline for reconstructing native TissueCyte-style STPT datasets using illumination correction and stitching algorithms from StitchIt.

The motivation is to provide a small, auditable bridge from the native
OpenSTP/TissueCyte acquisition layout used by our microscope to StitchIt's
offline reconstruction algorithms, without adopting the full BakingTray
acquisition workflow or repackaging the raw TIFFs.

The pipeline reads the native TIFF and Mosaic files in place and writes every
derived artifact under the experiment's `processed/reconstruction` directory.
Raw acquisition files are never renamed or rewritten.

## Current stage

Stage 1 builds and validates the complete dataset index. It parses acquisition
metadata, maps each TIFF to section/layer/tile/channel coordinates, reconstructs
the commanded 14-by-18 scan grid, and writes auditable tables and QC plots.

Run it from the repository root:

```matlab
addpath('config');
runStptReconstruction(config_260812_MikeZ_PO431109_F_01());
```

The master runner will eventually orchestrate all reconstruction stages from the
same experiment config.

Completed stage directories are protected from accidental replacement. To
intentionally regenerate Stage 1, set `cfg.execution.overwrite = true`; the old
derived Stage 1 directory is removed before the new run starts.
