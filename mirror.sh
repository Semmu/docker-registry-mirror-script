#!/usr/bin/env bash

#
# CONFIGURATION
#

ECR_REGION="us-east-1"
IMAGES_LIST_FILE=./images.list



#
# TEXT COLORING VARS
#

RESET='\033[0m'
RED='\033[00;31m'
GREEN='\033[00;32m'
YELLOW='\033[00;33m'
LIGHTGRAY='\033[00;37m'
CYAN='\033[00;36m'



#
# MESSAGE HELPER FUNCTIONS
#

# printing current date for reference
function now {
    echo -e "${CYAN}    [TIME] now:" "$(date)" "$RESET"
}

# generic log/info/debug messages
function log {
    echo -e "${LIGHTGRAY}    [INFO]" "$1" "$RESET"
}

# success/ok messages
function ok {
    echo -e "${GREEN} [SUCCESS]" "$1" "$RESET"
}

# warnings/resolvable issues
function warn {
    echo -e "${YELLOW} [WARNING]" "$1" "$RESET"
}

# fatal errors -> terminates script
function err {
    echo -e "${RED}   [ERROR]" "$1" "$RESET"
    exit 1
}



#
# REQUIREMENT CHECKER FUNCTIONS
#

# ensuring required environmental variables are present
function ensure_env_exists {
    log "- env $1"

    if [[ -z $( env | grep "${1}=" ) ]] ; then
        err "env $1 does not exist, make sure to authenticate to awscli first!"
    fi
}

# ensuring commands/binaries are present
function ensure_command_exists { 
    log "- $1"
    if ! which "$1" 1>/dev/null 2>/dev/null ; then
        err "$1 is not installed! please install it first!"
    fi
}

# ensuring required files exist
function ensure_file_exists {
    log "- $1"
    if [[ ! -f $1 ]] ; then
        erro "$1 does not exist! please create it first!"
    fi
}

# ensuring docker daemon is running
function ensure_docker_daemon_running {
    if ! docker info 1>/dev/null 2>/dev/null ; then
        err "docker does not seem to be running! please start it first!"
    fi
}



#
# ACTUALLY DOING STUFF BELOW
#

# instant fail on any error
set -e

# printing time here and there for reference
now

# ensuring AWS access credentials
log "ensuring required environmental variables exist..."
ensure_env_exists AWS_SESSION_TOKEN
ensure_env_exists AWS_ACCESS_KEY_ID
ensure_env_exists AWS_SECRET_ACCESS_KEY
ensure_env_exists AWS_ECR_ID
ok "all required env vars exists!"

# checking required files
log "checking if all required files exist..."
ensure_file_exists $IMAGES_LIST_FILE
ok "all required files exist!"

# checking required tools
log "checking if all the required tools are installed..."
ensure_command_exists awk
ensure_command_exists aws
ensure_command_exists curl
ensure_command_exists docker
ensure_command_exists jq
ok "all required tools are available!"

# checking docker daemon
log "checking if docker daemon is running..."
ensure_docker_daemon_running
ok "docker daemon is up!"

# checking if $IMAGES_LIST_FILE contains duplicates
IMAGES_LIST_LINES_COUNT=$( grep -c '[^[:space:]]' $IMAGES_LIST_FILE )
IMAGES_LIST_UNIQUE_LINES_COUNT=$( sort $IMAGES_LIST_FILE | uniq | grep -c '[^[:space:]]' )
if [[ ! $IMAGES_LIST_LINES_COUNT -eq $IMAGES_LIST_UNIQUE_LINES_COUNT ]] ; then
    warn "$IMAGES_LIST_FILE seems to contain duplicates! ignoring..."
fi

now

# validating images list file and checking Docker Hub for availability
UNIQUE_REQUIRED_IMAGES=$( sort $IMAGES_LIST_FILE | uniq )
log "validating ${IMAGES_LIST_FILE} and checking their availability on Docker Hub..."
for UNIQUE_REQUIRED_IMAGE in ${UNIQUE_REQUIRED_IMAGES[@]} ; do
    REPO=$( echo "$UNIQUE_REQUIRED_IMAGE" | awk -F':' '{print $1}' )
    TAG=$( echo "$UNIQUE_REQUIRED_IMAGE" | awk -F':' '{print $2}' )

    log "- ${REPO}:${TAG}"

    if [[ -z $TAG ]] ; then
        err "${UNIQUE_REQUIRED_IMAGE} has no tag defined, please define a static tag!"
    fi

    if [[ $TAG == "latest" || $TAG == "stable" ]] ; then
        warn "${REPO} has 'latest' or 'stable' defined as its tag, change it to a static one!"
    fi

    if ! curl --silent -f -lSL "https://index.docker.io/v1/repositories/${REPO}/tags/${TAG}" 1>/dev/null 2>/dev/null ; then
        warn "$REPO:$TAG does not exist on Docker Hub! mirroring would fail!"
    fi
done
ok "${IMAGES_LIST_FILE} seems to be valid!"

now

# logging in to our ECR
log "logging in to our ECR via docker..."
aws ecr-public get-login-password --region $ECR_REGION | docker login --username AWS --password-stdin "public.ecr.aws/${AWS_ECR_ID}" > /dev/null
ok "docker login successful!"

# getting list of existing mirror repos
log "getting existing public repositories in our ECR..."
EXISTING_REPOS=$(aws ecr-public describe-repositories --region us-east-1 --out json | jq '.repositories[].repositoryName' | sed s/\"//g | sort )
for EXISTING_REPO in ${EXISTING_REPOS[@]} ; do
    log " - $EXISTING_REPO"
done
ok "successfully got list of our already existing ECR repositories!"

now

# checking if all the required repos exist or not
UNIQUE_REQUIRED_REPOS=$( sort $IMAGES_LIST_FILE | awk -F':' '{print $1}' | uniq )
log "checking if all the required repositories already exist or not..."
for REQUIRED_REPO in ${UNIQUE_REQUIRED_REPOS[@]} ; do
    log "- $REQUIRED_REPO"

    FOUND=0
    for EXISTING_REPO in ${EXISTING_REPOS[@]} ; do
        if [[ "$EXISTING_REPO" == "$REQUIRED_REPO" ]] ; then
            FOUND=1
        fi
    done

    if [[ ! $FOUND -eq 1 ]] ; then
        warn "${REQUIRED_REPO} repository does not exist! creating it..."
        aws ecr-public create-repository --repository-name "$REQUIRED_REPO" --region "$ECR_REGION" 1>/dev/null
        ok "$REQUIRED_REPO repository created!"
    fi
done
ok "all the required repositories exist!"

now

# finally mirroring images
log "checking if all the required images are mirrored or not..."
UNIQUE_REQUIRED_IMAGES=$( sort $IMAGES_LIST_FILE | uniq )
for UNIQUE_REQUIRED_IMAGE in ${UNIQUE_REQUIRED_IMAGES[@]} ; do
    REPO=$( echo "$UNIQUE_REQUIRED_IMAGE" | awk -F':' '{print $1}' )
    TAG=$( echo "$UNIQUE_REQUIRED_IMAGE" | awk -F':' '{print $2}' )

    log "- $REPO:$TAG"

    EXISTING_IMAGES=$( aws ecr-public describe-images --repository-name "$REPO" --region "$ECR_REGION" --output json | jq '.imageDetails[].imageTags[]' | sed s/\"//g | sort )

    FOUND=0

    for EXISTING_IMAGE in ${EXISTING_IMAGES[@]} ; do
        if [[ "$TAG" == "$EXISTING_IMAGE" ]] ; then
            FOUND=1
        fi
    done

    if [[ $FOUND -eq 0 ]] ; then
        warn "$REPO:$TAG not mirrored yet! mirroring..."

        log "downloading $REPO:$TAG from Docker Hub..."
        now
        if ! docker pull "${REPO}:${TAG}" ; then
            err "could not download ${REPO}:${TAG} from Docker Hub, does it exist?"
        fi

        log "tagging and pushing it to our ECR..."
        docker tag "${REPO}:${TAG}" "public.ecr.aws/${AWS_ECR_ID}/${REPO}:${TAG}"
        now
        docker push "public.ecr.aws/${AWS_ECR_ID}/${REPO}:${TAG}"
        now
        ok "$REPO:$TAG successfully mirrored to our ECR!"
    fi
done

now

ok "everything is mirrored, job's done, bye!"