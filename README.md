# `docker-registry-mirror-script`

A simple shell script to mirror specific Docker images from Docker Hub (or others) to a public AWS ECR registry (or others?<sup>1</sup>).

*<sup>1</sup>: not yet supported, but may be implemented in the future. Feature requests and PRs are welcome!*


## Features

* Can mirror images from Docker Hub **and** other sources (everything that is supported by `docker pull`)
* Validates the image list for basic requirements
* Checks for Docker Hub image availability
* Automatically creates missing AWS ECR repos
* Skips uploading already mirrored images
* Colorful and informative output while the script is running


## Motivation

On November 2nd 2020 a rate limiter has been introduced to Docker Hub, affecting public repos and unauthenticated pulls. More details can be found in [their blogpost.](https://www.docker.com/blog/what-you-need-to-know-about-upcoming-docker-hub-rate-limiting/)

At that time in my company it has caused issues for us, since our Kubernetes-based CI/CD system ran into rate limiting issues very frequently while pulling worker pod containers from Docker Hub.

Shortly after [AWS just happened to announce their public ECR repos,](https://aws.amazon.com/about-aws/whats-new/2020/12/announcing-amazon-ecr-public-and-amazon-ecr-public-gallery/) which was a perfect alternative for us, since we were already using AWS.

So to solve the issue, I have written this mirror script, which can mirror scripts from Docker Hub (or other registries) and upload them to a public AWS ECR.


## Requirements

Tools installed:

* `awk` - image list processing
* `aws` - AWS CLI for logging in and others
* `curl` - checking Docker Hub for container details
* `docker` - obvious
* `jq` - parsing various responses


Environmental variables present:

* `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` - AWS CLI session details
* `AWS_ECR_ID` - ID of your public AWS ECR


## Usage

### 1. Create the list of images to be mirrored

First you will need a textfile to hold the list of images to be mirrored. It should be called `./images.list` and it should look something like this:

```
maven:3.6-jdk-14
docker:19.03.14-dind
python:3.8.7-buster
quay.io/prometheusmsteams/prometheus-msteams:v1.4.2
gradle:6.8.3-jdk15
public.ecr.aws/bitnami/node:14-prod
```

Each line is an image to be mirrored, identified by its name and tag. The name can include a URL if you want to download from a different source than Docker Hub, and the tag _should_ be non-moving (e.g. **not** `latest` or `stable`).


### 2. Authenticate to your AWS account

You will need your common AWS environmental variables declared for this script to run.

If you're using some kind of multi-factor authentication device, take a look at my other script called [`aws-mfa-login`!](https://github.com/Semmu/aws-mfa-login)


### 3. Run the script

Define your AWS ECR ID via an environmental variable and then run the script, e.g.:

```bash
AWS_ECR_ID=12345678 ./mirror.sh
```

Voilà! It should do its thing.


## Contributing

If you want to submit a fix, a new feature, maybe supporting other targets (like a private [Nexus](https://www.sonatype.com/products/repository-oss) instance), feel free to fork the repo and open a PR.

_One note: I would like to use [`gitmoji`](https://github.com/carloscuesta/gitmoji) for each commit message, no matter how silly it looks. It is a personal preference._


## License

MIT.
