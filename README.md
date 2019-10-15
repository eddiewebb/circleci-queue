# CircleCI Concurrency Control Orb

[![CircleCI](https://img.shields.io/circleci/build/gh/eddiewebb/circleci-queue)](https://circleci.com/gh/eddiewebb/circleci-queue/tree/master) 
[![GitHub license](https://img.shields.io/github/license/eddiewebb/circleci-queue)](https://github.com/eddiewebb/circleci-queue/blob/master/LICENSE)
[![CircleCI Orb Version](https://img.shields.io/badge/endpoint.svg?url=https://badges.circleci.io/orb/eddiewebb/queue)](https://circleci.com/orbs/registry/orb/eddiewebb/queue)
[![Bors enabled](https://bors.tech/images/badge_small.svg)](https://app.bors.tech/repositories/21077)

CircleCI Orb to limit workflow concurrency.

Why? Some jobs (typically deployments) need to run sequentially and not parallel, but also run to completion. So CircleCI's native `auto-cancel` is not quite the right fit.
See https://github.com/eddiewebb/circleci-challenge as an example using blue/green cloud foundry deployments.


## Basic Usage

This adds concurrency limits by ensuring any jobs with this step will only continue once no previous builds are running. It supports a single argument of how many minutes to wait before aborting itself and it requires a single Environment Variable `CIRCLECI_API_KEY` - which can be created in [account settings](https://circleci.com/account/api).

## Screenshots / Examples

Suppose we have a workflow take takes a little while to run. Normally the build (#18) will run immediately, with no queuing.
![no queuing if only active build](assets/build_noqueue.png)

Someone else on the team makes another commit, since the first build (#18) is still running, it will queue build #19.
![no queuing if only active build](assets/build_queue2.png)

It's late afternoon, everyone is pushing their commits in to ensure they are good before they leave for the day. Build #20 also queues.
![no queuing if only active build](assets/build_queued.png)

Meanwhile, build #19 is now allowed to move forward since build #18 finished.

![no queuing if only active build](assets/build_progressed.png)

Oh No! Since `1 minute` is abnormally long for things to be queued, build #20 aborts itself, letting build #19 finish uninterrupted.

![no queuing if only active build](assets/build_aborted.png)

# Setup
See https://circleci.com/orbs/registry/orb/eddiewebb/queue#usage-examples for current examples

## Note

Queueing is not supported on forked repos. If a queue from a fork happens the queue will immediately exit and the next step of the job will begin.
