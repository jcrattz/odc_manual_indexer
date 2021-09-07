SHELL:=/bin/bash
# Set the project name to the path - making underscore the path separator.
PWD=$(pwd)
project_name=$(shell echo $${PWD//\//_})
docker_compose_prod = docker-compose --project-directory build/docker/prod -f build/docker/prod/docker-compose.yml -p $(project_name)_prod
docker_compose_dev = docker-compose --project-directory build/docker/dev -f build/docker/dev/docker-compose.yml -p $(project_name)_dev

IMG_REPO?=jcrattzama/odc_manual_indexer
IMG_VER?=
ODC_VER?=1.8.3

BASE_IMG=jcrattzama/datacube-base:odc1.8.3

PROD_OUT_IMG?="${IMG_REPO}:odc${ODC_VER}${IMG_VER}"
DEV_OUT_IMG?="${IMG_REPO}:odc${ODC_VER}${IMG_VER}_dev"

# Common exports used in subshells in the targets below.
COMMON_EXPRTS=export ODC_VER=${ODC_VER}; \
export BASE_IMG=${BASE_IMG}; export REQS_PATH=${REQS_PATH}
PROD_COMMON_EXPRTS=export OUT_IMG=${PROD_OUT_IMG}; ${COMMON_EXPRTS}
DEV_COMMON_EXPRTS=export OUT_IMG=${DEV_OUT_IMG}; ${COMMON_EXPRTS}

## Production ##
up:
	(${PROD_COMMON_EXPRTS}; $(docker_compose_prod) up -d --build)

up-no-build:
	(${PROD_COMMON_EXPRTS}; $(docker_compose_prod) up -d)

build-tag: # -e TAG=<tag> OR -e IMG_VER=<version>
	(${PROD_COMMON_EXPRTS}; $(docker_compose_prod) build)

down: 
	(${PROD_COMMON_EXPRTS}; $(docker_compose_prod) down --remove-orphans)

ssh:
	(${PROD_COMMON_EXPRTS}; $(docker_compose_prod) exec manual bash)

ps:
	(${PROD_COMMON_EXPRTS}; $(docker_compose_prod) ps)

restart: down up

restart-no-build: down up-no-build

push:
	docker push ${PROD_OUT_IMG}

pull:
	docker pull ${PROD_OUT_IMG}

build-and-push: build-tag push
## End Production ##

## Development ##
dev-up:
	(${DEV_COMMON_EXPRTS}; $(docker_compose_dev) up -d --build)

dev-up-no-build:
	(${DEV_COMMON_EXPRTS}; $(docker_compose_dev) up -d)

dev-down: 
	(${DEV_COMMON_EXPRTS}; $(docker_compose_dev) down --remove-orphans)

dev-ssh:
	(${DEV_COMMON_EXPRTS}; $(docker_compose_dev) exec manual bash)

dev-ps:
	(${DEV_COMMON_EXPRTS}; $(docker_compose_dev) ps)

dev-restart: dev-down dev-up

dev-restart-no-build: dev-down dev-up-no-build

dev-build-no-cache:
	(${DEV_COMMON_EXPRTS}; $(docker_compose_dev) build --no-cache)

dev-build-tag: # -e TAG=<tag> OR -e IMG_VER=<version>
	(${DEV_COMMON_EXPRTS}; $(docker_compose_dev) build)

dev-push:
	docker push ${DEV_OUT_IMG}

dev-pull:
	docker pull ${DEV_OUT_IMG}

build-and-push: build-tag push
## End Development ##

## ODC Docker Network ##
# Create the `odc` network on which everything runs.
create-odc-network:
	docker network create odc

delete-odc-network:
	docker network rm odc
## End ODC Docker Network ##

## ODC DB ##
# Create the persistent volume for the ODC database.
create-odc-db-volume:
	docker volume create odc-db-vol

# Delete the persistent volume for the ODC database.
delete-odc-db-volume:
	docker volume rm odc-db-vol

recreate-odc-db-volume: delete-odc-db-volume create-odc-db-volume

# Create the ODC database Docker container.
# The `-N` argument sets the maximum number of concurrent connections (`max_connections`).
# The `-B` argument sets the shared buffer size (`shared_buffers`).
create-odc-db:
	docker run -d \
	-e POSTGRES_DB=datacube \
	-e POSTGRES_USER=dc_user \
	-e POSTGRES_PASSWORD=localuser1234 \
	--name=odc-db \
	--network="odc" \
	-v odc-db-vol:/var/lib/postgresql/data \
	postgres:10-alpine \
	-N 1000 \
	-B 2048MB

start-odc-db:
	docker start odc-db

stop-odc-db:
	docker stop odc-db

restart-odc-db: stop-odc-db start-odc-db

odc-db-ssh:
	docker exec -it odc-db bash

dev-odc-db-init:
	(${DEV_COMMON_EXPRTS}; $(docker_compose_dev) exec manual datacube system init)

odc-db-init:
	(${PROD_COMMON_EXPRTS}; $(docker_compose_prod) exec manual datacube system init)

delete-odc-db:
	docker rm odc-db

recreate-odc-db: stop-odc-db delete-odc-db create-odc-db

recreate-odc-db-and-vol: stop-odc-db delete-odc-db recreate-odc-db-volume create-odc-db
## End ODC DB ##

## Docker Misc ##
sudo-ubuntu-install-docker:
	sudo apt-get update
	sudo apt install -y docker.io
	sudo curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-Linux-x86_64" -o /usr/local/bin/docker-compose
	sudo chmod +x /usr/local/bin/docker-compose
	sudo systemctl start docker
	sudo systemctl enable docker
	# The following steps are for enabling use 
	# of the `docker` command for the current user
	# without using `sudo`
	getent group docker || sudo groupadd docker
	sudo usermod -aG docker ${USER}
## End Docker Misc ##