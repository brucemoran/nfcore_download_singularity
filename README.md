# `nf-core tools ` Download Singularity

## Overview
The `nf-core tools download` method was not functional when setting up a new workflow on a HPC that is essentially offline. So this repo allows users to download all `Singularity` images for an `nf-core` pipeline, along with `configs` and `workflow` dirs as per `nf-core tools download`.

## Usage
1) Run the command:
   ```
   nextflow run brucemoran/nfcore_download_singularity
    --outdir <path/to/output>
    --pipeline <nf-core pipeline name>
    --revision <version>
    --email me@oh.my
   ```

2) Output goes to:
   ```
   <path/to/output>/<nf-core pipeline name>/<version>
   ```

## About the output

### `configs`, `workflow` directories
These directories are the same as is produced by `nf-core tools download`.

These are output for completeness, and we recommend still be using `nextflow pull nf-core/<name> -r <version>` to allow running using the standard `nextflow run nf-core/<name> -r <version>` command syntax.

### `singularity-images` directory
This directory contains `.sif` images downloaded from `depot.galaxy.org` and `.img` images that were pulled from the Docker Hub repo. The latter case happens when no `.sif` exists for the image.

To use these images it is important to set your `$NXF_SINGULARITY_CACHEDIR` to the `singularity-images` directory for the run.
