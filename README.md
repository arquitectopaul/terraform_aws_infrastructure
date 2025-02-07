# terraform_aws_infrastructure
IaC para producción. Contiene un VPC con un EC2 con alta disponibilidad y escalabilidad.

# Herramientas
Terraform es una herramienta de Infraestructura como código IaC.
Descarga de Terraform:
https://developer.hashicorp.com/terraform/downloads?product_intent=terraform

Consola de AWS:
https://aws.amazon.com/es/console/

# Pasos
Configure las credenciales de aws en el archivo .env
Para saber la versión de terraform:   terraform --version
Los 4 pasos de terraform son:
init
plan
apply
destroy

Ejecute los scripts:

1-plan-infrastructure-layer:
  stage: layer_1
  when: manual
  before_script:
  - cd infrastructure
  script:
  - terraform init
  - terraform plan -var-file="../infra-production.tfvars"

2-deploy-infrastructure-layer:
  stage: layer_1
  when: manual
  before_script:
  - cd infrastructure
  script:
  - terraform apply -var-file="../infra-production.tfvars" -auto-approve


1-plan-application-layer:
  stage: layer_2
  when: manual
  before_script:
  - cd platform
  script:
  - terraform init
  - terraform plan -var-file="../platform-production.tfvars"

2-deploy-application-layer:
  stage: layer_2
  when: manual
  before_script:
  - cd platform
  script:
  - terraform apply -var-file="../platform-production.tfvars" -auto-approve


1-destroy-infrastructure-layer:
  stage: destroy
  when: manual
  before_script:
  - cd infrastructure
  script:
  - terraform init
  - terraform destroy -var-file="../infra-production.tfvars" --force

2-destroy-application-layer:
  stage: destroy
  when: manual
  before_script:
  - cd platform
  script:
  - terraform init
  - terraform destroy -var-file="../platform-production.tfvars" --force

|