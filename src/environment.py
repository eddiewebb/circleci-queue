import os


def loadOrExit(variable_name):
	if variable_name in os.environ:
		return os.environ[variable_name]
	else:
		print "Required environment variable " + variable_name + " not found, exiting."
		exit(1)