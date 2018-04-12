import requests


class CircleCI:

	#"https://circleci.com/api/v1.1/project/:vcs/:user/:project?filter=running"
	jobs_api_url_template = "https://circleci.com/api/v1.1/project/{}/{}/{}?circle-token={}&filter=running"


	def __init__(self,circleci_key,build_num,user_name,project_name,repo_url):
		vcs_type="github"
		if "bitbucket" in repo_url.lower():
			vcs_type = "bitbucket"
		self.api_url = self.jobs_api_url_template.format(vcs_type,user_name,project_name,circleci_key)
		#local testing self.api_url = "http://localhost:5000"
	


	def oldest_running_build_num(self):
		r = requests.get(self.api_url)
		build_summary = r.json()
		if len(build_summary) == 1:
			return build_summary[0]['build_num']
		else:
			oldest = len(build_summary) - 1
			return build_summary[oldest]['build_num']
		

	def cancel_current(self):
		return
