# This version-strategy uses git tags to set the version string
VERSION := $(shell git describe --tags --always --dirty)
GIT_COMMIT := $(shell git rev-list -1 HEAD)

# HELP
# This will output the help for each task
# thanks to https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help

help:
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help

version: ## Show version
	@echo $(VERSION) \(git commit: $(GIT_COMMIT)\)

# HTTPS TASK
key: ## [HTTP] Generate key
	openssl genrsa -out server.key 2048
	openssl ecparam -genkey -name secp384r1 -out server.key

cert: ## [HTTP] Generate self signed certificate
	openssl req -new -x509 -sha256 -key server.key -out server.pem -days 3650

# DOCKER TASKS
docker-build: ## [DOCKER] Build given container. Example: `make docker-build BIN=user`
	docker build -f cmd/$(BIN)/Dockerfile --no-cache --build-arg BIN=$(BIN) --build-arg VERSION=$(VERSION) --build-arg GIT_COMMIT=$(GIT_COMMIT) -t go-api-boilerplate-$(BIN) .

docker-run: ## [DOCKER] Run container on given port. Example: `make docker-run BIN=user PORT=3000`
	docker run -i -t --rm -p=$(PORT):$(PORT) --name="go-api-boilerplate-$(BIN)" go-api-boilerplate-$(BIN)

docker-stop: ## [DOCKER] Stop docker container. Example: `make docker-stop BIN=user`
	docker stop go-api-boilerplate-$(BIN)

docker-rm: docker-stop ## [DOCKER] Stop and then remove docker container. Example: `make docker-rm BIN=user`
	docker rm go-api-boilerplate-$(BIN)

docker-publish: aws-repo-login docker-publish-latest docker-publish-version ## [DOCKER] Docker publish. Example: `make docker-publish BIN=user REGISTRY=https://your-registry.com`

docker-publish-latest: docker-tag-latest
	@echo 'publish latest to $(REGISTRY)'
	docker push $(REGISTRY)/$(BIN):latest

docker-publish-version: docker-tag-version
	@echo 'publish $(VERSION) to $(REGISTRY)'
	docker push $(REGISTRY)/$(BIN):$(VERSION)

docker-tag: docker-tag-latest docker-tag-version ## [DOCKER] Tag current container. Example: `make docker-tag BIN=user REGISTRY=https://your-registry.com`

docker-tag-latest:
	@echo 'create tag latest'
	docker tag go-api-boilerplate-$(BIN) $(REGISTRY)/$(BIN):latest

docker-tag-version:
	@echo 'create tag $(VERSION)'
	docker tag go-api-boilerplate-$(BIN) $(REGISTRY)/$(BIN):$(VERSION)

docker-release: docker-build docker-publish ## [DOCKER] Docker release - build, tag and push the container. Example: `make docker-release BIN=user REGISTRY=https://your-registry.com`

helm-install: ## [HELM] Deploy the Helm chart for application. Example: `make helm-install`
	kubectl create namespace go-api-boilerplate \
	&& helm install go-api-boilerplate helm/app/ --namespace go-api-boilerplate

helm-upgrade: ## [HELM] Update the Helm chart for application. Example: `make helm-upgrade`
	helm upgrade go-api-boilerplate helm/app/ --namespace go-api-boilerplate

helm-history: ## [HELM] See what revisions have been made to the application's helm chart. Example: `make helm-history`
	helm history go-api-boilerplate --namespace go-api-boilerplate

helm-dependencies: ## [HELM] Update helm chart's dependencies for application. Example: `make helm-dependencies`
	cd helm/app/ && helm dependency update

helm-delete: ## [HELM] Delete helm chart for application. Example: `make helm-delete`
	helm uninstall go-api-boilerplate --namespace go-api-boilerplate \
	&& kubectl delete namespace go-api-boilerplate

# TELEPRESENCE TASKS
telepresence-swap-local: ## [TELEPRESENCE] Replace the existing deployment with the Telepresence proxy for local process. Example: `make telepresence-swap-local BIN=user PORT=3000 DEPLOYMENT=go-api-boilerplate-user`
	go build -o cmd/$(BIN)/$(BIN) cmd/$(BIN)/main.go
	telepresence \
	--swap-deployment $(DEPLOYMENT) \
	--expose 3000 \
	--run ./cmd/$(BIN)/$(BIN) \
	--port=$(PORT) \
	--method vpn-tcp

telepresence-swap-docker: ## [TELEPRESENCE] Replace the existing deployment with the Telepresence proxy for local docker image. Example: `make telepresence-swap-docker BIN=user PORT=3000 DEPLOYMENT=go-api-boilerplate-user`
	telepresence \
	--swap-deployment $(DEPLOYMENT) \
	--docker-run -i -t --rm -p=$(PORT):$(PORT) --name="$(BIN)" $(BIN):latest

# HELPERS
# generate script to login to aws docker repo
CMD_REPOLOGIN := "eval $$\( aws ecr"
ifdef AWS_CLI_PROFILE
CMD_REPOLOGIN += " --profile $(AWS_CLI_PROFILE)"
endif
ifdef AWS_CLI_REGION
CMD_REPOLOGIN += " --region $(AWS_CLI_REGION)"
endif
CMD_REPOLOGIN += " get-login \)"

aws-repo-login: ## [HELPER] login to AWS-ECR
	@eval $(CMD_REPOLOGIN)
