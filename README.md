# script-toolbox
Various scripts to convert from FS dir's to HCP .spec files and prep data for analysis

Presently, this repository represents a collection of scripts that allows for analysis of single subject data using:
- surfaces generated from freesufer in their standard directory structure
- fMRI data preprocessed using FSL's FEAT +/- FIX
- Intersect any additional anatomical volumes with your cortical surfaces to better compare/combine datasets for computational analysis.

The goal of these scripts is to be able to use the Human Connectome Project's wb_view/wb_command tools and generate NIFTI/GIFTI/CIFTI files in subjects where you do NOT have the prerequsite data to run the HCP's Pipelines scripts.
(e.g., no 1mm^3 T2 images, no fieldmaps for BOLD data, you don't want to use MNI152 atlasspace, etc...)

This repo is actively changing, but the general order of operations is:
1. Run Freesurfer's recon-all on your subject to generate surfaces
2. (Optional: Run CreateNewTemplateSpace.sh to generate lower- or higher- resolution template meshes)
3. Run FreeSurfer2HCPWorkbenchConverter.sh to create a ./hcp subdirectory that contains HCP-style surface and .spec files
4. Run ImportVolumeToSpec.sh and ImportBOLDToSpec.sh with registered (and pre-processed) NIFTI files to generate HCP-style *.func.gii files

(NOTE: ImportBOLDToSpec.sh actually goes ahead and makes both a dense connectome and a surface fc-Gradient map based on the BOLD data, assuming it is rs-fcMRI data...)


Other files in this repository are either works in progress or are called by the scripts above. This file will be updated with descriptions of working scripts as they are created.
