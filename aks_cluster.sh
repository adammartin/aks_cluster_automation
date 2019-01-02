#!/usr/bin/env bash
set -e

az account set -s ApplicationDevelopment_DEV # EXTRACT ApplicationDevelopment_DEV to a passed in variables
echo "EXECUTING SCRIPTS FOR THE FOLLOWING SUBSCRIPTIONS:"
az account show
echo "CREATING/UPDATING THE FOLLOWING RESOURCE GROUP:"
az group create --name SharedApplicationCluster --location centralus # EXTRACT location
echo "CREATING/UPDATING AKS CLUSTER:"
# az aks create --subscription ApplicationDevelopment_DEV --resource-group SharedApplicationCluster --name azshrappaks01d --node-count 1 --enable-addons monitoring --generate-ssh-keys # EXTRACT name, resource group
az aks create --subscription ApplicationDevelopment_DEV --resource-group SharedApplicationCluster --name azshrappaks01d --node-count 1 --generate-ssh-keys # EXTRACT name, resource group
az aks get-credentials --resource-group SharedApplicationCluster --name azshrappaks01d # USE extracted name
kubectl get nodes
