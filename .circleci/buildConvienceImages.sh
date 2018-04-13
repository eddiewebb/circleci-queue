#!/bin/bash

#
# CircleCI provides "convinience images" for core languages. This script builds a augmneted version of all major languages.
#


while read IMAGETAG;do
	echo "build for ${IMAGETAG}"
	sed 's|REPLACEMEWITHIMAGE|'"${IMAGETAG}"'|' Dockerfiles/Blank > tempDockerfile
	OUR_TAG="eddiewebb/queue-${IMAGETAG/\//-}"
	echo "Building image ${OUR_TAG} from ${IMAGETAG} "
	docker build -f tempDockerfile -t ${OUR_TAG} .
	docker push ${OUR_TAG}
done < .circleci/images.txt


#
# At first i though we would doo all, but wya too many.
#

#IMAGES=( "circleci/openjdk" "circleci/node" )
#
#for IMAGE in IMAGES;do
#	for TAG in $(curl -sL "https://hub.docker.com/v2/repositories/${IMAGE}/tags?page_size=20" | jq -r '.results[].name');do
#		echo "build for ${IMAGE}:${TAG}"
#		sed 's|REPLACEMEWITHIMAGE|'"${IMAGE}:${TAG}"'|' Dockerfiles/Blank > tempDockerfile
#		OUR_TAG="eddiewebb/queue-${IMAGE/\//-}:${TAG}"
#		echo "Building image ${OUR_TAG} from ${IMAGE}:${TAG} "
#		docker build -f tempDockerfile -t ${OUR_TAG} .
#		exit
#	done
#done
