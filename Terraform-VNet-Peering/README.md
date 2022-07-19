## Deploy Azure Virtual Network Peering with a Terraform Module

In this blog post I'll take you through this Terraform module I created which you can use to deploy VNet peerings in your Azure tenant.

Consider a typical hub and spoke network, the Virtual Networks may be spread out across your tenant in multiple subscriptions. Terraform needs a way to create these VNets in multiple subscriptions, which is where providers come in.

Terraform providers adds a set of resource types and/or data sources that it can manage. Every resource type is implemented by a provider.

Best practices call for keeping our code DRY (Don't Repeat Yourself) in order to reduce maintenance overhead and allow our code to be less susceptible to errors.

With the above in mind, I will walk through my implementation so you can configure and implement it in your environment.

Post - https://aqibrahman.com/deploy-azure-virtual-network-peering-with-a-terraform-module