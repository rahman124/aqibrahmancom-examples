# vnet_peering

A terraform module for peering two Azure Virtual Networks in separate subscriptions

## Requirements

Two virtual networks in separate subscriptions

## Providers

| Name | Version |
|------|---------|
| azurerm.initiator | >= 2.99.0 |
| azurerm.target | >= 2.99.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| peerings | Map of peerings to be created | `map` | n/a | yes |
| allow_virtual_network_access | Controls if the VMs in the remote virtual network can access VMs in the local virtual network | `bool` | `true` | no |
| allow_forwarded_traffic | Controls if forwarded traffic from VMs in the remote virtual network is allowed | `bool` | `true` | no |


## Outputs

No outputs.
