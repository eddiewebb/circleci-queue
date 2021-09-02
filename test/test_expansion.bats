#!/usr/bin/env bats

# load custom assertions and functions
load bats_helper


# setup is run beofre each test
function setup {
  INPUT_PROJECT_CONFIG=${BATS_TMPDIR}/input_config-${BATS_TEST_NUMBER}
  PROCESSED_PROJECT_CONFIG=${BATS_TMPDIR}/packed_config-${BATS_TEST_NUMBER} 
  JSON_PROJECT_CONFIG=${BATS_TMPDIR}/json_config-${BATS_TEST_NUMBER} 
	echo "#using temp file ${BATS_TMPDIR}/"

  # the name used in example config files.
  INLINE_ORB_NAME="queue"


  if [ -z "$BATS_IMPORT_DEV_ORB" ]; then
    echo "#Using \`inline\` orb assembly, to test against published orb, set BATS_IMPORT_DEV_ORB to fully qualified path" >&3
  else
    echo "#BATS_IMPORT_DEV_ORB env var is set, all config will be tested against imported orb $BATS_IMPORT_DEV_ORB" >&3
  fi
}


@test "Job: full job expands properly" {
  # given
  process_config_with test/inputs/fulljob.yml
  export TESTING_MOCK_RESPONSE=test/api/jobs/onepreviousjob-differentname.json
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows

  # when
  assert_jq_match '.jobs | length' 1 #only 1 job
  assert_jq_match '.jobs["Single File"].steps | length' 1 #only 1 steps
}


@test "Command: Input parameters are respected by command" {
  # given
  process_config_with test/inputs/command-non-default.yml

  # when
  assert_jq_match '.jobs | length' 1 #only 1 job
  assert_jq_match '.jobs["build"].steps | length' 1 #only 1 steps

  run jq -r '.jobs["build"].steps[0].run.command' $JSON_PROJECT_CONFIG

  assert_contains_text "max_time=1"

}

@test "Default job sets block workflow properly" {
  # given
  process_config_with test/inputs/fulljob.yml

  # when
  assert_jq_match '.jobs | length' 1 #only 1 job
  assert_jq_match '.jobs["Single File"].steps | length' 1 #only 1 steps

  jq -r '.jobs["Single File"].steps[0].run.command' $JSON_PROJECT_CONFIG > ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash

  export CIRCLECI_API_KEY="madethisup"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_JOB="singlejob"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_BRANCH="madethisup"

  run bash ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash
  assert_contains_text "Orb parameter block-workflow is true."
}

@test "Race condition on previous workflow does not fool us" {
  # given
  process_config_with test/inputs/command-defaults.yml
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows

  # when
  assert_jq_match '.jobs | length' 1 #only 1 job
  assert_jq_match '.jobs["build"].steps | length' 1 #only 1 steps

  jq -r '.jobs["build"].steps[0].run.command' $JSON_PROJECT_CONFIG > ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash

  export CIRCLECI_API_KEY="madethisup"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_JOB="singlejob"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_BRANCH="madethisup"
  export CIRCLE_PR_REPONAME=""

  # set API Payload to temp location
  export TESTING_MOCK_RESPONSE=/tmp/dynamic_response.json
  # set initial response to mimic in-btween race condition, no running jobs
  cp test/api/jobs/nopreviousjobs.json /tmp/dynamic_response.json
  # in 11 seconds (> 10) switch to return the running job BACKGROUND PROCESS
  (sleep 11 && cp test/api/jobs/onepreviousjobsamename.json /tmp/dynamic_response.json) &

  run bash ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash


  assert_contains_text "Max Queue Time: 1 minutes"
  assert_contains_text "Rerunning check 1/1" 
  assert_contains_text "This build (${CIRCLE_BUILD_NUM}) is queued, waiting for build number (3) to complete."
  assert_contains_text "Max wait time exceeded"
  assert_contains_text "Cancelleing build 2"
  [[ "$status" == "1" ]]
}


@test "Command: script will proceed with no previous jobs" {
  # given
  process_config_with test/inputs/command-defaults.yml
  export TESTING_MOCK_RESPONSE=test/api/jobs/nopreviousjobs.json
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows

  # when
  assert_jq_match '.jobs | length' 1 #only 1 job
  assert_jq_match '.jobs["build"].steps | length' 1 #only 1 steps

  jq -r '.jobs["build"].steps[0].run.command' $JSON_PROJECT_CONFIG > ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash

  export CIRCLECI_API_KEY="madethisup"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_JOB="singlejob"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_BRANCH="madethisup"
  export CIRCLE_PR_REPONAME=""
  run bash ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash


  assert_contains_text "Max Queue Time: 1 minutes"
  assert_contains_text "Front of the line, WooHoo!, Build continuing"
  [[ "$status" == "0" ]]

}

@test "Command: script will proceed with previous job of different name" {
  # given
  process_config_with test/inputs/command-defaults.yml
  export TESTING_MOCK_RESPONSE=test/api/jobs/onepreviousjob-differentname.json
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows

  # when
  assert_jq_match '.jobs | length' 1 #only 1 job
  assert_jq_match '.jobs["build"].steps | length' 1 #only 1 steps

  jq -r '.jobs["build"].steps[0].run.command' $JSON_PROJECT_CONFIG > ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash

  export CIRCLECI_API_KEY="madethisup"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_JOB="singlejob"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_BRANCH="madethisup"
  export CIRCLE_PR_REPONAME=""
  run bash ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash


  assert_contains_text "Max Queue Time: 1 minutes"
  assert_contains_text "Front of the line, WooHoo!, Build continuing"
  [[ "$status" == "0" ]]
}

@test "Command: script will WAIT with previous job of same name" {
  # given
  process_config_with test/inputs/command-defaults.yml
  export TESTING_MOCK_RESPONSE=test/api/jobs/onepreviousjobsamename.json
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows

  # when
  assert_jq_match '.jobs | length' 1 #only 1 job
  assert_jq_match '.jobs["build"].steps | length' 1 #only 1 steps

  jq -r '.jobs["build"].steps[0].run.command' $JSON_PROJECT_CONFIG > ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash

  export CIRCLECI_API_KEY="madethisup"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_JOB="singlejob"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_BRANCH="madethisup"
  export CIRCLE_PR_REPONAME=""
  run bash ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash


  assert_contains_text "Max Queue Time: 1 minutes"
  assert_contains_text "Max wait time exceeded"
  assert_contains_text "Cancelleing build 2"
  [[ "$status" == "1" ]]
}


@test "Command: script with dont-quit will not fail current job" {
  # given
  process_config_with test/inputs/command-non-default.yml
  export TESTING_MOCK_RESPONSE=test/api/jobs/onepreviousjobsamename.json
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows

  # when
  assert_jq_match '.jobs | length' 1 #only 1 job
  assert_jq_match '.jobs["build"].steps | length' 1 #only 1 steps

  jq -r '.jobs["build"].steps[0].run.command' $JSON_PROJECT_CONFIG > ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash

  export CIRCLECI_API_KEY="madethisup"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_JOB="singlejob"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_BRANCH="madethisup"
  export CIRCLE_PR_REPONAME=""
  run bash ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash


  assert_contains_text "Max Queue Time: 1 minutes"
  assert_contains_text "Max wait time exceeded"
  assert_contains_text "Orb parameter dont-quit is set to true, letting this job proceed!"
  [[ "$status" == "0" ]]
}



@test "Command: script will consider branch" {
  # given
  process_config_with test/inputs/command-non-default.yml
  export TESTING_MOCK_RESPONSE=test/api/jobs/nopreviousjobs.json
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows

  # when
  assert_jq_match '.jobs | length' 1 #only 1 job
  assert_jq_match '.jobs["build"].steps | length' 1 #only 1 steps

  jq -r '.jobs["build"].steps[0].run.command' $JSON_PROJECT_CONFIG > ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash

  export CIRCLECI_API_KEY="madethisup"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_BRANCH="somespecialbranch"
  export CIRCLE_JOB="singlejob"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_PR_REPONAME=""
  run bash ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash


  assert_contains_text "Max Queue Time: 1 minutes"
  assert_contains_text "Orb parameter 'consider-branch' is false, will block previous builds on any branch"
  assert_contains_text "Front of the line, WooHoo!, Build continuing"
  [[ "$status" == "0" ]]

}


@test "Command: script will skip queueing on branches that don't match filter" {
  # given
  process_config_with test/inputs/command-filter-branch.yml
  export TESTING_MOCK_RESPONSE=test/api/jobs/nopreviousjobs.json #Response shouldn't matter as we're ending early
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows

  # when
  assert_jq_match '.jobs | length' 1 #only 1 job
  assert_jq_match '.jobs["build"].steps | length' 1 #only 1 steps

  jq -r '.jobs["build"].steps[0].run.command' $JSON_PROJECT_CONFIG > ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash

  export CIRCLECI_API_KEY="madethisup"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_BRANCH="dev"
  export CIRCLE_JOB="singlejob"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_PR_REPONAME=""
  run bash ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash


  assert_contains_text "Queueing only happens on master branch, skipping queue"
  assert_text_not_found "Max Queue Time: 1 minutes"
  [[ "$status" == "0" ]]

}

@test "Command: script will consider branch default" {
  # given
  process_config_with test/inputs/command-defaults.yml
  export TESTING_MOCK_RESPONSE=test/api/jobs/nopreviousjobs.json #branch filtereing handles by API, so return no matching builds
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows

  # when
  assert_jq_match '.jobs | length' 1 #only 1 job
  assert_jq_match '.jobs["build"].steps | length' 1 #only 1 steps

  jq -r '.jobs["build"].steps[0].run.command' $JSON_PROJECT_CONFIG > ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash

  export CIRCLECI_API_KEY="madethisup"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_BRANCH="somespecialbranch"
  export CIRCLE_JOB="singlejob"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_PR_REPONAME=""
  run bash ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash


  assert_contains_text "${CIRCLE_BRANCH} queueable"
  assert_contains_text "Max Queue Time: 1 minutes"
  assert_contains_text "Only blocking execution if running previous jobs on branch: ${CIRCLE_BRANCH}"
  assert_contains_text "Front of the line, WooHoo!, Build continuing"
  [[ "$status" == "0" ]]

}



@test "Command: script will queue on different job when block-workflow is true" {
  # given
  process_config_with test/inputs/command-non-default.yml
  export TESTING_MOCK_RESPONSE=test/api/jobs/onepreviousjob-differentname.json
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows

  # when
  assert_jq_match '.jobs | length' 1 #only 1 job
  assert_jq_match '.jobs["build"].steps | length' 1 #only 1 steps

  jq -r '.jobs["build"].steps[0].run.command' $JSON_PROJECT_CONFIG > ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash

  export CIRCLECI_API_KEY="madethisup"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_JOB="singlejob"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_BRANCH="madethisup"
  export CIRCLE_PR_REPONAME=""
  run bash ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash


  assert_contains_text "Max Queue Time: 1 minutes"
  assert_contains_text "Max wait time exceeded"

}


@test "Command: script will skip queueing on forks" {
  # given
  process_config_with test/inputs/command-defaults.yml

  # when
  assert_jq_match '.jobs | length' 1 #only 1 job
  assert_jq_match '.jobs["build"].steps | length' 1 #only 1 steps

  jq -r '.jobs["build"].steps[0].run.command' $JSON_PROJECT_CONFIG > ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash

  export CIRCLECI_API_KEY="madethisup"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_JOB="singlejob"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_BRANCH="madethisup"
  export CIRCLE_PR_REPONAME="fork"

  run bash ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash
  assert_contains_text "Queueing on forks is not supported. Skipping queue..."

}


@test "Default job sets block workflow properly" {
  # given
  process_config_with test/inputs/fulljob.yml

  # when
  assert_jq_match '.jobs | length' 1 #only 1 job
  assert_jq_match '.jobs["Single File"].steps | length' 1 #only 1 steps

  jq -r '.jobs["Single File"].steps[0].run.command' $JSON_PROJECT_CONFIG > ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash

  export CIRCLECI_API_KEY="madethisup"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_JOB="singlejob"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_BRANCH="madethisup"

  run bash ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash
  assert_contains_text "Orb parameter block-workflow is true."
}
