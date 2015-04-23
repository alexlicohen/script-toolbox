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
    echo "    --BOLDtransform=/absolute/path/to/BOLD_to_HCPspace.mat"
    echo "    --MNItransform=/absolute/path/to/fsAnant_to_MNI   (.nii.gz)"
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

log_Msg "Script START"

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
BOLD2strucTransformMatrix=`opts_GetOpt1 "--BOLDtransform" $@`
struc2MNITransformMatrix=`opts_GetOpt1 "--MNItransform" $@`
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
SmoothingFWHM=2
HCPFolder="$StudyFolder"/"$Subject"/hcp
GrayordinatesResolution="2" # To match Standard HCP scripts
BrainOrdinatesResolution=$GrayordinatesResolution # For subcortical processing
MemLimit=12 # in GB, set to a couple GB less than max to not slow down the computer too much...


# Create a T1 reference downsampled to 222, 333, or something else
# Note: the standard HCP CIFTI greyordinates have a ~2mm spacing on the cortex and for subcortical ROIs, so a 2mm version is always created...
log_Msg "Creating a T1 reference downsampled to ${fMRIisospace}"
fsAnatTarget="$HCPFolder"/T1_"$fMRIisospace"
mri_convert -vs "$fMRIresolution" "$fMRIresolution" "$fMRIresolution" "$HCPFolder"/T1.nii.gz "$fsAnatTarget".nii.gz
fMRI_in_fsAnat="$HCPFolder"/"$Subject"_"$fMRIshortname"_in_fsAnat_"$fMRIisospace"
if [ 1 -ne `echo "$fMRIresolution" == 2 | bc -l` ] ; then
	mri_convert -vs 2 2 2 "$HCPFolder"/T1.nii.gz "$HCPFolder"/T1_222.nii.gz
fi

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
invwarp --ref="$HCPFolder"/T1.nii.gz --warp="$struc2MNITransformMatrix" --out="$HCPFolder"/MNI_to_fsAnat_warp
wb_command -volume-warpfield-resample "$HCPFolder"/Atlas_ROIs.MNI."$GrayordinatesResolution".nii.gz "$HCPFolder"/MNI_to_fsAnat_warp.nii.gz "$HCPFolder"/T1_"$fMRIisospace".nii.gz ENCLOSING_VOXEL "$HCPFolder"/Atlas_ROIs.fsAnat."$GrayordinatesResolution"."$fMRIisospace".nii.gz -fnirt /projects/mayoresearch/fc01/fMRI.feat/reg/standard.nii.gz

applywarp --interp=nn -i "$HCPFolder"/wmparc.nii.gz -r "$fMRI_in_fsAnat".nii.gz -o "$HCPFolder"/wmparc."$fMRIisospace".nii.gz
wb_command -volume-label-import "$HCPFolder"/wmparc."$fMRIisospace".nii.gz ${HCPPIPEDIR_Config}/FreeSurferSubcorticalLabelTableLut.txt "$HCPFolder"/ROIs."$fMRIisospace".nii.gz -discard-others

wb_command -volume-parcel-resampling-generic "$fMRI_in_fsAnat".nii.gz "$HCPFolder"/ROIs."$fMRIisospace".nii.gz "$HCPFolder"/Atlas_ROIs.fsAnat."$GrayordinatesResolution"."$fMRIisospace".nii.gz $Sigma "$fMRI_in_fsAnat"_AtlasSubcortical_s"$SmoothingFWHM".nii.gz -fix-zeros


# Generation of Dense Timeseries
log_Msg "Generating Dense Timeseries adapted from HCP Scripts"
TR_vol=`fslval "$fMRI_in_fsAnat"_AtlasSubcortical_s"$SmoothingFWHM".nii.gz pixdim4 | cut -d " " -f 1`

wb_command -cifti-create-dense-timeseries "$fMRI_in_fsAnat"_AtlasSubcortical_in_Gray_"$fMRIisospace".dtseries.nii -volume "$fMRI_in_fsAnat"_AtlasSubcortical_s"$SmoothingFWHM".nii.gz "$HCPFolder"/Atlas_ROIs.fsAnat."$GrayordinatesResolution"."$fMRIisospace".nii.gz -left-metric "$fMRI_in_fsAnat"_s"$SmoothingFWHM".roi.L."$LowResMesh"k_fs_LR.func.gii -roi-left "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject".L.roi."$LowResMesh"k_fs_LR.shape.gii -right-metric "$fMRI_in_fsAnat"_s"$SmoothingFWHM".roi.R."$LowResMesh"k_fs_LR.func.gii -roi-right "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject".R.roi."$LowResMesh"k_fs_LR.shape.gii -timestep "$TR_vol"


# Generation of Dense Connectome (set of correlation maps)
wb_command -cifti-correlation "$fMRI_in_fsAnat"_AtlasSubcortical_in_Gray_"$fMRIisospace".dtseries.nii "$fMRI_in_fsAnat"_AtlasSubcortical_in_Gray_"$fMRIisospace".dconn.nii -mem-limit "$MemLimit"

SurfacePresmooth=1 # as sigma
SurfaceExclude=4 # in mm

# Gradient Calculation and Averaging
wb_command -cifti-correlation-gradient "$fMRI_in_fsAnat"_AtlasSubcortical_in_Gray_"$fMRIisospace".dconn.nii "$fMRI_in_fsAnat"_AtlasSubcortical_in_Gray_"$fMRIisospace"_corrgrad_s"$SurfacePresmooth"_se"$SurfaceExclude".dscalar.nii -left-surface "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject".L.midthickness."$LowResMesh"k_fs_LR.surf.gii -right-surface "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject".R.midthickness."$LowResMesh"k_fs_LR.surf.gii -mem-limit "$MemLimit" -surface-presmooth "$SurfacePresmooth" -surface-exclude "$SurfaceExclude"

log_Msg "Script END"






