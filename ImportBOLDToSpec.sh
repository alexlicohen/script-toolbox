#!/bin/bash
set -e
#set -x

# Requirements for this script
#  installed versions of: FSL (version 5.0.6+), FreeSurfer (version 5.3.0-HCP), wb_command
#  environment: FSLDIR , FREESURFER_HOME , HCPPIPEDIR , CARET7DIR

# Author: Alex Cohen, with additional code adapted from HCP Pipelines scripts

# --------------------------------------------------------------------------------
#  Load Function Libraries
# --------------------------------------------------------------------------------

source $HCPPIPEDIR/global/scripts/log.shlib  # Logging related functions
source $HCPPIPEDIR/global/scripts/opts.shlib # Command line option functions

########################################## SUPPORT FUNCTIONS ##########################################

# --------------------------------------------------------------------------------
#  Usage Description Function
# --------------------------------------------------------------------------------

show_usage() {
    echo "This takes a nifti volume of fMRI data, e.g., after processesing with"
    echo "FEAT +/- FIX, and then does surface intersections for a FS->HCP .spec file"
    echo "  Inputs:"
    echo "    --subject=fc_12345"
    echo "    --inputvolume=/absolute/path/to/BOLD_timecourse.nii.gz"
    echo "   [--inputname=REST10min]  will use REST unless you want something else"
    echo "   [--path=/absolute/path/to/study/folder]  if not specified, assumes pwd"
    echo "   [--res=3]  will use 2, i.e., 2mm^3 voxels unless you want something else"
    exit 1
}

defaultopt() {
    echo $1
}

# --------------------------------------------------------------------------------
#   Establish tool name for logging
# --------------------------------------------------------------------------------
log_SetToolName "ImportBOLDToSpec.sh"

################################################## OPTION PARSING #####################################################

opts_ShowVersionIfRequested $@

if opts_CheckForHelpRequest $@; then
    show_usage
fi

log_Msg "Parsing Command Line Options"

# Input Variables
StudyFolder=`opts_GetOpt1 "--path" $@`
Subject=`opts_GetOpt1 "--subject" $@`
VolumefMRI=`opts_GetOpt1 "--inputvolume" $@`
fMRIshortname=`opts_GetOpt1 "--inputname" $@`
fMRIresolution=`opts_GetOpt1 "--res" $@`

#Initializing Variables with Default Values if not otherwise specified
WD="`pwd`"
StudyFolder=`defaultopt $StudyFolder $WD`
fMRIshortname=`defaultopt $fMRIshortname "REST"`
fMRIresolution=`defaultopt $fMRIresolution "2"`

# hardcoded parameters
LowResMesh="32"
NeighborhoodSmoothing="5"
Factor="0.5"
HCPFolder="$StudyFolder"/"$Subject"/hcp


# Create a T1 reference downsampled to 222, 333, or something else
# Note: the standard HCP CIFTI greyordinates have a ~2mm spacing on the cortex
fMRIisospace="$fMRIresolution""$fMRIresolution""$fMRIresolution"
fsAnatTarget="$HCPFolder"/T1_"$fMRIisospace"
mri_convert -vs "$fMRIresolution" "$fMRIresolution" "$fMRIresolution" "$HCPFolder"/T1.nii.gz $fsAnatTarget

fMRI_in_fsAnat="$HCPFolder"/"$Subject""$fMRIshortname"_in_fsAnat"$fMRIisospace"

# Apply transform to convert the cleaned BOLD data to fsAnat space
applywarp --ref="$fsAnatTarget" --in="$VolumefMRI" --premat=reg/example_func2highres.mat --out="$fMRI_in_fsAnat" --interp=spline

# Create Single frame image to use for targeting within HCP scripts
fslroi "$fMRI_in_fsAnat" "$fMRI_in_fsAnat"_SBRef 0 1

# Sample Volume to Surface using Ribbon Methods from HCP scripts
$HCPPIPEDIR/fMRISurface/scripts/RibbonVolumeToSurfaceMapping.sh "$HCPFolder"/temp "$fMRI_in_fsAnat" fc01 "$HCPFolder"/fsaverage_LR32k 32 "$HCPFolder" FS