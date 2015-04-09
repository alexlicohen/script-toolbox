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
    echo "This takes a nifti volume of fMRI data, prcoesses it with FEAT and FIX, "
    echo "and then does surface intersections with a FS->HCP .spec file"
    echo "  Inputs:"
    echo "    --subject=fc_12345"
    echo "    --inputvolume=/absolute/path/to/BOLD_timecourse.nii.gz"
    echo "   [--inputname=REST10min]  will use REST unless you want something else"
    echo "   [--path=/absolute/path/to/study/folder]  if not specified, assumes pwd"
    exit 1
}

defaultopt() {
    echo $1
}

# --------------------------------------------------------------------------------
#   Establish tool name for logging
# --------------------------------------------------------------------------------
log_SetToolName "RestMRI2HCPSpec.sh"

################################################## OPTION PARSING #####################################################

opts_ShowVersionIfRequested $@

if opts_CheckForHelpRequest $@; then
    show_usage
fi

log_Msg "Parsing Command Line Options"

# Input Variables
StudyFolder=`opts_GetOpt1 "--path" $@`
Subject=`opts_GetOpt1 "--subject" $@`
VolumefMRI=`opts_GetOpt1 "--inputvolume" $@` #T2w, DIR or other image already registered to T1 used as HCP Pipelines/Freesurfer input
fMRIshortname=`opts_GetOpt1 "--inputname" $@` #what prefix/suffix to add to new files (if using T2 images, this could be T2w, etc...)

#Initializing Variables with Default Values if not otherwise specified
WD="`pwd`"
StudyFolder=`defaultopt $StudyFolder $WD`
fMRIshortname=`defaultopt $fMRIshortname "REST"`

# hardcoded parameters
LowResMesh="32"
NeighborhoodSmoothing="5"
Factor="0.5"
LeftGreyRibbonValue="1"
RightGreyRibbonValue="1"
HCPFolder="$StudyFolder"/"$Subject"/hcp

# Set up the ribbon files as per the HCP fMRISurface scripts, but in fsAnat space only
for Hemisphere in L R ; do
  if [ $Hemisphere = "L" ] ; then
    GreyRibbonValue="$LeftGreyRibbonValue"
  elif [ $Hemisphere = "R" ] ; then
    GreyRibbonValue="$RightGreyRibbonValue"
  fi    
  ${CARET7DIR}/wb_command -create-signed-distance-volume "$HCPFolder"/"$Subject"."$Hemisphere".white.native.surf.gii "$HCPFolder"/T1.nii.gz "$HCPFolder"/"$Subject"."$Hemisphere".white.native.nii.gz
  ${CARET7DIR}/wb_command -create-signed-distance-volume "$HCPFolder"/"$Subject"."$Hemisphere".pial.native.surf.gii "$HCPFolder"/T1.nii.gz "$HCPFolder"/"$Subject"."$Hemisphere".pial.native.nii.gz
  fslmaths "$HCPFolder"/"$Subject"."$Hemisphere".white.native.nii.gz -thr 0 -bin -mul 255 "$HCPFolder"/"$Subject"."$Hemisphere".white_thr0.native.nii.gz
  fslmaths "$HCPFolder"/"$Subject"."$Hemisphere".white_thr0.native.nii.gz -bin "$HCPFolder"/"$Subject"."$Hemisphere".white_thr0.native.nii.gz
  fslmaths "$HCPFolder"/"$Subject"."$Hemisphere".pial.native.nii.gz -uthr 0 -abs -bin -mul 255 "$HCPFolder"/"$Subject"."$Hemisphere".pial_uthr0.native.nii.gz
  fslmaths "$HCPFolder"/"$Subject"."$Hemisphere".pial_uthr0.native.nii.gz -bin "$HCPFolder"/"$Subject"."$Hemisphere".pial_uthr0.native.nii.gz
  fslmaths "$HCPFolder"/"$Subject"."$Hemisphere".pial_uthr0.native.nii.gz -mas "$HCPFolder"/"$Subject"."$Hemisphere".white_thr0.native.nii.gz -mul 255 "$HCPFolder"/"$Subject"."$Hemisphere".ribbon.nii.gz
  fslmaths "$HCPFolder"/"$Subject"."$Hemisphere".ribbon.nii.gz -bin -mul $GreyRibbonValue "$HCPFolder"/"$Subject"."$Hemisphere".ribbon.nii.gz
  rm "$HCPFolder"/"$Subject"."$Hemisphere".white.native.nii.gz "$HCPFolder"/"$Subject"."$Hemisphere".white_thr0.native.nii.gz "$HCPFolder"/"$Subject"."$Hemisphere".pial.native.nii.gz "$HCPFolder"/"$Subject"."$Hemisphere".pial_uthr0.native.nii.gz
done


# Import the BET'd T1 in fsAnat space to the HCP dir
fsAnatTarget=/projects/mayoresearch/fc01/hcp/T1_brain.nii.gz
fslreorient2std T1_brain.nii.gz >> T1_brain.reorient.mat
fslreorient2std T1_brain.nii.gz T1_brain.nii.gz

# Process the raw NIFTI BOLD data through FEAT, then FIX
fMRIinput=/projects/mayoresearch/raw_nifti/fc01/fc01_BOLD.nii.gz
# get the script version from the FEAT gui settings...
fix fMRI.feat /usr/local/fix/training_files/Standard.RData 20 -m

# Apply transform to convert the cleaned BOLD data to fsAnat space
applywarp --ref=/projects/mayoresearch/fc01/hcp/T1 --in=example_func --premat=example_func2highres.mat --out=example_func_in_fsAnat --interp=spline

# Sample Volume to Surface using Ribbon Methods from HCP scripts
RibbonVolumeToSurfaceMapping.sh