#!/bin/bash

# just confirm our required variables are present
: ${CIRCLECI_API_KEY:?"Required Env Variable not found!"}
: ${CIRCLE_BUILD_NUM:?"Required Env Variable not found!"}
: ${CIRCLE_PROJECT_USERNAME:?"Required Env Variable not found!"}
: ${CIRCLE_PROJECT_REPONAME:?"Required Env Variable not found!"}
: ${CIRCLE_REPOSITORY_URL:?"Required Env Variable not found!"}
# CIRCLE_JOB is optional: ${CIRCLE_JOB:?"Required Env Variable not found!"}


if [ -z "$1" ]; then
	echo "Must provide Max Queue Time in *minutes* as script argument"
	exit 1
fi
max_time=$1
echo "This build will block until all previous builds complete."
echo "Max Queue Time: ${max_time} minutes."

my_dir="$(cd "$(dirname "$0")" && pwd -P)"
source "${my_dir}/circle_api.sh"
wait_time=0
loop_time=30
max_time_seconds=$((max_time * 60))
while true; do

	load_oldest_running_build_num
	if [ ${CIRCLE_BUILD_NUM} -le $oldest_running_build_num ]; then
		echo "Front of the line, WooHoo!, Build continuing"
		break
	else
		echo "This build (${CIRCLE_BUILD_NUM}) is queued, waiting for build number (${oldest_running_build_num}) to complete."
		echo "Total Queue time: ${wait_time} seconds."
	fi

	if [ $wait_time -ge $max_time_seconds ]; then
		echo "Max wait time exceeded, cancelling this build."
		cancel_current_build
		sleep 60 #waut for APi to cancel this job, rather than showiung as failure
		exit 1 # but just in case, fail job
	fi

	sleep $loop_time
	wait_time=$(( loop_time + wait_time ))
done
