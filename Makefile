PROJECT ?= my-platform
ENV ?= dev
AWS_REGION ?= us-east-1

TF_DIR := terraform/envs/$(ENV)
BACKEND_CONFIG := ../../../bootstrap/backend-$(ENV).hcl
GITOPS_ENV_DIR := gitops/environments/$(ENV)

.PHONY: bootstrap init fmt fmt-check validate plan apply destroy clean check configure-gitops-values gitops-render gitops-validate deploy-argocd apply-argocd-apps render-observability

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

clean:
	find terraform -type d -name ".terraform" -prune -exec rm -rf {} +
	find terraform -type f -name ".terraform.lock.hcl" -delete

check: fmt-check
	python3 -m py_compile scripts/gitops.py
	python3 -m json.tool gitops/base/components.json >/tmp/components.json
	python3 -m json.tool gitops/environments/environments.json >/tmp/environments.json
	for env in dev staging production; do python3 -m json.tool gitops/environments/$$env/environment.json >/tmp/$$env-environment.json; done
	for env in dev staging production; do $(MAKE) gitops-render ENV=$$env; done
	helm lint gitops/apps/example-app/chart
	helm template example-app gitops/apps/example-app/chart --values gitops/apps/example-app/chart/values-dev.yaml >/tmp/example-app.yaml

configure-gitops-values:
	@set -e; \
	CLUSTER="$$(cd $(TF_DIR) && terraform output -raw eks_cluster_name)"; \
	VPC="$$(cd $(TF_DIR) && terraform output -raw vpc_id)"; \
	ALB_ARN="$$(cd $(TF_DIR) && terraform output -raw alb_controller_role_arn)"; \
	CA_ARN="$$(cd $(TF_DIR) && terraform output -raw cluster_autoscaler_role_arn)"; \
	ESO_ARN="$$(cd $(TF_DIR) && terraform output -raw eso_role_arn)"; \
	GRAFANA_ARN="$$(cd $(TF_DIR) && terraform output -raw grafana_cloudwatch_role_arn)"; \
	CLUSTER="$$CLUSTER" VPC="$$VPC" ALB_ARN="$$ALB_ARN" CA_ARN="$$CA_ARN" ESO_ARN="$$ESO_ARN" GRAFANA_ARN="$$GRAFANA_ARN" AWS_REGION="$(AWS_REGION)" ENV="$(ENV)" \
	python3 -c 'import json,os,pathlib; p=pathlib.Path("gitops/environments")/os.environ["ENV"]/ "environment.json"; d=json.loads(p.read_text()); account=os.environ["ALB_ARN"].split(":")[4]; d["aws"]["accountId"]=account; d["aws"]["clusterName"]=os.environ["CLUSTER"]; d["aws"]["region"]=os.environ["AWS_REGION"]; d["aws"]["vpcId"]=os.environ["VPC"]; d["aws"]["roles"]["awsLoadBalancerController"]=os.environ["ALB_ARN"]; d["aws"]["roles"]["clusterAutoscaler"]=os.environ["CA_ARN"]; d["aws"]["roles"]["externalSecrets"]=os.environ["ESO_ARN"]; d["aws"]["roles"]["grafanaCloudWatch"]=os.environ["GRAFANA_ARN"]; p.write_text(json.dumps(d, indent=2) + "\n")'
	$(MAKE) gitops-render ENV=$(ENV)
	@echo "Updated $(GITOPS_ENV_DIR)/environment.json and rendered ArgoCD manifests"

gitops-render:
	python3 scripts/gitops.py render $(ENV)

gitops-validate:
	python3 scripts/gitops.py validate $(ENV)

deploy-argocd:
	helm repo add argo https://argoproj.github.io/argo-helm
	helm repo update argo
	helm upgrade --install argocd argo/argo-cd \
		--namespace argocd --create-namespace \
		--values deploy/argocd/install/values.yaml

apply-argocd-apps: gitops-validate
	kubectl apply -f $(GITOPS_ENV_DIR)/root-app.yaml

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
