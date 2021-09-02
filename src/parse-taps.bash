#!/bin/bash

head='<?xml version="1.0"?>\n<testsuite name="BatsTests" tests="%d">'
foot='</testsuite>'

test='<testcase file="%s" classname="%s" time="%d" />'


header(){
	line="$1"
	count=$(expr "$line" : '1..\([0-9]*\)')
	printf "$head" $count
}

parse_it(){
	NAME=$(expr "$line" : '.*ok [0-9]* \(.*\) #time.*')
	TIME=$(expr "$line" : '.*ok [0-9]*.*\#time=\(.*\)')
	printf "${test}" "${NAME}" "${NAME}" ${TIME}
}



while read -r line;do
	case $line in
		1..*) header;;
		ok*) parse_it;;
		\#*) continue;;
		*) echo "unkon line" ;;
	esac
done < "$1"

printf "\n$foot"