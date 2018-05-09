# circleci-queue
Docker image or standalone script to block/queue jobs to ensure max concurrency limits

WHy?  Some jobs (typically deployments) need to run sequentially and not parrellel, but also run to completion. So CircleCI's native `auto-cancel` is not quite the right fit.
See https://github.com/eddiewebb/circleci-challenge as an example using blue/green cloud foundry deployments.

[![CircleCI](https://circleci.com/gh/eddiewebb/circleci-queue/tree/master.svg?style=svg)](https://circleci.com/gh/eddiewebb/circleci-queue/tree/master)

## Basic Usage
This adds concurreny limits by ensuring any jobs with this step will only continue once no previous builds are running.  It supports a single argument of how many minutes to wait before aborting itself and it requires a single Environment Variable `CIRCLECI_API_KEY` - which can be created in [account settings](https://circleci.com/account/api).


## Screenshots / Examples
Suppose we have a workflow take takes a little while to run.  Normally the build (#18) will run immediately, with no queuing.
![no queuing if only active build](assets/build_noqueue.png)

Someone else on the team makes another commit, since the first build (#18) is still running, it will queue build #19.
![no queuing if only active build](assets/build_queue2.png)

It's late afternoon, everyone is pushing their commits in to ensure they are good before they leave for the day. Build #20 also queues.
![no queuing if only active build](assets/build_queued.png)

Meanwhile, build #19 is now allowed to move forward since build #18 finished.

![no queuing if only active build](assets/build_progressed.png)

Oh No!  Since `1 minute` is abnormally long for things to be queued, build #20 aborts itself, letting build #19 finish uninterupted.

![no queuing if only active build](assets/build_aborted.png)

# Setup

## Standalone use
You can use this in any docker image by including the files found in [src](src) and executing the entry script `queueBuildUntilFrontOfLine.sh 5`

**Image must provide python**
Sample partial `.circleci/config.yml`
```
jobs:
  testing:
    docker:
      - image: circleci/python:2-jessie
    steps:
      - checkout
      - run:
          name: Queue Build
          command: |
            # wait up to 10 minute for previous builds
            python src/queueBuildUntilFrontOfLine.sh 10

      - run:
          name: Do Regular Things
          command: |
            # Do your deployments, testring, etc, whatever should run with single concurrnecy across all builds

```

## Docker image

### Replace current image 
To get the latest and greatest without fuss, you can use the provided docker image based on your lnaguage need. Many images supported, add more to [.circleci/images.txt] to add more.

`circleci/node:4-stretch-browsers ` ==> `eddiewebb/queue-circleci-node:4-stretch-browsers`  

Browse https://hub.docker.com/u/eddiewebb/ for all.

`queueBuildUntilFrontOfLine. 5`
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
