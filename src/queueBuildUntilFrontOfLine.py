import sys
import time
import circleci
import environment


circleci_key = environment.loadOrExit('CIRCLECI_API_KEY')
build_num = int(environment.loadOrExit('CIRCLE_BUILD_NUM'))
user_name = environment.loadOrExit('CIRCLE_PROJECT_USERNAME')
project_name = environment.loadOrExit('CIRCLE_PROJECT_REPONAME')
repo_url = environment.loadOrExit('CIRCLE_REPOSITORY_URL')

if len(sys.argv) < 2:
	print "Must provide Max Queue Time in *minutes* as script argument"
	exit (1)
max_time = int(sys.argv[1])
print "This build will block until all previous builds complete."
print "Max Queue Time: " + str(max_time) + " minutes."



api = circleci.CircleCI(circleci_key,build_num,user_name,project_name,repo_url)
wait_time = 0
loop_time = 30
while True:

	oldest_running_build_num = api.oldest_running_build_num()
	if build_num <= oldest_running_build_num :
		print "Front of the line, WooHoo!, Build continuing"
		break
	else:
		print "This build (" + str(build_num) + ") is queued, waiting for build number (" + str(oldest_running_build_num) + ") to complete."
		print "Total Queue time: " + str(wait_time) + " seconds."
	

	if wait_time >= (max_time * 60):
		print "Max wait time exceeded, cancelling this build."
		api.cancel_current()
		exit(1)

	time.sleep(loop_time)
	wait_time += loop_time


