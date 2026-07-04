# Terraform commands

```shell
# Download and cache providers
terraform init

# Upgrade provider cache
terraform init -upgrade

# Validate necessary changes
terraform plan

# Apply changes
terraform apply

# Delete all previously created resources
terraform destroy

# Import into state file an existing resource that wasn't created by terraform
# Resource must have been defined in a *.tf file
terraform import <resource_type.resource_name> <name_in_destination>

```
