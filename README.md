# AZURE AKS CLUSTER AUTOMATION SCRIPT

This project is intended as an example on how to automatically spin up an Azure AKS Cluster with a LetsEncrypt ingress baked into it.

This is still naive at this point and there are many things that could be enhanced but it's a great starting point for how you can accomplish the automation.

## Prerequisites

In order to use this there are requirements:

1. [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)
2. An Azure account.
3. MacOS Only: [Python 3](https://docs.python-guide.org/starting/install3/osx/) for Azure CLI
4. MacOS Only: [HomeBrew](https://brew.sh) for Azure CLI
5. BASH or ZSH
6. You are properly authenticated with [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/reference-index?view=azure-cli-latest#az-login)

## Getting Started

The project is relatively simple.  Once your environment is setup properly and you can execute basic azure cli commands then you are ready.

First you need to compose/decide on what values to pass in for the required arguments:

```
-s --subscription: Subcription to create or use
-r --resource_group: Resource Group to create or use
-d --dnsname: DNS Name to prepend to the azure c-name
-c --cluster_name: Name to apply to the AKS Cluster being created
-l --location: Azure Region to host the application in
-n --node_count: Number of nodes to create
-p --cert_provider: Select which lets encrypt provider to use [letsencrypt-prod|letsencrypt-staging]
-u --delete_creds: Delete current credentials [true|false]
```

The script does provide a `-h` (`--help`) option if you forget what options are required and what they are used for.

As an example I might create a sample script for a specific environment that looks like this:

```
#!/usr/bin/env bash
set -e

SUBSCRIPTION=MyFirstSubscription
RESOURCE_GROUP=MyResourceGroup
DNSNAME="dev-mycompany"
CLUSTER_NAME=my_awesome_cluster
LOCATION=eastus
NODE_COUNT=2
CERT_PROVIDER="letsencrypt-prod"
DELETE_CUR_CREDENTIALS="true"

./aks_cluster.sh -s $SUBSCRIPTION -r $RESOURCE_GROUP -d $DNSNAME -c $CLUSTER_NAME -l $LOCATION -n $NODE_COUNT -p $CERT_PROVIDER -u "true"
```

Execute and you will spin up an AKS cluster that will have your desired lets encrypt configuration set up.  To validate your configuration you can follow existing [walk through's on deploying sample](https://docs.microsoft.com/en-us/azure/aks/ingress-tls#run-demo-applications) apps provided by Microsoft.

### Local Development

There are no additional requirements beyond the Prerequistes listed above and your favorite shell script editor.  The shell script is not test driven (that is a gap that could be closed as there is logic buried in the script).
