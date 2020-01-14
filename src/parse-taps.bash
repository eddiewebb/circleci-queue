#!/bin/bash

head='<?xml version="1.0"?>\n<testsuite>'
foot='</testsuite>'

test='<testcase file="%s" name="%s" time="%d" />'

parse_it(){
	$line=$1
	NAME=$(expr "$line" : '.*ok [0-9]* \(.*\) #time.*')
	TIME=$(expr "$line" : '.*ok [0-9]*.*\#time=\(.*\)')
	printf "${test}" "${NAME}" ${TIME}
}


printf "$head"

while read -r line;do
	case $line in
		1..*) continue ;;
		ok*) parse_it $line;;
		\#*) continue;;
		*) echo "unkon line" ;;
	esac
done < "$1"

printf "\n$foot"