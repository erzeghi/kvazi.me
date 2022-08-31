# Kvazi

Repo for personal page [kvazi.me](https://kvazi.me/)

# Infra

This static page is hosted on S3.

Terraform is used for managing infrastructure.

State backend is stored in AWS. CloudFormation used to build Terraform backend :) Useful repo: [tf-state-backend-s3-cloudformation](https://github.com/tiborhercz/tf-state-backend-s3-cloudformation)