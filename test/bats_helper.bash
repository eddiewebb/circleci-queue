#!/bin/bash


function process_config_with {
	append_project_configuration $1 > $INPUT_PROJECT_CONFIG
 	circleci config process $INPUT_PROJECT_CONFIG > ${PROCESSED_PROJECT_CONFIG}
 	yq eval -o=j ${PROCESSED_PROJECT_CONFIG} > ${JSON_PROJECT_CONFIG}

 	#assertions use output, tests can override outptu to test additional commands beyond parsing.
 	output=`cat  ${PROCESSED_PROJECT_CONFIG}`
}

function append_project_configuration {
	if [ -z "$BATS_IMPORT_DEV_ORB" ]; then
		assemble_inline $1
	else
		assemble_external $1
	fi
}

#
#  USes circleci config pack, but indents everything under an `orbs.ORBNAME` element so it may be inlined.
#
function assemble_inline {
	CONFIG=$1
	echo "version: 2.1" 
	echo "orbs:"
	echo "  ${INLINE_ORB_NAME}:"
	circleci orb pack src | sed -e 's/^/    /'
	if [ -s $CONFIG ];then
		cat $CONFIG
	fi
}


#
#   Adds `orbs:` section referencing the provided dev orb
#
function assemble_external {
	CONFIG=$1
	echo "version: 2.1"
	echo "orbs:" 
	echo "  ${INLINE_ORB_NAME}: $BATS_IMPORT_DEV_ORB"  
	if [ -s $CONFIG ];then
		cat $CONFIG
	fi
}



#
#  Add assertions for use in BATS tests
#

function assert_contains_text {
	TEXT=$1
	if [[ "$output" != *"${TEXT}"* ]]; then
		echo "Expected text \`$TEXT\`, not found in output (printed below)"
		echo $output
		return 1
	fi	
}

function assert_text_not_found {
	TEXT=$1
	if [[ "$output" == *"${TEXT}"* ]]; then
		echo "Forbidden text \`$TEXT\`, was found in output.."
		echo $output
		return 1
	fi	
}

function assert_matches_file {
	FILE=$1
	echo "${output}" | sed '/# Original config.yml file:/q' | sed '$d' | diff -B $FILE -
	return $?
}

function assert_jq_match {
	MATCH=$2
	RES=$(jq -r "$1" ${JSON_PROJECT_CONFIG})
	if [[ "$RES" != "$MATCH" ]];then
		echo "Expected match "'"'"$MATCH"'"'" was not found in "'"'"$RES"'"'
		return 1
	fi
}

function assert_jq_contains {
	MATCH=$2
	RES=$(jq -r "$1" ${JSON_PROJECT_CONFIG})
	if [[ "$RES" != *"$MATCH"* ]];then
		echo "Expected string "'"'"$MATCH"'"'" was not found in "'"'"$RES"'"'
		return 1
	fi
}

function load_config_parameters {
	NAME=${1:-build}
	jq -r '.jobs["'${NAME}'"].steps[0].run.environment | to_entries[] | "export "+(.key | ascii_upcase)+"="+(.value | @sh)' $JSON_PROJECT_CONFIG > $ENV_STAGING_PATH
	source $ENV_STAGING_PATH
}

