#!/bin/bash

#
# THis script uses many environment variables, some set from pipeline parameters. See orb yaml for source.
#

load_variables(){

    TMP_DIR=`mktemp -d`
    SHALLOW_JOBSTATUS_PATH=$TMP_DIR/jobstatus.json
    AUGMENTED_JOBSTATUS_PATH=$TMP_DIR/augmented_jobstatus.json
    echo "Block: $BLOCK_WORKFLOW"
    : ${MAX_TIME:?"Required Env Variable not found!"}
    wait_time=0
    loop_time=11
    max_time_seconds=$(( 60 * ${MAX_TIME} ))
    # just confirm our required variables are present
    : ${CIRCLE_BUILD_NUM:?"Required Env Variable not found!"}
    : ${CIRCLE_PROJECT_USERNAME:?"Required Env Variable not found!"}
    : ${CIRCLE_PROJECT_REPONAME:?"Required Env Variable not found!"}
    : ${CIRCLE_REPOSITORY_URL:?"Required Env Variable not found!"}
    : ${CIRCLE_JOB:?"Required Env Variable not found!"}
    VCS_TYPE="github"
    if [[ "$CIRCLE_REPOSITORY_URL" =~ .*bitbucket\.org.* ]]; then
        VCS_TYPE="bitbucket"
        echo "VCS_TYPE set to bitbucket"
    fi
    : ${VCS_TYPE:?"Required VCS TYPE not found! This is likely a bug in orb, please report."}
    : ${MY_PIPELINE_NUMBER:?"Required MY_PIPELINE_NUMBER not found! This is likely a bug in orb, please report."}
    
    # If a pattern is wrapped with slashes, remove them.
    if [[ "$TAG_PATTERN" == /*/ ]]; then
        TAG_PATTERN=${TAG_PATTERN:1:-1}
    fi
    echo "Expecting CCI Personal Access TOKEN Named: ${CCI_API_KEY_NAME}"
    CCI_TOKEN=${!CCI_API_KEY_NAME}
    # Only needed for private projects
    if [ -z "${CCI_TOKEN}" ]; then
        echo "CCI_TOKEN not set. Private projects and force cancel will not function."
    else
        fetch "${CIRCLECI_BASE_URL}/api/v2/me" "$TMP_DIR/me.cci"
        me=$(jq -e '.id' $TMP_DIR/me.cci)
        echo "Using API key for user: ${me} on host ${CIRCLECI_BASE_URL}"
    fi

    if [[ $DEBUG != "false" ]];then
     echo "Using Temp Dir: $TMP_DIR"
     #set
    fi
}


do_we_run(){
    if [ -n "${CIRCLE_TAG}" ] && [ -z "$TAG_PATTERN"  ]; then
        echo "TAG_PATTERN defined, but not on tagged run, skip queueing!"
        exit 0
    fi
    
    if [ ! -z "$CIRCLE_PR_REPONAME" ]; then
        echo "Queueing on forks is not supported. Skipping queue..."
        # It's important that we not fail here because it could cause issues on the main repo's branch
        exit 0
    fi
    if [[ "${ONLY_ON_BRANCH}" == "*" ]] || [[ "${ONLY_ON_BRANCH}" == "${CIRCLE_BRANCH}" ]]; then
        echo "${CIRCLE_BRANCH} matches queueable branch names"
    else
        echo "Queueing only enforced on branch '${ONLY_ON_BRANCH}', skipping queue"
        exit 0
    fi
}


update_active_run_data(){     
    fetch_filtered_active_builds
    augment_jobs_with_pipeline_data
    
    JOB_NAME="${CIRCLE_JOB}"
    if [ "${JOB_REGEXP}" ] ;then
        JOB_NAME="${JOB_REGEXP}"
    fi

    # falsey parameters are empty strings, so always compare against 'true' 
    if [ "${BLOCK_WORKFLOW}" != "false" ] ;then
        echo "Orb parameter block-workflow is true. Any previous (matching) pipelines with running workflows will block this entire workflow."
        if [ "${ONLY_ON_WORKFLOW}" = "*" ]; then
            echo "No workflow name filter. This job will block until no previous workflows with *any* name are running, regardless of job name."
            oldest_running_build_num=`jq 'sort_by(.workflows.pipeline_number)| .[0].build_num' $AUGMENTED_JOBSTATUS_PATH`
            front_of_queue_pipeline_number=`jq -r 'sort_by(.workflows.pipeline_number)| .[0].workflows.pipeline_number // empty' $AUGMENTED_JOBSTATUS_PATH`
        else
            echo "Orb parameter limit-workflow-name is provided."
            echo "This job will block until no previous occurrences of workflow ${ONLY_ON_WORKFLOW} are running, regardless of job name"
            oldest_running_build_num=`jq ". | map(select(.workflows.workflow_name| test(\"${ONLY_ON_WORKFLOW}\";\"sx\"))) | sort_by(.workflows.pipeline_number)| .[0].build_num" $AUGMENTED_JOBSTATUS_PATH`
            front_of_queue_pipeline_number=`jq -r ". | map(select(.workflows.workflow_name| test(\"${ONLY_ON_WORKFLOW}\";\"sx\"))) | sort_by(.workflows.pipeline_number)| .[0].workflows.pipeline_number // empty" $AUGMENTED_JOBSTATUS_PATH`
        fi
    else
        echo "Orb parameter block-workflow is false. Use Job level queueing."
        echo "Only blocking execution if running previous jobs matching this job: ${JOB_NAME}"
        oldest_running_build_num=`jq ". | map(select(.workflows.job_name | test(\"${JOB_NAME}\";\"sx\"))) | sort_by(.workflows.pipeline_number)|  .[0].build_num" $AUGMENTED_JOBSTATUS_PATH`
        front_of_queue_pipeline_number=`jq -r ". | map(select(.workflows.job_name | test(\"${JOB_NAME}\";\"sx\"))) | sort_by(.workflows.pipeline_number)|  .[0].workflows.pipeline_number // empty" $AUGMENTED_JOBSTATUS_PATH`
        if [[ "$DEBUG" != "false" ]];then
            echo "DEBUG: me: $MY_PIPELINE_NUMBER, front: $front_of_queue_pipeline_number"
        fi
    fi
    if [ -z $front_of_queue_pipeline_number ];then
        echo "API Call for existing jobs returned no matches. This means job is alone."
        if [[ $DEBUG != "false" ]];then
            echo "All running jobs:"
            cat $SHALLOW_JOBSTATUS_PATH || exit 0
            echo "All running jobs with created_at:"
            cat $AUGMENTED_JOBSTATUS_PATH || exit 0
            echo "All workflow details."
            cat /tmp/workflow-*.json || echo "Could not load workflows.."
            exit 1
        fi
    fi
}

fetch_filtered_active_builds(){
    JOB_API_SUFFIX="?filter=running&shallow=true"
    jobs_api_url_template="${CIRCLECI_BASE_URL}/api/v1.1/project/${VCS_TYPE}/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}${JOB_API_SUFFIX}"
    if [ "${FILTER_BRANCH}" == "false" ];then
        echo "Orb parameter 'this-branch-only' is false, will block previous builds on any branch." 
    else
        #branch filter
        : ${CIRCLE_BRANCH:?"Required Env Variable not found!"}
        echo "Only blocking execution if running previous jobs on branch: ${CIRCLE_BRANCH}"
        jobs_api_url_template="${CIRCLECI_BASE_URL}/api/v1.1/project/${VCS_TYPE}/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/tree/$(urlencode "${CIRCLE_BRANCH}")${JOB_API_SUFFIX}"
    fi

    if [ ! -z $TESTING_MOCK_RESPONSE ] && [ -f $TESTING_MOCK_RESPONSE ];then
        echo "Using test mock response"
        cat $TESTING_MOCK_RESPONSE > $SHALLOW_JOBSTATUS_PATH
    else
        fetch "$jobs_api_url_template" "$SHALLOW_JOBSTATUS_PATH"
    fi

    if [ -n "${CIRCLE_TAG}" ] && [ "$TAG_PATTERN" != "" ]; then
        echo "TAG_PATTERN variable non-empty, will only block pipelines with maching tag"
        jq "[ .[] | select((.build_num | . == \"${CIRCLE_BUILD_NUM}\") or (.vcs_tag | (. != null and test(\"${TAG_PATTERN}\"))) ) ]" $SHALLOW_JOBSTATUS_PATH >/tmp/jobstatus_tag.json
        mv /tmp/jobstatus_tag.json $SHALLOW_JOBSTATUS_PATH
    fi
}

augment_jobs_with_pipeline_data(){
    echo "Getting queue ordering"
    cp $SHALLOW_JOBSTATUS_PATH $AUGMENTED_JOBSTATUS_PATH
    for workflow in `jq -r ".[] | .workflows.workflow_id //empty" $AUGMENTED_JOBSTATUS_PATH | uniq`; do
        #get workflow to get pipeline...
        workflow_file=${TMP_DIR}/workflow-${workflow}.json
        if [ -f "$TESTING_MOCK_WORKFLOW_RESPONSES/${workflow}.json" ]; then
            echo "Using test mock workflow response"
            cat $TESTING_MOCK_WORKFLOW_RESPONSES/${workflow}.json > ${workflow_file}
        else
            fetch "${CIRCLECI_BASE_URL}/api/v2/workflow/${workflow}" "${workflow_file}"
        fi
        pipeline_id=`jq -r '.pipeline_id' ${workflow_file}`
        pipeline_number=`jq -r '.pipeline_number' ${workflow_file}`
        echo "Workflow: ${workflow} is from pipeline #${pipeline_number}"
        cat $AUGMENTED_JOBSTATUS_PATH | jq --arg pipeline_number "${pipeline_number}" --arg workflow "${workflow}" '(.[] | select(.workflows.workflow_id == $workflow) | .workflows) |= . + {pipeline_number:$pipeline_number}' > ${TMP_DIR}/augmented_jobstatus-${workflow}.json
        #DEBUG echo "new augmented_jobstatus:"
        #DEBUG cat ${TMP_DIR}/augmented_jobstatus-${workflow}.json
        mv ${TMP_DIR}/augmented_jobstatus-${workflow}.json $AUGMENTED_JOBSTATUS_PATH
    done
}

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
    if [[ $DEBUG != "false" ]];then
        echo "DEBUG: Making API Call to ${1}"    
    fi
    url=$1
    target=$2
    http_response=$(curl -s -X GET -H "Circle-Token:${CCI_TOKEN}" -H "Content-Type: application/json" -o "${target}" -w "%{http_code}" "${url}")
    if [ $http_response != "200" ]; then
        echo "ERROR: Server returned error code: $http_response"
        cat ${target}
        exit 1
    else
        if [[ $DEBUG != "false" ]];then
            echo "DEBUG: API Success"
        fi
    fi
}


cancel_build_num(){
    BUILD_NUM=$1
    echo "Cancelling build ${BUILD_NUM}"
    cancel_api_url_template="${CIRCLECI_BASE_URL}/api/v1.1/project/${VCS_TYPE}/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/${BUILD_NUM}/cancel?circle-token=${CCI_TOKEN}"
    curl -s -X POST $cancel_api_url_template > /dev/null
}





#
# MAIN LOGIC STARTS HERE
# 
load_variables
do_we_run #exit early if we can
echo "Max Queue Time: ${max_time_seconds} seconds."
#
# Queue Loop
#
confidence=0
while true; do
    # get running jobs, filtered to branch or tag, with pipeline ID
    update_active_run_data

    echo "This Job's Pipeline #: $MY_PIPELINE_NUMBER"
    echo "Front of Queue (fifo) Pipeline #: $front_of_queue_pipeline_number"

    if [[ -z "$front_of_queue_pipeline_number" ]] || [[ ! -z "$MY_PIPELINE_NUMBER" ]] && [[ "$front_of_queue_pipeline_number" == "$MY_PIPELINE_NUMBER" ]] ; then
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
        echo "This build (${CIRCLE_BUILD_NUM}), pipeline (${MY_PIPELINE_NUMBER}) is queued, waiting for build(${oldest_running_build_num}) pipeline (${front_of_queue_pipeline_number}) to complete."
        echo "Total Queue time: ${wait_time} seconds."
    fi

    if [ $wait_time -ge $max_time_seconds ]; then
        echo "Max wait time exceeded, fail or force cancel..."
        if [ "${DONT_QUIT}" != "false" ];then
            echo "Orb parameter dont-quit is set to true, letting this job proceed!"
            if [ "${FORCE_CANCEL_PREVIOUS}" != "false" ]; then
                "FEATURE NOT IMPLEMENTED"
                exit 1
            fi
            exit 0
        else
            if [ "$FAIL_INSTEAD_OF_CANCEL" != "true" ] ; then
                cancel_build_num $CIRCLE_BUILD_NUM
                sleep 5 # wait for API to cancel this job, rather than showing as failure
                # but just in case, fail job
            fi
            exit 1
        fi
    fi

    sleep $loop_time
    wait_time=$(( loop_time + wait_time ))
done
