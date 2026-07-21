PROJECT ?= my-platform
ENV ?= dev
AWS_REGION ?= us-east-1

# ArgoCD is installed with Helm, not GitOps, so its version is pinned here.
# Every other chart version lives in gitops/base/components.json.
ARGOCD_CHART_VERSION ?= 10.1.4

TF_DIR := terraform/envs/$(ENV)
BACKEND_CONFIG := ../../../bootstrap/backend-$(ENV).hcl
GITOPS_ENV_DIR := gitops/environments/$(ENV)

.PHONY: prerequisites bootstrap init fmt fmt-check validate plan apply destroy destroy-gitops clean check kubeconfig configure-app-secret configure-gitops-values set-image-tag build-app gitops-render gitops-validate deploy-argocd configure-argocd-repository apply-argocd-apps verify render-observability

# Fails on the first missing tool instead of half way through a deploy.
prerequisites:
	@missing=0; \
	for tool in aws terraform kubectl helm jq python3 openssl; do \
		if command -v $$tool >/dev/null; then \
			echo "ok      $$tool"; \
		else \
			echo "MISSING $$tool"; missing=1; \
		fi; \
	done; \
	if aws sts get-caller-identity >/dev/null 2>&1; then \
		echo "ok      aws credentials"; \
	else \
		echo "MISSING aws credentials (aws sts get-caller-identity failed)"; missing=1; \
	fi; \
	test $$missing -eq 0

bootstrap:
	./bootstrap/bootstrap.sh $(PROJECT) $(ENV) $(AWS_REGION)

init:
	cd $(TF_DIR) && terraform init -backend-config=$(BACKEND_CONFIG)

fmt:
	terraform fmt -recursive terraform

fmt-check:
	terraform fmt -check -recursive terraform

validate:
	cd $(TF_DIR) && terraform validate

plan:
	cd $(TF_DIR) && terraform plan

apply:
	cd $(TF_DIR) && terraform apply

destroy:
	cd $(TF_DIR) && terraform destroy

# .terraform.lock.hcl is committed for the root modules, so it is not deleted
# here. Only provider caches and generated directories are removed.
clean:
	find terraform -type d -name ".terraform" -prune -exec rm -rf {} +

# Single source of truth for which environments exist.
ENVIRONMENTS = $(shell python3 -c 'import json; print(" ".join(json.load(open("gitops/environments/environments.json"))["environments"]))')

check: fmt-check
	python3 -m py_compile scripts/gitops.py app/main.py
	python3 -m json.tool gitops/base/components.json >/dev/null
	python3 -m json.tool gitops/environments/environments.json >/dev/null
	for env in $(ENVIRONMENTS); do python3 -m json.tool gitops/environments/$$env/environment.json >/dev/null; done
	for env in $(ENVIRONMENTS); do $(MAKE) gitops-render ENV=$$env; done
	@# Rendering must be deterministic: a second pass may not change anything.
	@find gitops/environments -name '*.yaml' -exec shasum {} + | shasum >/tmp/gitops-render-1
	@for env in $(ENVIRONMENTS); do python3 scripts/gitops.py render $$env; done
	@find gitops/environments -name '*.yaml' -exec shasum {} + | shasum >/tmp/gitops-render-2
	@cmp -s /tmp/gitops-render-1 /tmp/gitops-render-2 || { echo "gitops render is not deterministic"; exit 1; }
	python3 -m unittest discover -s tests -q
	python3 scripts/check-doc-links.py
	shellcheck bootstrap/*.sh scripts/*.sh
	helm lint gitops/apps/example-app/chart
	for env in $(ENVIRONMENTS); do \
		helm template example-app gitops/apps/example-app/chart \
			--values gitops/apps/example-app/chart/values-$$env.yaml >/dev/null; \
	done

# Region comes from the Terraform output, not from AWS_REGION, so the kubeconfig
# always matches the environment that was actually applied.
kubeconfig:
	@set -e; \
	CLUSTER="$$(cd $(TF_DIR) && terraform output -raw eks_cluster_name)"; \
	REGION="$$(cd $(TF_DIR) && terraform output -raw aws_region)"; \
	aws eks update-kubeconfig --name "$$CLUSTER" --region "$$REGION"

configure-app-secret:
	./scripts/configure-app-secret.sh $(ENV)

configure-gitops-values:
	@set -e; \
	CLUSTER="$$(cd $(TF_DIR) && terraform output -raw eks_cluster_name)"; \
	VPC="$$(cd $(TF_DIR) && terraform output -raw vpc_id)"; \
	ALB_ARN="$$(cd $(TF_DIR) && terraform output -raw alb_controller_role_arn)"; \
	CA_ARN="$$(cd $(TF_DIR) && terraform output -raw cluster_autoscaler_role_arn)"; \
	ESO_ARN="$$(cd $(TF_DIR) && terraform output -raw eso_role_arn)"; \
	GRAFANA_ARN="$$(cd $(TF_DIR) && terraform output -raw grafana_cloudwatch_role_arn)"; \
	ECR_URL="$$(cd $(TF_DIR) && terraform output -raw ecr_repository_url)"; \
	SECRET_PATH="$$(cd $(TF_DIR) && terraform output -raw app_secret_name)"; \
	REGION="$$(cd $(TF_DIR) && terraform output -raw aws_region)"; \
	CLUSTER="$$CLUSTER" VPC="$$VPC" ALB_ARN="$$ALB_ARN" CA_ARN="$$CA_ARN" ESO_ARN="$$ESO_ARN" GRAFANA_ARN="$$GRAFANA_ARN" ECR_URL="$$ECR_URL" SECRET_PATH="$$SECRET_PATH" AWS_REGION="$$REGION" ENV="$(ENV)" \
	python3 -c 'import json,os,pathlib; p=pathlib.Path("gitops/environments")/os.environ["ENV"]/ "environment.json"; d=json.loads(p.read_text()); account=os.environ["ALB_ARN"].split(":")[4]; d["aws"]["accountId"]=account; d["aws"]["clusterName"]=os.environ["CLUSTER"]; d["aws"]["region"]=os.environ["AWS_REGION"]; d["aws"]["vpcId"]=os.environ["VPC"]; d["aws"]["roles"]["awsLoadBalancerController"]=os.environ["ALB_ARN"]; d["aws"]["roles"]["clusterAutoscaler"]=os.environ["CA_ARN"]; d["aws"]["roles"]["externalSecrets"]=os.environ["ESO_ARN"]; d["aws"]["roles"]["grafanaCloudWatch"]=os.environ["GRAFANA_ARN"]; d["exampleApp"]["image"]["repository"]=os.environ["ECR_URL"]; d["exampleApp"]["secretManagerPath"]=os.environ["SECRET_PATH"]; p.write_text(json.dumps(d, indent=2) + "\n")'
	$(MAKE) gitops-render ENV=$(ENV)
	@echo "Updated $(GITOPS_ENV_DIR)/environment.json and rendered ArgoCD manifests"

# Point an environment at a specific image tag. ECR repositories use immutable
# tags, so every build gets its own tag and this is what promotes it.
set-image-tag:
	@test -n "$(TAG)" || { echo "usage: make set-image-tag ENV=<env> TAG=<tag>"; exit 1; }
	@ENV="$(ENV)" TAG="$(TAG)" python3 -c 'import json,os,pathlib; p=pathlib.Path("gitops/environments")/os.environ["ENV"]/ "environment.json"; d=json.loads(p.read_text()); d["exampleApp"]["image"]["tag"]=os.environ["TAG"]; p.write_text(json.dumps(d, indent=2) + "\n")'
	$(MAKE) gitops-render ENV=$(ENV)
	@echo "$(ENV) now points at image tag $(TAG); commit and push for ArgoCD to see it"

gitops-render:
	python3 scripts/gitops.py render $(ENV)

gitops-validate:
	python3 scripts/gitops.py validate $(ENV)

deploy-argocd:
	helm repo add argo https://argoproj.github.io/argo-helm
	helm repo update argo
	helm upgrade --install argocd argo/argo-cd \
		--version $(ARGOCD_CHART_VERSION) \
		--namespace argocd --create-namespace \
		--values deploy/argocd/install/values.yaml

# Registers the Git repository ArgoCD pulls from. SSH_KEY_FILE is a path to a
# private deploy key; it is read by kubectl and never written into the repo.
# See docs/gitops.md for how to create the key.
configure-argocd-repository:
	@test -n "$(SSH_KEY_FILE)" || { echo "usage: make configure-argocd-repository ENV=<env> SSH_KEY_FILE=~/.ssh/argocd_deploy_key"; exit 1; }
	@test -f "$(SSH_KEY_FILE)" || { echo "no such key file: $(SSH_KEY_FILE)"; exit 1; }
	@set -e; \
	REPO_URL="$$(python3 -c 'import json; print(json.load(open("$(GITOPS_ENV_DIR)/environment.json"))["repoURL"])')"; \
	ARGOCD_NS="$$(python3 -c 'import json; print(json.load(open("$(GITOPS_ENV_DIR)/environment.json"))["argocdNamespace"])')"; \
	kubectl -n "$$ARGOCD_NS" create secret generic argocd-repo-$(ENV) \
		--from-literal=type=git \
		--from-literal=url="$$REPO_URL" \
		--from-file=sshPrivateKey="$(SSH_KEY_FILE)" \
		--dry-run=client -o yaml \
		| kubectl label -f - --local -o yaml --dry-run=client argocd.argoproj.io/secret-type=repository \
		| kubectl apply -f -; \
	echo "Registered $$REPO_URL with ArgoCD in namespace $$ARGOCD_NS"

apply-argocd-apps: gitops-validate
	kubectl apply -f $(GITOPS_ENV_DIR)/root-app.yaml

verify:
	./scripts/verify.sh $(ENV)

# Run before `make destroy`: ALBs and other controller-created AWS resources
# must be gone before Terraform tears down the VPC.
destroy-gitops:
	./scripts/destroy-gitops.sh $(ENV)

# Builds and pushes the example application image. ECR tags are immutable, so
# TAG must be new on every build.
build-app:
	@test -n "$(TAG)" || { echo "usage: make build-app ENV=<env> TAG=<tag>"; exit 1; }
	@set -e; \
	ECR_URL="$$(cd $(TF_DIR) && terraform output -raw ecr_repository_url)"; \
	REGION="$$(cd $(TF_DIR) && terraform output -raw aws_region)"; \
	REGISTRY="$${ECR_URL%%/*}"; \
	aws ecr get-login-password --region "$$REGION" | docker login --username AWS --password-stdin "$$REGISTRY"; \
	docker build --platform linux/amd64 -t "$$ECR_URL:$(TAG)" app; \
	docker push "$$ECR_URL:$(TAG)"; \
	echo "Pushed $$ECR_URL:$(TAG). Next: make set-image-tag ENV=$(ENV) TAG=$(TAG)"

render-observability:
	helm template vm-stack vm/victoria-metrics-k8s-stack \
		--namespace observability \
		--values deploy/observability/victoria-metrics-k8s-stack-values.yaml \
		>/tmp/vm-stack-rendered.yaml
	helm template loki grafana/loki \
		--namespace observability \
		--values deploy/observability/loki-values.yaml \
		>/tmp/loki-rendered.yaml
	helm template promtail grafana/promtail \
		--namespace observability \
		--values deploy/observability/promtail-values.yaml \
		>/tmp/promtail-rendered.yaml
	@echo "Rendered observability manifests to /tmp/vm-stack-rendered.yaml, /tmp/loki-rendered.yaml, /tmp/promtail-rendered.yaml"
