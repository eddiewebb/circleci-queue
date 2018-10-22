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
}



@test "Command: Input parameters are respected by command" {
  # given
  process_config_with test/inputs/command-non-default.yml

  # when
  assert_jq_match '.jobs | length' 1 #only 1 job
  assert_jq_match '.jobs["build"].steps | length' 1 #only 1 steps

  run jq -r '.jobs["build"].steps[0].run.command' $JSON_PROJECT_CONFIG

  assert_contains_text "QUEUE_TIME=1"

}


@test "Command: script will proceed with no previous jobs" {
  # given
  process_config_with test/inputs/command-defaults.yml
  export TESTING_MOCK_RESPONSE=test/api/nopreviousjobs.json

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
  run bash ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash


  assert_contains_text "Max Queue Time: 1 minutes"
  assert_contains_text "Front of the line, WooHoo!, Build continuing"
  [[ "$status" == "0" ]]

}

@test "Command: script will proceed with previous job of different name" {
  # given
  process_config_with test/inputs/command-defaults.yml
  export TESTING_MOCK_RESPONSE=test/api/onepreviousjob-differentname.json

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
  run bash ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash


  assert_contains_text "Max Queue Time: 1 minutes"
  assert_contains_text "Front of the line, WooHoo!, Build continuing"
  [[ "$status" == "0" ]]
}

@test "Command: script will WAIT with previous job of same name" {
  # given
  process_config_with test/inputs/command-defaults.yml
  export TESTING_MOCK_RESPONSE=test/api/onepreviousjobsamename.json

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
  run bash ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash


  assert_contains_text "Max Queue Time: 1 minutes"
  assert_contains_text "Max wait time exceeded"
  assert_contains_text "Cancelleing build 2"
  [[ "$status" == "1" ]]
}

@test "Command: script with dont-quit will not fail current job" {
  # given
  process_config_with test/inputs/command-non-default.yml
  export TESTING_MOCK_RESPONSE=test/api/onepreviousjobsamename.json

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
  run bash ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash


  assert_contains_text "Max Queue Time: 1 minutes"
  assert_contains_text "Max wait time exceeded"
  assert_contains_text "Orb parameter dont-quit is set to true, letting this job proceed!"
  [[ "$status" == "0" ]]
}



@test "Command: script will consider branch" {
  # given
  process_config_with test/inputs/command-non-default.yml
  export TESTING_MOCK_RESPONSE=test/api/nopreviousjobs.json

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
  run bash ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash


  assert_contains_text "Max Queue Time: 1 minutes"
  assert_contains_text "Orb parameter 'consider-branch' is false, will block previous builds on any branch"
  assert_contains_text "Front of the line, WooHoo!, Build continuing"
  [[ "$status" == "0" ]]

}



@test "Command: script will consider branch default" {
  # given
  process_config_with test/inputs/command-defaults.yml
  export TESTING_MOCK_RESPONSE=test/api/nopreviousjobs.json #branch filtereing handles by API, so return no matching builds

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
  run bash ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash


  assert_contains_text "Max Queue Time: 1 minutes"
  assert_contains_text "Only blocking execution if running previous jobs on branch: ${CIRCLE_BRANCH}"
  assert_contains_text "Front of the line, WooHoo!, Build continuing"
  [[ "$status" == "0" ]]

}






@test "Command: script will queue on different job when consider-job is false" {
  # given
  process_config_with test/inputs/command-non-default.yml
  export TESTING_MOCK_RESPONSE=test/api/onepreviousjob-differentname.json

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
  run bash ${BATS_TMPDIR}/script-${BATS_TEST_NUMBER}.bash


  assert_contains_text "Max Queue Time: 1 minutes"
  assert_contains_text "Max wait time exceeded"

}


