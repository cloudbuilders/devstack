#!/usr/bin/env bash

source ./stackrc
# Run everything in the exercises/ directory that isn't explicitly disabled

# comma separated list of script basenames to skip
# to refrain from exercising euca.sh use SKIP_EXERCISES=euca
SKIP_EXERCISES=${SKIP_EXERCISES:-""}

# Locate the scripts we should run
EXERCISE_DIR=$(dirname "$0")/exercises
basenames=$(for b in `ls $EXERCISE_DIR/*.sh`; do basename $b .sh; done)

# Track the state of each script
passes=""
failures=""
skips=""

# Loop over each possible script (by basename)
for script in $basenames; do
    if [[ "$SKIP_EXERCISES" =~ $script ]] ; then
        skips="$skips $script"
    else
        echo =========================
        echo Running $script
        echo =========================
        $EXERCISE_DIR/$script.sh
        if [[ $? -ne 0 ]] ; then
            failures="$failures $script"
        else
            passes="$passes $script"
        fi
    fi
done

# output status of exercise run
echo =========================
echo =========================
for script in $skips; do
    echo SKIP $script
done
for script in $passes; do
    echo PASS $script
done
for script in $failures; do
    echo FAILED $script
done

if [ -n "$failures" ] ; then
    exit 1
fi
