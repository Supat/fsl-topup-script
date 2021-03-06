#!/bin/bash

if [ $# -eq 0 ]
then
	echo "No image input."
	echo "Usage: ./preprocessing.sh [structural image] [functional AP image] [functional PA image] [scouting image] [mask directory]"
	exit 1
fi

if [ $# -eq 5 ]
then
	STRUCTURAL_IMAGE=$1
	FUNCTIONAL_IMAGE=$2
	AP_IMAGE=$FUNCTIONAL_IMAGE
	PA_IMAGE=$3
	SCOUT_IMAGE=$4
	MASK_DIR=$5
else
	STRUCTURAL_IMAGE=$1
	FUNCTIONAL_IMAGE=$2
	AP_IMAGE=$3
	PA_IMAGE=$4
	SCOUT_IMAGE=$5
	MASK_DIR=$6
fi

AP_NAME=$(basename $AP_IMAGE ".nii") || AP_NAME=$(basename $AP_IMAGE ".nii.gz")
PA_NAME=$(basename $PA_IMAGE ".nii") || PA_NAME=$(basename $PA_IMAGE ".nii.gz")

# Generate acquisition parameter files
ACQPARAM_FILE="acqparams.txt"
if [ -f "$ACQPARAM_FILE" ]; then
	rm "$ACQPARAM_FILE"
fi
touch "$ACQPARAM_FILE"

echo "0 -1 0 $(cat ${AP_NAME}.json | grep "TotalReadoutTime" | grep -Eo "[0-9]+([.][0-9]+)")" >> $ACQPARAM_FILE
echo "0 1 0 $(cat ${PA_NAME}.json | grep "TotalReadoutTime" | grep -Eo "[0-9]+([.][0-9]+)")" >> $ACQPARAM_FILE

# Extract b0 volumes from AP and PA
AP_B0_VOLUME="AP_b0"
PA_B0_VOLUME="PA_b0"
fslroi $AP_IMAGE $AP_B0_VOLUME 0 1
fslroi $PA_IMAGE $PA_B0_VOLUME 0 1

# Create TOPUP input image
TOPUP_INPUT_IMAGE="AP_PA"
fslmerge -t $TOPUP_INPUT_IMAGE $AP_B0_VOLUME $PA_B0_VOLUME
#fslmerge -t $TOPUP_INPUT_IMAGE $AP_IMAGE $PA_IMAGE
fslmaths $TOPUP_INPUT_IMAGE -mul 0 -add 1 -Tmin ${TOPUP_INPUT_IMAGE}_mask
fslmaths $TOPUP_INPUT_IMAGE -abs -add 1 -mas ${TOPUP_INPUT_IMAGE}_mask -dilM -dilM -dilM -dilM -dilM $TOPUP_INPUT_IMAGE

# Create TOPUP correction fieldmap
TOPUP_OUTPUT_IMAGE="topup_AP_PA_b0"
topup --imain=$TOPUP_INPUT_IMAGE --datain=$ACQPARAM_FILE --config=b02b0.cnf --out=$TOPUP_OUTPUT_IMAGE --rbmout=MotionMatrix --dfout=WarpField --jacout=Jacobian

# Unwarp image in j direction
dimtOne=`fslval $AP_B0_VOLUME dim4`
VolumeNumber=$(($dimtOne + 1))
  vnum=`zeropad $VolumeNumber 2`
flirt -dof 6 -interp spline -in $SCOUT_IMAGE -ref $PA_B0_VOLUME -omat SBRef2PA_B0.mat -out SBRef2PA_B0
convert_xfm -omat SBRef2WarpField.mat -concat MotionMatrix_${vnum}.mat SBRef2PA_B0.mat
convertwarp --relout --rel -r $PA_B0_VOLUME --premat=SBRef2WarpField.mat --warp1=WarpField_${vnum} --out=WarpField
imcp Jacobian_${vnum} Jacobian

# Apply TOPUP correction fieldmap to AP functional image
INPUT_IMAGE=$(basename $FUNCTIONAL_IMAGE ".nii") || INPUT_IMAGE=$(basename $FUNCTIONAL_IMAGE ".nii.gz")
#applytopup --imain=$INPUT_IMAGE --inindex=1 --datain=$ACQPARAM_FILE --topup=$TOPUP_OUTPUT_IMAGE --out=${INPUT_IMAGE}_corrected --method=jac
VolumeNumber=$((0 + 1))
  vnum=`zeropad $VolumeNumber 2`
applywarp --rel --interp=spline -i $INPUT_IMAGE -r ${TOPUP_INPUT_IMAGE}_mask --premat=MotionMatrix_${vnum}.mat -w WarpField_${vnum} -o ${INPUT_IMAGE}_corrected
fslmaths ${INPUT_IMAGE}_corrected -mul Jacobian_${vnum} ${INPUT_IMAGE}_corrected_jac

# Apply TOPUP correction fieldmap to PA functional image
INPUT_IMAGE_PA=$(basename $PA_IMAGE ".nii") || INPUT_IMAGE_PA=$(basename $PA_IMAGE ".nii.gz")
#applytopup --imain=$INPUT_IMAGE_PA --inindex=1 --datain=$ACQPARAM_FILE --topup=$TOPUP_OUTPUT_IMAGE --out=${INPUT_IMAGE_PA}_corrected --method=jac
VolumeNumber=$(($dimtOne + 1))
  vnum=`zeropad $VolumeNumber 2`
applywarp --rel --interp=spline -i $INPUT_IMAGE_PA -r ${TOPUP_INPUT_IMAGE}_mask --premat=MotionMatrix_${vnum}.mat -w WarpField_${vnum} -o ${INPUT_IMAGE_PA}_corrected
fslmaths ${INPUT_IMAGE_PA}_corrected -mul Jacobian_${vnum} ${INPUT_IMAGE_PA}_corrected_jac

# Apply TOPUP correction fieldmap to scout image
applywarp --rel --interp=spline -i $SCOUT_IMAGE -r $SCOUT_IMAGE -w WarpField -o ${SCOUT_IMAGE}_corrected
fslmaths ${SCOUT_IMAGE}_corrected -mul Jacobian ${SCOUT_IMAGE}_corrected_jac

# Quality Assurance
if [ -e qa.txt ] ; then rm -f qa.txt ; fi
echo "cd `pwd`" >> qa.txt
echo "# Inspect results of various corrections (phase one)" >> qa.txt
echo "fsleyes $AP_IMAGE ${INPUT_IMAGE}_corrected ${INPUT_IMAGE}_corrected_jac" >> qa.txt
echo "# Inspect results of various corrections (phase two)" >> qa.txt
echo "fsleyes $PA_IMAGE ${INPUT_IMAGE_PA}_corrected ${INPUT_IMAGE_PA}_corrected_jac" >> qa.txt

# Extract brain and binary mask with 0.3 fractional intensity threshold
bet "$STRUCTURAL_IMAGE" "${STRUCTURAL_IMAGE}_brain_f03" -f 0.3 -g 0 -m

# Perform preprocessing using FEAT
FUNC_INPUT=$(pwd)/${INPUT_IMAGE}_corrected.nii.gz
BRAIN_INPUT=$(pwd)/${STRUCTURAL_IMAGE}_brain_f03.nii.gz
cp feat_preprocessing.fsf ${INPUT_IMAGE}.fsf
sed -i '' "s|<FUNCTIONAL>|$FUNC_INPUT|g" ${INPUT_IMAGE}.fsf
sed -i '' "s|<BRAIN>|$BRAIN_INPUT|g" ${INPUT_IMAGE}.fsf
sed -i '' "s|<OUTPUT>|$INPUT_IMAGE|g" ${INPUT_IMAGE}.fsf
feat ${INPUT_IMAGE}.fsf

# Perform preprocessing using FEAT on PA functional image
FUNC_INPUT=$(pwd)/${INPUT_IMAGE_PA}_corrected.nii.gz
BRAIN_INPUT=$(pwd)/${STRUCTURAL_IMAGE}_brain_f03.nii.gz
cp feat_preprocessing.fsf ${INPUT_IMAGE_PA}.fsf
sed -i '' "s|<FUNCTIONAL>|$FUNC_INPUT|g" ${INPUT_IMAGE_PA}.fsf
sed -i '' "s|<BRAIN>|$BRAIN_INPUT|g" ${INPUT_IMAGE_PA}.fsf
sed -i '' "s|<OUTPUT>|$INPUT_IMAGE_PA|g" ${INPUT_IMAGE_PA}.fsf
feat ${INPUT_IMAGE_PA}.fsf

# Register preprocessed functional data
#flirt -in ${INPUT_IMAGE}.feat/filtered_func_data.nii.gz -ref $FSLDIR/data/standard/MNI152_T1_1mm.nii.gz -applyxfm -init ${INPUT_IMAGE}.feat/reg/example_func2standard.mat -out registered_filtered_func_data.nii.gz
cp ${INPUT_IMAGE}.feat/filtered_func_data.nii.gz AP_filtered_func_data.nii.gz

# Register preprocessed PA functional data
#flirt -in ${INPUT_IMAGE_PA}.feat/filtered_func_data.nii.gz -ref $FSLDIR/data/standard/MNI152_T1_1mm.nii.gz -applyxfm -init ${INPUT_IMAGE_PA}.feat/reg/example_func2standard.mat -out registered_PA_filtered_func_data.nii.gz
cp ${INPUT_IMAGE_PA}.feat/filtered_func_data.nii.gz PA_filtered_func_data.nii.gz

# Create transformation matrix from standard to AP native space
flirt -in $AP_B0_VOLUME -ref $FSLDIR/data/standard/MNI152_T1_1mm.nii.gz -omat AP_native2standard.mat -out registered_AP_B0_VOLUME
convert_xfm -omat AP_standard2native.mat -inverse AP_native2standard.mat

# Create transformation matrix from standard to PA native space
flirt -in $PA_B0_VOLUME -ref $FSLDIR/data/standard/MNI152_T1_1mm.nii.gz -omat PA_native2standard.mat -out registered_PA_B0_VOLUME
convert_xfm -omat PA_standard2native.mat -inverse PA_native2standard.mat

# Extract signals from ROIs
if [ -d "timeseries" ]; then
	rm -r "timeseries"
fi
mkdir "timeseries"
for MASK in $(ls $MASK_DIR); do
	TS_NAME=$(basename $MASK ".nii") || TS_NAME=$(basename $MASK ".nii.gz")

	# Transform mask from standard space to native space
	flirt -in $MASK_DIR$MASK -ref $FSLDIR/data/standard/MNI152_T1_1mm.nii.gz -applyxfm -init AP_standard2native.mat -out ${MASK}_AP_native
	fslmaths ${MASK}_AP_native -thr 0.9 -bin ${MASK}_AP_native

	fslmeants -i AP_filtered_func_data.nii.gz -m ${MASK}_AP_native -o timeseries/${TS_NAME}.txt
done
if [ -f "label.txt" ]; then
	rm "label.txt"
fi
ls $MASK_DIR | grep HMAT > label.txt
cd timeseries
paste $(ls | grep HMAT) > fslnets_ts.txt
cd -
mv timeseries/fslnets_ts.txt fslnets_ts.txt

# Extract signals from PA ROIs
if [ -d "timeseries_PA" ]; then
	rm -r "timeseries_PA"
fi
mkdir "timeseries_PA"
for MASK in $(ls $MASK_DIR); do
	TS_NAME=$(basename $MASK ".nii") || TS_NAME=$(basename $MASK ".nii.gz")

	# Transform mask from standard space to native space
	flirt -in $MASK_DIR$MASK -ref $FSLDIR/data/standard/MNI152_T1_1mm.nii.gz -applyxfm -init PA_standard2native.mat -out ${MASK}_PA_native
	fslmaths ${MASK}_PA_native -thr 0.9 -bin ${MASK}_PA_native

	fslmeants -i PA_filtered_func_data.nii.gz -m ${MASK}_PA_native -o timeseries_PA/${TS_NAME}.txt
done
if [ -f "label_PA.txt" ]; then
	rm "label_PA.txt"
fi
ls $MASK_DIR | grep HMAT > label_PA.txt
cd timeseries_PA
paste $(ls | grep HMAT) > fslnets_ts_PA.txt
cd -
mv timeseries_PA/fslnets_ts_PA.txt fslnets_ts_PA.txt