#!/bin/bash

if [ $# -eq 0 ]
then
	echo "No image input."
	exit 1
fi

if [ $# -eq 3 ]
then
	STRUCTURAL_IMAGE=$1
	FUNCTIONAL_IMAGE=$2
	AP_IMAGE=$FUNCTIONAL_IMAGE
	PA_IMAGE=$3
else
	STRUCTURAL_IMAGE=$1
	FUNCTIONAL_IMAGE=$2
	AP_IMAGE=$3
	PA_IMAGE=$4
fi

AP_NAME=$(basename $AP_IMAGE ".nii") || AP_NAME=$(basename $AP_IMAGE ".nii.gz")
PA_NAME=$(basename $PA_IMAGE ".nii") || PA_NAME=$(basename $PA_IMAGE ".nii.gz")

# Generate acquisition parameter files
ACQPARAM_FILE="acqparams.txt"
if [ -f "$ACQPARAM_FILE" ]; then
	rm "$ACQPARAM_FILE"
else
	touch "$ACQPARAM_FILE"
fi

echo "0 -1 0 $(cat ${AP_NAME}.json | grep "TotalReadoutTime" | grep -Eo "[0-9]+([.][0-9]+)")" >> $ACQPARAM_FILE
echo "0 1 0 $(cat ${PA_NAME}.json | grep "TotalReadoutTime" | grep -Eo "[0-9]+([.][0-9]+)")" >> $ACQPARAM_FILE

# Extract b0 volumes from AP and PA
AP_B0_VOLUME="AP_b0"
PA_B0_VOLUME="PA_b0"
fslroi $AP_IMAGE $AP_B0_VOLUME 0 1
fslroi $PA_IMAGE $PA_B0_VOLUME 0 1

# Create TOPUP input image
TOPUP_INPUT_IMAGE="AP_PA_b0"
fslmerge -t $TOPUP_INPUT_IMAGE $AP_B0_VOLUME $PA_B0_VOLUME

# Create TOPUP correction fieldmap
TOPUP_OUTPUT_IMAGE="topup_AP_PA_b0"
topup --imain=$TOPUP_INPUT_IMAGE --datain=$ACQPARAM_FILE --config=b02b0.cnf --out=$TOPUP_OUTPUT_IMAGE

# Apply TOPUP correction fieldmap to AP functional image
INPUT_IMAGE=$(basename $FUNCTIONAL_IMAGE ".nii") || INPUT_IMAGE=$(basename $FUNCTIONAL_IMAGE ".nii.gz")
applytopup --imain=$INPUT_IMAGE --inindex=1 --datain=$ACQPARAM_FILE --topup=$TOPUP_OUTPUT_IMAGE --out=${INPUT_IMAGE}_corrected --method=jac

# Extract brain and binary mask with 0.3 fractional intensity threshold
bet "$STRUCTURAL_IMAGE" "${STRUCTURAL_IMAGE}_brain_f03" -f 0.3 -g 0 -m


