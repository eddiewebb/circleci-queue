#!/usr/bin/env bats

# load custom assertions and functions
load bats_helper

# setup is run beofre each test
function setup {
  INPUT_PROJECT_CONFIG=${BATS_TMPDIR}/input_config-${BATS_TEST_NUMBER}
  PROCESSED_PROJECT_CONFIG=${BATS_TMPDIR}/packed_config-${BATS_TEST_NUMBER} 
  JSON_PROJECT_CONFIG=${BATS_TMPDIR}/json_config-${BATS_TEST_NUMBER} 
  ENV_STAGING_PATH=${BATS_TMPDIR}/env-${BATS_TEST_NUMBER}.sh
       #echo "#using temp file ${BATS_TMPDIR}"
	BASH_ENV="$ENV_STAGING_PATH"

  # the name used in example config files.
  INLINE_ORB_NAME="queue"


  #if [ -z "$BATS_IMPORT_DEV_ORB" ]; then
    #echo "#Using \`inline\` orb assembly, to test against published orb, set BATS_IMPORT_DEV_ORB to fully qualified path" >&3
  #else
    #echo "#BATS_IMPORT_DEV_ORB env var is set, all config will be tested against imported orb $BATS_IMPORT_DEV_ORB" >&3
  #fi



}

@test "Default job sets block workflow properly" {
  # given
  export TESTING_MOCK_RESPONSE=test/api/jobs/onepreviousjob-differentname.json
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows
  process_config_with test/inputs/fulljob.yml

  # when
  assert_jq_match '.jobs | length' 1 #only 1 job
  assert_jq_match '.jobs["Single File"].steps | length' 2 #only 1 steps

  
  export CIRCLE_BRANCH="main"
  load_config_parameters "Single File"
  run bash scripts/loop.bash
  echo $ouput


  assert_contains_text "Orb parameter block-workflow is true."
}

@test "Default job sets can NOT block workflow if configured" {
  # given
  export TESTING_MOCK_RESPONSE=test/api/jobs/onepreviousjob-differentname.json
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows
  process_config_with test/inputs/fulljob-noblock.yml

  # when
  assert_jq_match '.jobs | length' 1 #only 1 job
  assert_jq_match '.jobs["Single File"].steps | length' 2 #only 1 steps

  
  export CIRCLE_BRANCH="main"
  load_config_parameters "Single File"
  run bash scripts/loop.bash
  echo $ouput


  assert_contains_text "Orb parameter block-workflow is false"
}


@test "Command: script will WAIT with previous job of similar name used in regexp" {
  # given

  process_config_with test/inputs/command-job-regex.yml
  # load any parameters provided as envars.

  export CIRCLE_BRANCH="main"
  load_config_parameters
  export TESTING_MOCK_RESPONSE=test/api/jobs/regex-matches.json
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows
  export CIRCLE_JOB=DeployStep1
  run bash scripts/loop.bash
  echo $ouput

  assert_contains_text "Max Queue Time: 6 seconds"
  assert_contains_text "Max wait time exceeded"
  assert_contains_text "Cancelling build 3"
  [[ "$status" == "1" ]]
}


@test "Command: script will NOT WAIT with previous job of non matching names when using regexp" {
  # given
  process_config_with test/inputs/command-job-regex.yml
  export TESTING_MOCK_RESPONSE=test/api/jobs/regex-no-matches.json
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows

  
  export CIRCLE_BRANCH="main"
  load_config_parameters
  export CIRCLE_JOB="DeployStep1"
  run bash scripts/loop.bash
  echo $ouput


  assert_contains_text "Max Queue Time: 6 seconds"
  assert_text_not_found "Max wait time exceeded"
  assert_contains_text "Front of the line, WooHoo!, Build continuing"
  [[ "$status" == "0" ]]
}



@test "Command: script will proceed with no previous jobs" {
  # given
  process_config_with test/inputs/command-defaults.yml
  export TESTING_MOCK_RESPONSE=test/api/jobs/nopreviousjobs.json
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows

  
  load_config_parameters
  run bash scripts/loop.bash
  echo $ouput


  assert_contains_text "Max Queue Time: 6 seconds"
  assert_text_not_found "Max wait time exceeded"
  assert_contains_text "Front of the line, WooHoo!, Build continuing"
  [[ "$status" == "0" ]]

}

@test "Command: script will proceed with previous job of different name" {
  # given
  process_config_with test/inputs/command-defaults.yml
  export TESTING_MOCK_RESPONSE=test/api/jobs/onepreviousjob-differentname.json
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows


  export CIRCLE_BRANCH="main"
  load_config_parameters
  run bash scripts/loop.bash
  echo $ouput


  assert_contains_text "Max Queue Time: 6 seconds"
  assert_contains_text "Front of the line, WooHoo!, Build continuing"
  [[ "$status" == "0" ]]
}

@test "Command: script will WAIT with previous job of same name" {
  # given
  process_config_with test/inputs/command-defaults.yml
  export TESTING_MOCK_RESPONSE=test/api/jobs/onepreviousjobsamename.json
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows

 
  export CIRCLE_BRANCH="main"
  load_config_parameters
  run bash scripts/loop.bash
  echo $ouput


  assert_contains_text "Max Queue Time: 6 seconds"
  assert_contains_text "Max wait time exceeded"
  assert_contains_text "Cancelling build 3"
  [[ "$status" == "1" ]]
}


@test "Command: script with dont-quit will not fail current job" {
  # given
  process_config_with test/inputs/command-dont-quit.yml
  export TESTING_MOCK_RESPONSE=test/api/jobs/onepreviousjobsamename.json
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows


  export CIRCLE_BRANCH="main"
  load_config_parameters
  run bash scripts/loop.bash
  echo $ouput


  assert_contains_text "Max Queue Time: 6 seconds"
  assert_contains_text "Max wait time exceeded"
  assert_contains_text "Orb parameter dont-quit is set to true, letting this job proceed!"
  [[ "$status" == "0" ]]
}

@test "Command: script will NOT consider branch" {
  # given
  process_config_with test/inputs/command-anybranch.yml
  export TESTING_MOCK_RESPONSE=test/api/jobs/nopreviousjobs.json
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows

  # when
 
  export CIRCLE_BRANCH="main"
  load_config_parameters
  run bash scripts/loop.bash
  echo $ouput

  assert_contains_text "Max Queue Time: 6 seconds"
  assert_contains_text "Orb parameter 'this-branch-only' is false, will block previous builds on any branch"
  assert_contains_text "Front of the line, WooHoo!, Build continuing"
  [[ "$status" == "0" ]]

}


@test "Command: script will consider branch default" {
  # given
  process_config_with test/inputs/command-defaults.yml
  export TESTING_MOCK_RESPONSE=test/api/jobs/nopreviousjobs.json #branch filtering handled by API, so return no matching builds
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows

  # when
  assert_jq_match '.jobs | length' 1 #only 1 job
  assert_jq_match '.jobs["build"].steps | length' 2 #only 1 steps

  
  export CIRCLE_BRANCH="main"
  load_config_parameters
  run bash scripts/loop.bash
  echo $ouput


  assert_contains_text "${CIRCLE_BRANCH} matches queueable branch names"
  assert_contains_text "Max Queue Time: 6 seconds"
  assert_contains_text "Only blocking execution if running previous jobs on branch: ${CIRCLE_BRANCH}"
  assert_contains_text "Front of the line, WooHoo!, Build continuing"
  [[ "$status" == "0" ]]

}




@test "Command: script will skip queueing on forks" {
  # given
  process_config_with test/inputs/command-defaults.yml

  # when
  assert_jq_match '.jobs | length' 1 #only 1 job
  assert_jq_match '.jobs["build"].steps | length' 2 #only 1 steps

  
  export CIRCLE_BRANCH="main"
  load_config_parameters
  export CIRCLE_PR_REPONAME="this/was/forked"
  export TRIGGER_SOURCE="1" 
  run bash scripts/loop.bash
  echo $ouput


  assert_contains_text "Queueing on forks is not supported. Skipping queue..."

}

