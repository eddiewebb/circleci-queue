#!/bin/bash

# Default to github, but allow this to be overriden.
if [ -z $VCS_TYPE ]; then
	VCS_TYPE="github"
fi

load_oldest_running_build_num(){
	jobs_api_url_template="https://circleci.com/api/v1.1/project/${VCS_TYPE}/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}?circle-token=${CIRCLECI_API_KEY}&filter=running"
	#jobs_api_url_template="http://localhost:5000"

	#negative index grabs last (oldest) job in returned results.
	if [ -z ${CIRCLE_JOB} ];then
		echo "No Job variable, blocking on any runnin jobs for this project."
		oldest=`curl -s $jobs_api_url_template | jq '.[-1].build_num'`
	else
		echo "Only blocking for runnin jobs matching: ${CIRCLE_JOB}"
		oldest=`curl -s $jobs_api_url_template | jq ". | map(select(.build_parameters.CIRCLE_JOB==\"${CIRCLE_JOB}\")) | .[-1].build_num"`
	fi
	if [ -z $oldest ];then
		echo "API Call for existing jobs failed, failing this build.  Please check API token"
		exit 1
	elif [ "null" == "$oldest" ];then
		echo "No running builds found, this is likely a bug in queue script"
		exit 1
	else
		oldest_running_build_num=$oldest
	fi
}


cancel_current_build(){
	echo "Cancelleing build ${CIRCLE_BUILD_NUM}"
	cancel_api_url_template="https://circleci.com/api/v1.1/project/${VCS_TYPE}/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/${CIRCLE_BUILD_NUM}/cancel?circle-token=${CIRCLECI_API_KEY}"
	curl -s -X POST $cancel_api_url_template > /dev/null
}
