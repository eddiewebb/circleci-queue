# If a pattern is wrapped with slashes, remove them.
if [[ "$TAG_PATTERN" == /*/ ]]; then
    TAG_PATTERN=${TAG_PATTERN:1:-1}
fi
echo "Expecting CCI PAT TOKEN Named: ${CCI_API_KEY_NAME}"
CCI_TOKEN=${!CCI_API_KEY_NAME}

urlencode(){
    LC_WAS="${LC_ALL:-}"
    export LC_ALL=C
    string="$1"
    while [ -n "$string" ]; do
    tail="${string#?}"
    head="${string%$tail}"
    case "$head" in
        [-_.~A-Za-z0-9]) printf '%c' "$head" ;;
        *) printf '%%%02X' "'$head" ;;
    esac
    string="${tail}"
    done
    echo
    export LC_ALL="${LC_WAS}"
}

fetch(){
    echo "DEBUG: Making API Call to ${1}"    
    url=$1
    target=$2
    http_response=$(curl -s -X GET -H "Circle-Token:${CCI_TOKEN}" -H "Content-Type: application/json" -o "${target}" -w "%{http_code}" "${url}")
    if [ $http_response != "200" ]; then
        echo "ERROR: Server returned error code: $http_response"
        cat ${target}
        exit 1
    else
        echo "DEBUG: API Success"
    fi
}

load_variables(){
    # just confirm our required variables are present
    : ${CIRCLE_BUILD_NUM:?"Required Env Variable not found!"}
    : ${CIRCLE_PROJECT_USERNAME:?"Required Env Variable not found!"}
    : ${CIRCLE_PROJECT_REPONAME:?"Required Env Variable not found!"}
    : ${CIRCLE_REPOSITORY_URL:?"Required Env Variable not found!"}
    : ${CIRCLE_JOB:?"Required Env Variable not found!"}
    # Only needed for private projects
    if [ -z "${CCI_TOKEN}" ]; then
    echo "CCI_TOKEN not set. Private projects will be inaccessible."
    else
    fetch "${CIRCLECI_BASE_URL}/api/v2/me" "/tmp/me.cci"
    me=$(jq -e '.id' /tmp/me.cci)
    echo "Using API key for user: ${me} on host ${CIRCLECI_BASE_URL}"
    fi
    VCS_TYPE="${VCS_TYPE}"
}


fetch_filtered_active_builds(){
    if [ "${FILTER_BRANCH}" != "true" ];then
        echo "Orb parameter 'consider-branch' is false, will block previous builds on any branch." 
        jobs_api_url_template="${CIRCLECI_BASE_URL}/api/v1.1/project/${VCS_TYPE}/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}?filter=running"
    elif [ -n "${CIRCLE_TAG:x}" ] && [ "$TAG_PATTERN" != "" ]; then
        # I'm not sure why this is here, seems identical to above?
        echo "CIRCLE_TAG and orb parameter tag-pattern is set, fetch active builds"
        jobs_api_url_template="${CIRCLECI_BASE_URL}/api/v1.1/project/${VCS_TYPE}/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}?filter=running"
    else
        : ${CIRCLE_BRANCH:?"Required Env Variable not found!"}
        echo "Only blocking execution if running previous jobs on branch: ${CIRCLE_BRANCH}"
        jobs_api_url_template="${CIRCLECI_BASE_URL}/api/v1.1/project/${VCS_TYPE}/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/tree/$(urlencode "${CIRCLE_BRANCH}")?filter=running"
    fi

    if [ ! -z $TESTING_MOCK_RESPONSE ] && [ -f $TESTING_MOCK_RESPONSE ];then
        echo "Using test mock response"
        cat $TESTING_MOCK_RESPONSE > /tmp/jobstatus.json
    else
        fetch "$jobs_api_url_template" "/tmp/jobstatus.json"
        if [ -n "${CIRCLE_TAG:x}" ] && [ "$TAG_PATTERN" != "" ]; then
            jq "[ .[] | select((.build_num | . == \"${CIRCLE_BUILD_NUM}\") or (.vcs_tag | (. != null and test(\"${TAG_PATTERN}\"))) ) ]" /tmp/jobstatus.json >/tmp/jobstatus_tag.json
            mv /tmp/jobstatus_tag.json /tmp/jobstatus.json
        fi
        echo "API access successful"
    fi
}

augment_jobs_with_pipeline_data(){
    echo "Getting queue ordering"
    cp /tmp/jobstatus.json /tmp/augmented_jobstatus.json
    for workflow in `jq -r ".[] | .workflows.workflow_id //empty" /tmp/augmented_jobstatus.json | uniq`; do
        #get workflow to get pipeline...
        workflow_file=/tmp/workflow-${workflow}.json
        if [ ! -z $TESTING_MOCK_WORKFLOW_RESPONSES ] && [ -f $TESTING_MOCK_WORKFLOW_RESPONSES/${workflow}.json ]; then
            echo "Using test mock workflow response"
            cat $TESTING_MOCK_WORKFLOW_RESPONSES/${workflow}.json > ${workflow_file}
        else
            fetch "${CIRCLECI_BASE_URL}/api/v2/workflow/${workflow}" "${workflow_file}"
        fi
        pipeline_id=`jq -r '.pipeline_id' ${workflow_file}`
        pipeline_number=`jq -r '.pipeline_number' ${workflow_file}`
        echo "Workflow: ${workflow} is from pipeline #${pipeline_number}"
        cat /tmp/augmented_jobstatus.json | jq --arg pipeline_number "${pipeline_number}" --arg workflow "${workflow}" '(.[] | select(.workflows.workflow_id == $workflow) | .workflows) |= . + {pipeline_number:$pipeline_number}' > /tmp/augmented_jobstatus-${workflow}.json
        #DEBUG echo "new augmented_jobstatus:"
        #DEBUG cat /tmp/augmented_jobstatus-${workflow}.json
        mv /tmp/augmented_jobstatus-${workflow}.json /tmp/augmented_jobstatus.json
    done
}

update_comparables(){     
    fetch_filtered_active_builds

    augment_jobs_with_pipeline_data

    load_current_workflow_values
    
    JOB_NAME="${CIRCLE_JOB}"
    if [ "${JOB_REGEXP}" ] ;then
    JOB_NAME="${JOB_REGEXP}"
    fi

    # falsey parameters are empty strings, so always compare against 'true' 
    if [ "${BLOCK_WORKFLOW}" = "true" ] ;then
        echo "Orb parameter block-workflow is true."
        if [ "${ONLY_ON_WORKFLOW}" = "*" ]; then
            echo "This job will block until no previous workflows have *any* jobs running."
            oldest_running_build_num=`jq 'sort_by(.workflows.pipeline_number)| .[-1].build_num' /tmp/augmented_jobstatus.json`
            front_of_queue_pipeline_number=`jq 'sort_by(.workflows.pipeline_number)| .[-1].workflows.pipeline_number // empty' /tmp/augmented_jobstatus.json`
        else
            echo "Orb parameter only-on-workflow is true."
            echo "This job will block until no previous occurrences of workflow ${ONLY_ON_WORKFLOW} have *any* jobs running."
            oldest_running_build_num=`jq ". | map(select(.workflows.workflow_name| test(\"${ONLY_ON_WORKFLOW}\";\"sx\"))) | sort_by(.workflows.pipeline_number)| .[-1].build_num" /tmp/augmented_jobstatus.json`
            front_of_queue_pipeline_number=`jq ". | map(select(.workflows.workflow_name| test(\"${ONLY_ON_WORKFLOW}\";\"sx\"))) | sort_by(.workflows.pipeline_number)| .[-1].workflows.pipeline_number // empty" /tmp/augmented_jobstatus.json`
        fi
    else
        echo "Orb parameter block-workflow is false."
        echo "Only blocking execution if running previous jobs matching this job: ${JOB_NAME}"
        oldest_running_build_num=`jq ". | map(select(.workflows.job_name | test(\"${JOB_NAME}\";\"sx\"))) | sort_by(.pipeline_number)|  .[-1].build_num" /tmp/augmented_jobstatus.json`
        front_of_queue_pipeline_number=`jq ". | map(select(.workflows.job_name | test(\"${JOB_NAME}\";\"sx\"))) | sort_by(.pipeline_number)|  .[-1].workflows.pipeline_number // empty" /tmp/augmented_jobstatus.json`
    fi
    if [ -z $front_of_queue_pipeline_number ];then
        echo "API Call for existing jobs returned no matches. This means job is alone."
        if [[ $DEBUG == "true" ]];then
            echo "All running jobs:"
            cat /tmp/jobstatus.json || exit 0
            echo "All running jobs with created_at:"
            cat /tmp/augmented_jobstatus.json || exit 0
            echo "All workflow details."
            cat /tmp/workflow-*.json
            exit 1
        fi
    fi
}

load_current_workflow_values(){
    my_pipeline_number=`jq '.[] | select( .build_num == '"${CIRCLE_BUILD_NUM}"').workflows.pipeline_number' /tmp/augmented_jobstatus.json`
}

cancel_current_build(){
    echo "Cancelling build ${CIRCLE_BUILD_NUM}"
    cancel_api_url_template="${CIRCLECI_BASE_URL}/api/v1.1/project/${VCS_TYPE}/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/${CIRCLE_BUILD_NUM}/cancel?circle-token=${CCI_TOKEN}"
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
echo "Branch: ${ONLY_ON_BRANCH}"
if [[ "${ONLY_ON_BRANCH}" == "*" ]] || [[ "${ONLY_ON_BRANCH}" == "${CIRCLE_BRANCH}" ]]; then
    echo "${CIRCLE_BRANCH} queueable"
else
    echo "Queueing only happens on '${ONLY_ON_BRANCH}' branch, skipping queue"
    exit 0
fi

#
# Set values that wont change while we wait
# 
load_variables
echo "This build will block until all previous builds complete."
wait_time=0
loop_time=11
max_time_seconds=$((60*${max_time}))
echo "Max Queue Time: ${max_time_seconds} seconds."
#
# Queue Loop
#
confidence=0
while true; do
    update_comparables

    echo "This Workflow Pipeline #: $my_pipeline_number"
    echo "Oldest running Workflow Pipeline #: $front_of_queue_pipeline_number"

    if [[ -z "$front_of_queue_pipeline_number" ]] || [[ ! -z "$my_pipeline_number" ]] && [[ "$front_of_queue_pipeline_number" < "$my_pipeline_number" || "$front_of_queue_pipeline_number" == "$my_pipeline_number" ]] ; then
        # recent-jobs API does not include pending, so it is possible we queried in between a workflow transition, and we;re NOT really front of line.
        if [ $confidence -lt $CONFIDENCE_THRESHOLD ];then
            # To grow confidence, we check again with a delay.
            confidence=$((confidence+1))
            echo "API shows no conflicting jobs/workflows. However it is possible a previous workflow has pending jobs not yet visible in API. To avoid a race condition we will verify out place in queue."
            echo "Rerunning check ${confidence}/$CONFIDENCE_THRESHOLD"
        else
            echo "Front of the line, WooHoo!, Build continuing"
            break
        fi
    else
        # If we fail, reset confidence
        confidence=0
        echo "This build (${CIRCLE_BUILD_NUM}), pipeline (${my_pipeline_number}) is queued, waiting for build(${oldest_running_build_num}) pipeline (${front_of_queue_pipeline_number}) to complete."
        echo "Total Queue time: ${wait_time} seconds."
    fi

    if [ $wait_time -ge $max_time_seconds ]; then
    echo "Max wait time exceeded, considering response."
    if [ "${DONT_QUIT}" == "true" ];then
        echo "Orb parameter dont-quit is set to true, letting this job proceed!"
        exit 0
    else
        cancel_current_build
        sleep 5 # wait for API to cancel this job, rather than showing as failure
        exit 1 # but just in case, fail job
    fi
    fi

    sleep $loop_time
    wait_time=$(( loop_time + wait_time ))
done
