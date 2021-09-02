
#
#.This query builds and determine our place in queue
#
main_loop(){
  load_variables
  max_time=<< parameters.time >>
  echo "This build will block until all previous builds complete."
  echo "Max Queue Time: ${max_time} minutes."
  wait_time=0
  loop_time=10
  max_time_seconds=$((max_time * 60))


  load_current_job_details #gives us our pipeline ID & Order



  #get recent pipeline for this project (optionally filtering on branch)
    # for each pipeline, is ID lower than ours?
      # if lower, get all workflows
        # for each workflow, are they running?
          # if job-specific running, do they contain my job?
          # v2 api sucks.




  #
  # Queue Loop
  #
  confidence=0
  while true; do
    update_comparables
    echo "This Workflow Timestamp: $my_commit_time"
    echo "Oldest Workflow Timestamp: $oldest_commit_time"
    if [[ "$oldest_commit_time" > "$my_commit_time" ]] || [[ "$oldest_commit_time" = "$my_commit_time" ]] ; then
      # API returns Y-M-D HH:MM (with 24 hour clock) so alphabetical string compare is accurate to timestamp compare as well
      # recent-jobs API does not include pending, so it is posisble we queried in between a workfow transition, and we;re NOT really front of line.
      if [ $confidence -lt <<parameters.confidence>> ];then
        # To grow confidence, we check again with a delay.
        confidence=$((confidence+1))
      else
        echo "Front of the line, WooHoo!, Build continuing"
        break
      fi
    else
      echo "This build (${CIRCLE_BUILD_NUM}) is queued, waiting for build number (${oldest_running_build_num}) to complete."
      echo "Total Queue time: ${wait_time} seconds."
    fi

    if [ $wait_time -ge $max_time_seconds ]; then
      echo "Max wait time exceeded, considering response."
      if [ "<<parameters.dont-quit>>" == "true" ];then
        echo "Orb parameter dont-quit is set to true, letting this job proceed!"
        exit 0
      else
        cancel_current_build
        sleep 10 # wait for API to cancel this job, rather than showing as failure
        exit 1 # but just in case, fail job
      fi
    fi

    sleep $loop_time
    wait_time=$(( loop_time + wait_time ))
  done

}



load_variables(){
  # just confirm our required variables are present
  : ${CIRCLE_BUILD_NUM:?"Required Env Variable not found!"}
  : ${CIRCLE_PROJECT_USERNAME:?"Required Env Variable not found!"}
  : ${CIRCLE_PROJECT_REPONAME:?"Required Env Variable not found!"}
  : ${CIRCLE_REPOSITORY_URL:?"Required Env Variable not found!"}
  : ${CIRCLE_JOB:?"Required Env Variable not found!"}
  : ${CIRCLE_WORKFLOW_ID:?"Required Env Variable not found!"}
  # Only needed for private projects
  if [ -z "$CIRCLECI_API_KEY" ]; then
    echo "ERROR: CIRCLECI_API_KEY not set. API will be inaccessible." >&2
    exit 1
  fi
  VCS_TYPE="<<parameters.vcs-type>>"
}

load_current_pipeline_info(){
  #get_api_payload "https://circleci.com/api/v2/project/${VCS_TYPE}/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/job/${CIRCLE_BUILD_NUM}" /tmp/current_workflow.json
  get_api_payload "https://circleci.com/api/v2/workflow/${CIRCLE_WORKFLOW_ID}" /tmp/current_workflow.json
  CIRCLE_PIPELINE_ID=$(jq '.pipeline_id' /tmp/current_workflow.json) #UUID
  CIRCLE_PIPELINE_NUMBER=$(jq '.pipeline_number' /tmp/current_workflow.json) #RelativeOrder
}


get_api_payload(){
  url=$1
  target=$2
  curl -X GET "${url}" -H "Accept: application/json" -H "Circle-Token: ${CIRCLECI_API_KEY}" > ${target}
  if [ $? -ne 0 ];then
    echo "ERROR: Curl command to ${url} failed. Response below." 
    cat $target
    exit 1
  fi
}


fetch_filtered_active_builds(){
  if [ "<<parameters.consider-branch>>" != "true" ];then
    echo "Orb parameter 'consider-branch' is false, will block previous builds on any branch."
    jobs_api_url_template="https://circleci.com/api/v1.1/project/${VCS_TYPE}/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}?circle-token=${CIRCLECI_API_KEY}&filter=running"
  else
    echo "Only blocking execution if running previous jobs on branch: ${CIRCLE_BRANCH}"
    : ${CIRCLE_BRANCH:?"Required Env Variable not found!"}
    jobs_api_url_template="https://circleci.com/api/v1.1/project/${VCS_TYPE}/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/tree/${CIRCLE_BRANCH}?circle-token=${CIRCLECI_API_KEY}&filter=running"
  fi

  if [ ! -z $TESTING_MOCK_RESPONSE ] && [ -f $TESTING_MOCK_RESPONSE ];then
    echo "Using test mock response"
    cat $TESTING_MOCK_RESPONSE > /tmp/jobstatus.json
  else
    echo "Attempting to access CircleCI api. If the build process fails after this step, ensure your CIRCLECI_API_KEY is set."
    curl -f -s $jobs_api_url_template > /tmp/jobstatus.json
    echo "API access successful"
  fi
}

fetch_active_workflows(){
  cp /tmp/jobstatus.json /tmp/augmented_jobstatus.json
  for workflow in `jq -r ".[] | .workflows.workflow_id" /tmp/augmented_jobstatus.json | uniq`
  do
    echo "Checking time of workflow: ${workflow}"
    workflow_file=/tmp/workflow-${workflow}.json
    if [ ! -z $TESTING_MOCK_WORKFLOW_RESPONSES ] && [ -f $TESTING_MOCK_WORKFLOW_RESPONSES/${workflow}.json ]; then
      echo "Using test mock workflow response"
      cat $TESTING_MOCK_WORKFLOW_RESPONSES/${workflow}.json > ${workflow_file}
    else
      curl -f -s "https://circleci.com/api/v2/workflow/${workflow}?circle-token=${CIRCLECI_API_KEY}" > ${workflow_file}
    fi
    created_at=`jq -r '.created_at' ${workflow_file}`
    echo "Workflow was created at: ${created_at}"
    cat /tmp/augmented_jobstatus.json | jq --arg created_at "${created_at}" --arg workflow "${workflow}" '(.[] | select(.workflows.workflow_id == $workflow) | .workflows) |= . + {created_at:$created_at}' > /tmp/augmented_jobstatus-${workflow}.json
    #DEBUG echo "new augmented_jobstatus:"
    #DEBUG cat /tmp/augmented_jobstatus-${workflow}.json
    mv /tmp/augmented_jobstatus-${workflow}.json /tmp/augmented_jobstatus.json
  done
}

update_comparables(){     
  fetch_filtered_active_builds

  fetch_active_workflows

  load_current_workflow_values

  # falsey parameters are empty strings, so always compare against 'true' 
  if [ "<<parameters.consider-job>>" != "true" ] || [ "<<parameters.block-workflow>>" = "true" ] ;then
    echo "Orb parameter block-workflow is true."
    echo "This job will block until no previous workflows have *any* jobs running."
    oldest_running_build_num=`jq 'sort_by(.workflows.created_at)| .[0].build_num' /tmp/augmented_jobstatus.json`
    oldest_commit_time=`jq 'sort_by(.workflows.created_at)| .[0].workflows.created_at' /tmp/augmented_jobstatus.json`
  else
    echo "Orb parameter block-workflow is false."
    echo "Only blocking execution if running previous jobs matching this job: ${CIRCLE_JOB}"
    oldest_running_build_num=`jq ". | map(select(.build_parameters.CIRCLE_JOB==\"${CIRCLE_JOB}\")) | sort_by(.workflows.created_at)|  .[0].build_num" /tmp/augmented_jobstatus.json`
    oldest_commit_time=`jq ". | map(select(.build_parameters.CIRCLE_JOB==\"${CIRCLE_JOB}\")) | sort_by(.workflows.created_at)|  .[0].workflows.created_at" /tmp/augmented_jobstatus.json`
  fi
  echo "Oldest job: $oldest_running_build_num"
  if [ -z $oldest_commit_time ];then
    echo "API Call for existing jobs failed, failing this build.  Please check API token"
    echo "All running jobs:"
    cat /tmp/jobstatus.json || exit 0
    echo "All running jobs with created_at:"
    cat /tmp/augmented_jobstatus.json || exit 0
    echo "All worfklow details."
    cat /tmp/workflow-*.json
    exit 1
  fi
}

load_current_workflow_values(){
   my_commit_time=`jq '.[] | select( .build_num == '"${CIRCLE_BUILD_NUM}"').workflows.created_at' /tmp/augmented_jobstatus.json`
}

cancel_current_build(){
  echo "Cancelleing build ${CIRCLE_BUILD_NUM}"
  cancel_api_url_template="https://circleci.com/api/v1.1/project/${VCS_TYPE}/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/${CIRCLE_BUILD_NUM}/cancel?circle-token=${CIRCLECI_API_KEY}"
  curl -s -X POST $cancel_api_url_template > /dev/null
}



#
# We can skip a few use cases without calling API
#
if [ ! -z "$CIRCLE_PR_REPONAME" ]; then
  echo "Queueing on forks is not supported. Skipping queue..."
  # It's important that we not fail here because it could cause issues on the main repo's branch
  exit 0
fi
if [ "<<parameters.only-on-branch>>" = "*" ] || [ "<<parameters.only-on-branch>>" = "${CIRCLE_BRANCH}" ]; then
  echo "${CIRCLE_BRANCH} queueable"
else
  echo "Queueing only happens on <<parameters.only-on-branch>> branch, skipping queue"
  exit 0
fi

