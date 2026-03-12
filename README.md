> This is the instance of the Histomics AWS deployment terraform associated with **histomics.kitware.com**.
> Its state is managed on Kitware's Terraform Cloud organization.

### Prerequisites

1. Obtain a domain name via AWS Route53, and set the `domain_name` terraform variable to its value.
1. Create an SSH keypair and set the public key as the `ssh_public_key` terraform variable.
   This is the key that will be authorized on the worker EC2 instance(s).
1. Set AWS credentials in your shell environment.
1. In your target MongoDB Atlas organization, create a new API key and set the public and private
   key in your local environment in the variables `MONGODB_ATLAS_PUBLIC_KEY` and
   `MONGODB_ATLAS_PRIVATE_KEY`.
1. Set the target MongoDB Atlas organization ID as the `mongodbatlas_org_id` terraform variable.
