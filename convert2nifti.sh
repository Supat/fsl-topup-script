#!/bin/bash

INPUT_DIR=$1

dcm2niix -f %p_%i $INPUT_DIR

