import circleci
import environment


circleci_key = environment.loadOrExit('CIRCLECI_API_KEY')
build_num = environment.loadOrExit('CIRCLE_BUILD_NUM')
user_name = environment.loadOrExit('CIRCLE_PROJECT_USERNAME')
project_name = environment.loadOrExit('CIRCLE_PROJECT_REPONAME')
repo_url = environment.loadOrExit('CIRCLE_REPOSITORY_URL')


api = circleci.CircleCI(circleci_key,build_num,user_name,project_name,repo_url)

print "checking status"