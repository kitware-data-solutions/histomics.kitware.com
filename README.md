> This is the instance of the Histomics AWS deployment terraform associated with **histomics.kitware.com**.
> Its state is managed on Kitware's Terraform Cloud organization.

# Histomics AWS deployment scripts

This repository contains infrastructure-as-code for reproducible Histomics deployments on AWS
using highly managed, scalable services, including

* Elastic Container Service for the web application
* EC2 instances for celery worker nodes
* MongoDB Atlas for the database
* Amazon MQ as the celery queue
* CloudWatch for log persistence
* Sentry integration (optional)

### Prerequisites

1. Obtain a domain name via AWS Route53, and set the `domain_name` terraform variable to its value.
1. Create an SSH keypair and set the public key as the `ssh_public_key` terraform variable.
   This is the key that will be authorized on the worker EC2 instance(s).
1. Set AWS credentials in your shell environment.
1. In your target MongoDB Atlas organization, create a new API key and set the public and private
   key in your local environment in the variables `MONGODB_ATLAS_PUBLIC_KEY` and
   `MONGODB_ATLAS_PRIVATE_KEY`.
1. Set the target MongoDB Atlas organization ID as the `mongodbatlas_org_id` terraform variable.

### Building the worker AMI

1. `cd packer`
1. `packer build worker.pkr.hcl`
1. Use the resulting AMI ID as the `worker_ami_id` terraform variable.

### Deploying

1. `DOCKER_DEFAULT_PLATFORM=linux/amd64 docker build -t zachmullen/histomics-load-test -f histomicsui.Dockerfile .`
1. `docker push zachmullen/histomics-load-test`
1. Copy the SHA from the docker push command and paste it into `main.tf`
1. Push and merge the resulting change, and ensure the plan and apply succeeds in TF Cloud.

**Note**: the first time you run the terraform plan on TF Cloud, it will fail with a message like:

```hcl
count = length(data.aws_subnets.default.ids)
```

> The "count" value depends on resource attributes that cannot be determined until apply, so Terraform cannot predict how many instances will be created. To work around this, use the -target argument to first apply only the resources that the count depends on.

This is because the length of the set of subnets is unknown until the first apply, which is a limitation of terraform itself. To work around this, the very first time you run the plan, set the following env var in
TF Cloud:

* Key: `TF_CLI_ARGS_plan`
* Value: `-target=data.aws_subnets.default`

Run and apply the resulting plan, and then delete that env var in TF Cloud. Subsequent runs should then work.
