#!/usr/bin/env bats

# load custom assertions and functions
load bats_helper

# setup is run beofre each test
function setup {
  INPUT_PROJECT_CONFIG=${BATS_TMPDIR}/input_config-${BATS_TEST_NUMBER}
  PROCESSED_PROJECT_CONFIG=${BATS_TMPDIR}/packed_config-${BATS_TEST_NUMBER} 
  JSON_PROJECT_CONFIG=${BATS_TMPDIR}/json_config-${BATS_TEST_NUMBER} 
  ENV_STAGING_PATH=${BATS_TMPDIR}/env-${BATS_TEST_NUMBER}.sh
       echo "#using temp file ${BATS_TMPDIR}"

  # the name used in example config files.
  INLINE_ORB_NAME="queue"


  #if [ -z "$BATS_IMPORT_DEV_ORB" ]; then
    #echo "#Using \`inline\` orb assembly, to test against published orb, set BATS_IMPORT_DEV_ORB to fully qualified path" >&3
  #else
    #echo "#BATS_IMPORT_DEV_ORB env var is set, all config will be tested against imported orb $BATS_IMPORT_DEV_ORB" >&3
  #fi



}


@test "Command: Input parameters are passed to environment" {
  # given
  process_config_with test/inputs/command-non-default.yml

  # when
  assert_jq_match '.jobs | length' 1 #only 1 job
  assert_jq_match '.jobs["build"].steps | length' 1 #only 1 steps
  assert_jq_match '.jobs["build"].steps[0].run.environment["ONLY_ON_BRANCH"]' 'unique-branch-name'
  assert_jq_match '.jobs["build"].steps[0].run.environment["BLOCK_WORKFLOW"]' 'true'
  assert_jq_match '.jobs["build"].steps[0].run.environment["MAX_TIME"]' '1/10'
  assert_jq_match '.jobs["build"].steps[0].run.environment["DONT_QUIT"]' 'true'
  assert_jq_match '.jobs["build"].steps[0].run.environment["FORCE_CANCEL_PREVIOUS"]' 'true'
  assert_jq_match '.jobs["build"].steps[0].run.environment["FILTER_BRANCH"]' 'false'
  assert_jq_match '.jobs["build"].steps[0].run.environment["ONLY_ON_WORKFLOW"]' 'unique-workflow-name'
  assert_jq_match '.jobs["build"].steps[0].run.environment["CONFIDENCE_THRESHOLD"]'   '100'        
  assert_jq_match '.jobs["build"].steps[0].run.environment["CCI_API_KEY_NAME"]' 'ABC_123'
  assert_jq_match '.jobs["build"].steps[0].run.environment["TAG_PATTERN"]' 'unique-tag-pattern'
  assert_jq_match '.jobs["build"].steps[0].run.environment["JOB_REGEXP"]' 'unique-job-regex'
  assert_jq_match '.jobs["build"].steps[0].run.environment["CIRCLECI_BASE_URL"]' 'https://unique-hostname'
  #assert_jq_match '.jobs["build"].steps[0].run.environment["MY_PIPELINE_NUMBER"]' '99999999'
  #assert_jq_match '.jobs["build"].steps[0].run.environment["TRIGGER_SOURCE"]' 'unique-trigger-source'
  #assert_jq_match '.jobs["build"].steps[0].run.environment["VCS_TYPE"]' 'unique-vcs-type'
  #assert_jq_match '.jobs["build"].steps[0].run.environment["MY_BRANCH"]' 'unique-branch-for-me'
}


@test "Command: script will WAIT with previous job of similar name used in regexp" {
  # given

  process_config_with test/inputs/command-job-regex.yml
  # load any parameters provided as envars.
  load_config_parameters
  export TESTING_MOCK_RESPONSE=test/api/jobs/regex-matches.json
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows


  # mimic CCI provided values

  export MY_PIPELINE_NUMBER="2"
  export TRIGGER_SOURCE="1" 
  export VCS_TYPE="github" 
  export MY_BRANCH="main"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_JOB="DeployStep1"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_BRANCH="main"
  export CIRCLE_PR_REPONAME=""
  run bash scripts/loop.bash
  echo $ouput

  assert_contains_text "Max Queue Time: 6 seconds"
  assert_contains_text "Max wait time exceeded"
  assert_contains_text "Cancelling build 2"
  [[ "$status" == "1" ]]
}


@test "Command: script will NOT WAIT with previous job of non matching names when using regexp" {
  # given
  process_config_with test/inputs/command-job-regex.yml
  export TESTING_MOCK_RESPONSE=test/api/jobs/regex-no-matches.json
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows

  
  load_config_parameters
  export MY_PIPELINE_NUMBER="2"
  export TRIGGER_SOURCE="1" 
  export VCS_TYPE="github" 
  export MY_BRANCH="main"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_JOB="DeployStep1"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_BRANCH="main"
  export CIRCLE_PR_REPONAME=""
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
  export MY_PIPELINE_NUMBER="2"
  export TRIGGER_SOURCE="1" 
  export VCS_TYPE="github" 
  export MY_BRANCH="main"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_JOB="singlejob"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_BRANCH="main"
  export CIRCLE_PR_REPONAME=""
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


  load_config_parameters
  export MY_PIPELINE_NUMBER="2"
  export TRIGGER_SOURCE="1" 
  export VCS_TYPE="github" 
  export MY_BRANCH="main"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_JOB="singlejob"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_BRANCH="main"
  export CIRCLE_PR_REPONAME=""
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

 
  load_config_parameters
  export MY_PIPELINE_NUMBER="2"
  export TRIGGER_SOURCE="1" 
  export VCS_TYPE="github" 
  export MY_BRANCH="main"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_JOB="singlejob"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_BRANCH="main"
  export CIRCLE_PR_REPONAME=""
  run bash scripts/loop.bash
  echo $ouput


  assert_contains_text "Max Queue Time: 6 seconds"
  assert_contains_text "Max wait time exceeded"
  assert_contains_text "Cancelling build 2"
  [[ "$status" == "1" ]]
}


@test "Command: script with dont-quit will not fail current job" {
  # given
  process_config_with test/inputs/command-defaults.yml
  export TESTING_MOCK_RESPONSE=test/api/jobs/onepreviousjobsamename.json
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows

  load_config_parameters
  export DONT_QUIT="true"
  export MY_PIPELINE_NUMBER="2"
  export TRIGGER_SOURCE="1" 
  export VCS_TYPE="github" 
  export MY_BRANCH="main"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_JOB="singlejob"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_BRANCH="main"
  export CIRCLE_PR_REPONAME=""
  run bash scripts/loop.bash
  echo $ouput


  assert_contains_text "Max Queue Time: 6 seconds"
  assert_contains_text "Max wait time exceeded"
  assert_contains_text "Orb parameter dont-quit is set to true, letting this job proceed!"
  [[ "$status" == "0" ]]
}

@test "Command: script will NOT consider branch" {
  # given
  process_config_with test/inputs/command-defaults.yml
  export TESTING_MOCK_RESPONSE=test/api/jobs/nopreviousjobs.json
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows

  # when
 
  load_config_parameters
  export FILTER_BRANCH="false"
  export MY_PIPELINE_NUMBER="2"
  export TRIGGER_SOURCE="1" 
  export VCS_TYPE="github" 
  export MY_BRANCH="main"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_JOB="singlejob"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_BRANCH="main"
  export CIRCLE_PR_REPONAME=""
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
  assert_jq_match '.jobs["build"].steps | length' 1 #only 1 steps

  
  load_config_parameters
  export MY_PIPELINE_NUMBER="2"
  export TRIGGER_SOURCE="1" 
  export VCS_TYPE="github" 
  export MY_BRANCH="main"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_JOB="singlejob"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_BRANCH="main"
  export CIRCLE_PR_REPONAME=""
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
  assert_jq_match '.jobs["build"].steps | length' 1 #only 1 steps

  
  load_config_parameters
  export CIRCLE_PR_REPONAME="this/was/forked"
  export MY_PIPELINE_NUMBER="2"
  export TRIGGER_SOURCE="1" 
  export VCS_TYPE="github" 
  export MY_BRANCH="main"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_JOB="singlejob"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_BRANCH="main"
  run bash scripts/loop.bash
  echo $ouput


  assert_contains_text "Queueing on forks is not supported. Skipping queue..."

}


@test "Default job sets block workflow properly" {
  # given
  export TESTING_MOCK_RESPONSE=test/api/jobs/onepreviousjob-differentname.json
  export TESTING_MOCK_WORKFLOW_RESPONSES=test/api/workflows
  process_config_with test/inputs/fulljob.yml

  # when
  assert_jq_match '.jobs | length' 1 #only 1 job
  assert_jq_match '.jobs["Single File"].steps | length' 1 #only 1 steps

  
  load_config_parameters "Single File"
  export MY_PIPELINE_NUMBER="2"
  export TRIGGER_SOURCE="1" 
  export VCS_TYPE="github" 
  export MY_BRANCH="main"
  export CIRCLE_BUILD_NUM="2"
  export CIRCLE_JOB="singlejob"
  export CIRCLE_PROJECT_USERNAME="madethisup"
  export CIRCLE_PROJECT_REPONAME="madethisup"
  export CIRCLE_REPOSITORY_URL="madethisup"
  export CIRCLE_BRANCH="main"
  export CIRCLE_PR_REPONAME=""
  run bash scripts/loop.bash
  echo $ouput


  assert_contains_text "Orb parameter block-workflow is true."
}