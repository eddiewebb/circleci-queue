# circleci-queue
Docker image or standalone script to block/queue jobs to ensure max concurrency limits

## Basic Usage
This adds concurreny limits by ensuring any jobs with this step will only continue once no previous vuilds are running.  It supports a single argument of how many minutes to wait before aborting itself.

It requires a single Enviuronment Variable `CIRCLECI_API_KEY` - create one in [account settings](https://circleci.com/account/api) and add it to your project.

## Standalone Python use
You can use this in any docker image by including the files found in [src](src) and executing the entry script `queueBuildUntilFrontOfLine.py 5`

**IMage must provide python**
Sample partial `.circleci/config.yml`
```
jobs:
  testing:
    docker:
      - image: circleci/python:2-jessie  # any image with python 2
    steps:
      - checkout
      - run:
          name: Queue Build
          command: |
            # wait up to 10 minute for previous builds
            python src/queueBuildUntilFrontOfLine.py 10

      - run:
          name: Do Regular Things
          command: |
            # Do your deployments, testring, etc, whatever should run with single concurrnecy across all builds

```

## Docker image
To get the latest and greatest without fuss, you can use the provided docker image `eddiewebb/circleci-queue` as the job image, and invoke `queueBuildUntilFrontOfLine. 5`
Sample partial `.circleci/config.yml`
```
jobs:
  queue:
    docker:
      - image: eddiewebb/circleci-queue:latest  
    steps:
      - checkout
      - run:
          name: Queue Build
          command: |
            # wait up to 10 minute for previous builds
            queueBuildUntilFrontOfLine 10
  build:
    docker:
      - image: Someother/image:tag
    steps:
      - run:
          name: Do Regular Things
          command: |
            # Do your deployments, testring, etc, whatever should run with single concurrnecy across all builds

```
