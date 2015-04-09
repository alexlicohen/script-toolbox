# Import the BET'd T1 in fsAnat space to the HCP dir
fslreorient2std "$StudyFolder"/"$Subject"/mri/T1_brain.nii.gz >> "$HCPFolder"/T1_brain.fslreorient2std.mat
fslreorient2std "$StudyFolder"/"$Subject"/mri/T1_brain.nii.gz "$HCPFolder"/T1_brain.nii.gz

# Process the raw NIFTI BOLD data through FEAT, then FIX
### insert FEAT script? from the FEAT gui settings...
fix fMRI.feat /usr/local/fix/training_files/Standard.RData 20 -m