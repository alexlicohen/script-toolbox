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
    echo "    --transform=/absolute/path/to/BOLD_to_HCPspace.mat"
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
BOLD2strucTransformMatrix=`opts_GetOpt1 "--transform" $@`
MNI2strucTransformMatrix=`opts_GetOpt1 "--transform" $@`
fMRIshortname=`opts_GetOpt1 "--inputname" $@`
fMRIresolution=`opts_GetOpt1 "--res" $@`

#Initializing Variables with Default Values if not otherwise specified
WD="`pwd`"
StudyFolder=`defaultopt $StudyFolder $WD`
fMRIshortname=`defaultopt $fMRIshortname "REST"`
fMRIresolution=`defaultopt $fMRIresolution "2"`

# hardcoded parameters
fMRIisospace="$fMRIresolution""$fMRIresolution""$fMRIresolution"
LowResMesh="32"
NeighborhoodSmoothing="5"
SmoothingFWHM=2
Factor="0.5"
HCPFolder="$StudyFolder"/"$Subject"/hcp
GrayordinatesResolution="2" # To match Standard HCP scripts
BrainOrdinatesResolution=$GrayordinatesResolution # For subcortical processing


# Create a T1 reference downsampled to 222, 333, or something else
# Note: the standard HCP CIFTI greyordinates have a ~2mm spacing on the cortex
log_Msg "Creating a T1 reference downsampled to ${fMRIisospace}"
fsAnatTarget="$HCPFolder"/T1_"$fMRIisospace"
mri_convert -vs "$fMRIresolution" "$fMRIresolution" "$fMRIresolution" "$HCPFolder"/T1.nii.gz "$fsAnatTarget".nii.gz
fMRI_in_fsAnat="$HCPFolder"/"$Subject"_"$fMRIshortname"_in_fsAnat_"$fMRIisospace"


# Apply transform to convert the BOLD data to fsAnat space
log_Msg "Applying FSL transform to convert the BOLD data to fsAnat space in ${fMRIisospace} resolution"
applywarp --ref="$fsAnatTarget" --in="$VolumefMRI" --premat="$BOLD2strucTransformMatrix" --out="$fMRI_in_fsAnat" --interp=spline


# Create Single frame image to use for targeting within HCP scripts
fslroi "$fMRI_in_fsAnat" "$fMRI_in_fsAnat"_SBRef 0 1


# Sample Volume to Surface using Ribbon Methods from HCP scripts
log_Msg "Sampling Volume to Surface using Ribbon Methods from HCP scripts (largely unmodifed script)"
if [ ! -e "$HCPFolder"/ribbon ] ; then
  mkdir -p "$HCPFolder"/ribbon
fi
RibbonVolumeToSurfaceMapping_ac.sh "$HCPFolder"/ribbon "$fMRI_in_fsAnat" "$Subject" "$HCPFolder"/fsaverage_LR"$LowResMesh"k "$LowResMesh" "$HCPFolder" FS


# Surface Smoothing adapted from HCP scripts
log_Msg "Performing Surface Smoothing adapted from HCP scripts using a FWHM of ${SmoothingFWHM}"
Sigma=`echo "$SmoothingFWHM / ( 2 * ( sqrt ( 2 * l ( 2 ) ) ) )" | bc -l`
for Hemisphere in L R ; do
 	wb_command -metric-smoothing "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii "$fMRI_in_fsAnat"."$Hemisphere".roi."$LowResMesh"k_fs_LR.func.gii "$Sigma" "$fMRI_in_fsAnat"_s"$SmoothingFWHM".roi."$Hemisphere"."$LowResMesh"k_fs_LR.func.gii -roi "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".roi."$LowResMesh"k_fs_LR.shape.gii
done


# Subcortical Processing adapted from HCP scripts
unset POSIXLY_CORRECT # unsure what part of the script is not POSIX compliant, but the HCP scripts have this here... (I typically don't set this anyway...)
log_Msg "Performing Subcortical Processing adapted from HCP scripts, and volume parcel (wmparc) resampling after applying warp and doing a volume label import, all downsampled to subject FSAnat space"
cp "${HCPPIPEDIR_Templates}/91282_Greyordinates/"Atlas_ROIs."$GrayordinatesResolution".nii.gz "$HCPFolder"/Atlas_ROIs.MNI."$GrayordinatesResolution".nii.gz

#invwarp --ref=my_struct --warp=warps_into_MNI_space --out=warps_into_my_struct_space

#applywarp --ref=my_struct --in=ACC_left --warp=warps_into_my_struct_space --out=ACC_left_in_my_struct_space --interp=nn

applywarp --interp=nn -i "$HCPFolder"/Atlas_ROIs.MNI."$GrayordinatesResolution".nii.gz -r "$fMRI_in_fsAnat".nii.gz -o "$HCPFolder"/Atlas_ROIs."$GrayordinatesResolution".nii.gz --premat
applywarp --interp=nn -i "$HCPFolder"/wmparc.nii.gz -r "$fMRI_in_fsAnat".nii.gz -o "$HCPFolder"/wmparc."$fMRIisospace".nii.gz
wb_command -volume-label-import "$HCPFolder"/wmparc."$fMRIisospace".nii.gz ${HCPPIPEDIR_Config}/FreeSurferSubcorticalLabelTableLut.txt "$HCPFolder"/ROIs."$fMRIisospace".nii.gz -discard-others
# wb_command -volume-parcel-resampling-generic "$fMRI_in_fsAnat".nii.gz "$HCPFolder"/ROIs."$fMRIisospace".nii.gz "$HCPFolder"/Atlas_ROIs."$fMRIisospace".nii.gz $Sigma "$fMRI_in_fsAnat"_AtlasSubcortical_s"$SmoothingFWHM".nii.gz -fix-zeros

echo "${script_name}: END"






