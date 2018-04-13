

VCS_TYPE="github"
if [[ *"bitbucket"* = repo_url ]]; then
	VCS_TYPE = "bitbucket"
fi

load_oldest_running_build_num(){
	jobs_api_url_template="https://circleci.com/api/v1.1/project/${VCS_TYPE}/${CIRCLE_USERNAME}/${CIRCLE_REPONAME}?circle-token=${CIRCLECI_API_KEY}&filter=running"
	#jobs_api_url_template="http://localhost:5000"
	
	#negative index grabs last (oldest) job in returned results.
	oldest=`curl -s $jobs_api_url_template | jq '.[-1].build_num'`
	if [ -z "$oldest" ];then
		echo $CIRCLE_BUILD_NUM
	else
		echo $oldest
	fi
}


cancel_current_build(){
	echo "Cancelleing build ${CIRCLE_BUILD_NUM}"
	cancel_api_url_template="https://circleci.com/api/v1.1/project/${VCS_TYPE}/${CIRCLE_USERNAME}/${CIRCLE_REPONAME}/${CIRCLE_BUILD_NUM}/cancel?circle-token=${CIRCLECI_API_KEY}"
	curl -X POST $cancel_api_url_template
}


