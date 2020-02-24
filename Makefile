DOCKER_REPO=quay.io/kinvolk

IMAGES=$(shell (ls -d */ | cut -d/ -f1))

.PHONY: build
build:
	for i in $(IMAGES); do docker build --pull -t $(DOCKER_REPO)/$$i:$$(git describe --always) $$i; done

.PHONY: tag-latest
tag-latest:
	for i in $(IMAGES); do docker tag $(DOCKER_REPO)/$$i:$$(git describe --always) $(DOCKER_REPO)/$$i:latest; done

.PHONY: push
push:
	for i in $(IMAGES); do docker push $(DOCKER_REPO)/$$i:$$(git describe --always); done

.PHONY: push-latest
push-latest:
	for i in $(IMAGES); do docker push $(DOCKER_REPO)/$$i:latest; done

.PHONY: all
all: build tag-latest push push-latest
