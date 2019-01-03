#!/usr/bin/env bash
set -e

# VARIABLES TO EXTRACT
SUBSCRIPTION=ApplicationDevelopment_DEV
LOCATION=eastus2
RESOURCE_GROUP=SharedApplicationCluster
CLUSTER_NAME=azshrappaks01d
NODE_COUNT=2
DELETE_CUR_CREDENTIALS=true

az account set -s $SUBSCRIPTION
echo "EXECUTING SCRIPTS FOR THE FOLLOWING SUBSCRIPTIONS:"
az account show
echo "CREATING/UPDATING THE FOLLOWING RESOURCE GROUP:"
az group create --name $RESOURCE_GROUP --location $LOCATION
echo "CREATING/UPDATING AKS CLUSTER:"
# --subscription $SUBSCRIPTION --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --node-count $NODE_COUNT --enable-addons monitoring --generate-ssh-keys
az aks create --subscription $SUBSCRIPTION --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --node-count $NODE_COUNT --generate-ssh-keys

# NOTE: You can run into a pain point if your local ~/.kube/config file already has the same named cluster in place.
if [ $DELETE_CUR_CREDENTIALS = true ] ; then
  echo "DELETING ~/.kube/config"
  rm ~/.kube/config
fi
az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME
kubectl get nodes


# Please note: by default, Tiller is deployed with an insecure 'allow unauthenticated users' policy.
# To prevent this, run `helm init` with the --tiller-tls-verify flag.
# For more information on securing your installation see: https://docs.helm.sh/using_helm/#securing-your-helm-installation
echo "INSTALLING HELM"
kubectl apply -f helm-rbac.yaml
helm init --service-account tiller
helm repo update

echo "INSTALLING nginx-ingress"
helm install stable/nginx-ingress --namespace kube-system --set controller.replicaCount=$NODE_COUNT --version 0.23.0
kubectl get service -l app=nginx-ingress --namespace kube-system


# Continue from: https://docs.microsoft.com/en-us/azure/aks/ingress-tls#configure-a-dns-name
