# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an Azure infrastructure deployment project for a web-based calculator application. The project includes:

- Azure Resource Manager (ARM) template for VM deployment (`azuredeploy_250908.json`)
- A Python-based web calculator with MySQL backend (to be implemented)
- Automated VM setup via shell script (`setup_webserver.sh`)

## Key Project Files

- `azuredeploy_250908.json` - ARM template that deploys Ubuntu VM with network security group, virtual network, and public IP
- `lkb_needs.txt` - Korean requirements document outlining the project scope
- `setup_webserver.sh` - Shell script for automated installation of Python, MySQL, and web application (referenced but not present)

## Deployment Commands

The project is deployed using Azure CLI:

```bash
# Login to Azure
az login

# Create resource group (use unique 3-digit number)
az group create --name azure-vm-XXX --location koreacentral

# Deploy infrastructure
az deployment group create \
  --resource-group azure-vm-XXX \
  --template-file azuredeploy.json \
  --parameters adminPassword="VM_PASSWORD" mysqlPassword="DB_PASSWORD" scriptsBaseUri="https://raw.githubusercontent.com/YOUR_REPO_PATH"
```

## Application Requirements

Based on `lkb_needs.txt`, the web application should implement:

1. **Calculator Interface**: Web page with number buttons (1-9) and basic arithmetic operations, displaying results in a text box
2. **History Interface**: Web page showing a list of calculation results/history
3. **Backend**: Python web service with MySQL database for storing calculation history

## Infrastructure Details

- **Platform**: Ubuntu 22.04 LTS on Azure VM
- **VM Size**: Standard_D2s_v3 (default)
- **Network**: Virtual network (10.0.0.0/16) with subnet (10.0.0.0/24)
- **Security**: NSG allowing SSH (22), HTTP (80), and MySQL (3306) from specified IP range
- **Database**: MySQL server with configurable credentials

## Development Notes

- Application code needs to be developed and placed in a GitHub repository
- The `scriptsBaseUri` parameter should point to the raw GitHub URL containing `setup_webserver.sh`
- Manual GitHub upload process (no automated deployment pipeline)
- Default admin username: "lantine"
- Default allowed IP range: 211.33.181.0/24 (should be customized for security)