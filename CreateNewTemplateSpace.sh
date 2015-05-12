#!/bin/bash
set -e
#set -x


# Requirements for this script
#  installed versions of: FSL (version 5.0.6), wb_command
#  environment: FSLDIR , HCPPIPEDIR added to path

# --------------------------------------------------------------------------------
#  Usage Description Function
# --------------------------------------------------------------------------------

show_usage() {
    echo " This is a basic script to add new resolution-templates to an HCP Pipelines repository"
    echo " NOTE: This would have to be done on each machine and/or the generated files copied "
    echo "       from the Pipelines/global/templates/standard_mesh_atlases dir"
    echo ""
    echo " Usage:"
    echo " 	  CreateNewTemplateSpace.sh TargetNumberOfVertices ShortNameForTargetVolume (e.g., 32 for 32492)"
    echo "    i.e.: CreateNewTemplateSpace.sh 8000 8"
    exit 1
}


if [ $# -eq 0 ] ; then show_usage; exit 0; fi

NumberOfVertices=${1}
NewMesh=${2}

TemplateFolder="${HCPPIPEDIR}/global/templates/standard_mesh_atlases"
OriginalMesh="164"
SubcorticalLabelTable="${HCPPIPEDIR}/global/config/FreeSurferSubcorticalLabelTableLut.txt"

wb_command -surface-create-sphere ${NumberOfVertices} ${TemplateFolder}/R.sphere.${NewMesh}k_fs_LR.surf.gii
wb_command -surface-flip-lr ${TemplateFolder}/R.sphere.${NewMesh}k_fs_LR.surf.gii ${TemplateFolder}/L.sphere.${NewMesh}k_fs_LR.surf.gii

wb_command -set-structure ${TemplateFolder}/R.sphere.${NewMesh}k_fs_LR.surf.gii CORTEX_RIGHT
wb_command -set-structure ${TemplateFolder}/L.sphere.${NewMesh}k_fs_LR.surf.gii CORTEX_LEFT

echo ""
echo "The new resolution-template labeled ${NewMesh}k_fs_LR will have the following characteristics:"
wb_command -surface-information ${TemplateFolder}/R.sphere.${NewMesh}k_fs_LR.surf.gii | sed -n '3,4p'
wb_command -surface-information ${TemplateFolder}/R.sphere.${NewMesh}k_fs_LR.surf.gii | sed -n '7,10p'
echo ""

NewResolution=`wb_command -surface-information ${TemplateFolder}/R.sphere.${NewMesh}k_fs_LR.surf.gii | grep Mean | awk '{print $2}' | awk -F "." '{print $1}'`

flirt -interp spline -in ${TemplateFolder}/Avgwmparc.nii.gz -ref ${TemplateFolder}/Avgwmparc.nii.gz -applyisoxfm ${NewResolution} -out ${TemplateFolder}/Atlas_ROIs.${NewResolution}.nii.gz
applywarp --rel --interp=nn -i ${TemplateFolder}/Avgwmparc.nii.gz -r ${TemplateFolder}/Atlas_ROIs.${NewResolution}.nii.gz --premat=$FSLDIR/etc/flirtsch/ident.mat -o ${TemplateFolder}/Atlas_ROIs.${NewResolution}.nii.gz

wb_command -volume-label-import ${TemplateFolder}/Atlas_ROIs.${NewResolution}.nii.gz ${SubcorticalLabelTable} ${TemplateFolder}/Atlas_ROIs.${NewResolution}.nii.gz -discard-others -drop-unused-labels



for Hemisphere in L R ; do
  wb_command -metric-resample ${TemplateFolder}/${Hemisphere}.atlasroi.${OriginalMesh}k_fs_LR.shape.gii ${TemplateFolder}/fsaverage.${Hemisphere}_LR.spherical_std.${OriginalMesh}k_fs_LR.surf.gii ${TemplateFolder}/${Hemisphere}.sphere.${NewMesh}k_fs_LR.surf.gii BARYCENTRIC ${TemplateFolder}/${Hemisphere}.atlasroi.${NewMesh}k_fs_LR.shape.gii -largest
  wb_command -surface-cut-resample ${TemplateFolder}/colin.cerebral.${Hemisphere}.flat.${OriginalMesh}k_fs_LR.surf.gii ${TemplateFolder}/fsaverage.${Hemisphere}_LR.spherical_std.${OriginalMesh}k_fs_LR.surf.gii ${TemplateFolder}/${Hemisphere}.sphere.${NewMesh}k_fs_LR.surf.gii ${TemplateFolder}/colin.cerebral.${Hemisphere}.flat.${NewMesh}k_fs_LR.surf.gii
done