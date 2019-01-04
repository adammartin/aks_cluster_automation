#!/usr/bin/env bash
set -e

# VARIABLES TO EXTRACT
SUBSCRIPTION=ApplicationDevelopment_DEV
RESOURCE_GROUP=SharedApplicationCluster2
DNSNAME="dev2-mednax-kubernetes"
CLUSTER_NAME=azshrappaks02d
LOCATION=eastus
NODE_COUNT=2
CERT_PROVIDER="letsencrypt-prod" # letsencrypt-staging
DELETE_CUR_CREDENTIALS="false"


function get_ip()
{
  kubectl get service -l app=nginx-ingress --namespace kube-system | awk 'FNR == 2 {print $4}'
}


function valid_ip()
{
    local ip="$(get_ip)"
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "VALID"
    else
        echo "INVALID"
    fi
}


function install_ingress()
{
  {
    helm install stable/nginx-ingress --namespace kube-system --set controller.replicaCount=$NODE_COUNT --version 0.23.0
  } || {
    echo "TILLER NOT READY"
  }
}


function retrieve_credentials()
{
  # NOTE: You can run into a pain point if your local ~/.kube/config file already has the same named cluster in place from previous instance.
  local DELETE_CREDS=$1
  local L_RESOURCE_GROUP=$2
  local L_CLUSTER_NAME=$3
  if [ $DELETE_CREDS = "true" ] ; then
    echo "DELETING ~/.kube/config"
    rm ~/.kube/config
  fi
  az aks get-credentials --resource-group $L_RESOURCE_GROUP --name $L_CLUSTER_NAME
  kubectl get nodes
}


function install_helm()
{
  # Please note: by default, Tiller is deployed with an insecure 'allow unauthenticated users' policy.
  # To prevent this, run `helm init` with the --tiller-tls-verify flag.
  # For more information on securing your installation see: https://docs.helm.sh/using_helm/#securing-your-helm-installation
  echo "INSTALLING HELM"
  kubectl apply -f helm-rbac.yaml
  helm init --service-account tiller
  helm repo update
}


az account set -s $SUBSCRIPTION
echo "EXECUTING SCRIPTS FOR THE FOLLOWING SUBSCRIPTIONS:"
az account show
echo "CREATING/UPDATING THE FOLLOWING RESOURCE GROUP:"
az group create --name $RESOURCE_GROUP --location $LOCATION
echo "CREATING/UPDATING AKS CLUSTER:"
# --subscription $SUBSCRIPTION --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --node-count $NODE_COUNT --enable-addons monitoring --generate-ssh-keys
az aks create --subscription $SUBSCRIPTION --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --node-count $NODE_COUNT --generate-ssh-keys

retrieve_credentials $DELETE_CUR_CREDENTIALS $RESOURCE_GROUP $CLUSTER_NAME
install_helm

#echo "PAUSING 30 SECONDS FOR AZURE TO SPIN UP"
#sleep 30

echo "INSTALLING nginx-ingress"
while [ "$(install_ingress)" = "TILLER NOT READY" ]
do
  echo "WAITING FOR INGRESS INSTALLATION"
  ((ing_count++)) && ((ing_count==12)) && ing_count=0 && break # STOP AFTER 2 MINUTES
  sleep 10
done

while [ "$(valid_ip)" != "VALID" ]
do
  echo "WAITING FOR IP: $(get_ip)"
  ((ip_count++)) && ((ip_count==18)) && ip_count=0 && break # STOP AFTER 3 MINUTES
  sleep 10
done

IP="$(get_ip)"
PUBLICIPID=$(az network public-ip list --query "[?ipAddress!=null]|[?contains(ipAddress, '$IP')].[id]" --output tsv)

echo "UPDATE PUBLIC IP ADDRESS WITH DNS NAME"
az network public-ip update --ids $PUBLICIPID --dns-name $DNSNAME

echo "INSTALLING LETSENCRYPT CERT MANAGEMENT"
helm install stable/cert-manager \
    --namespace kube-system \
    --set ingressShim.defaultIssuerName=$CERT_PROVIDER \
    --set ingressShim.defaultIssuerKind=ClusterIssuer

if [ $CERT_PROVIDER = "letsencrypt-staging" ] ; then
  echo "APPLYING LETSENCRYPT STAGING"
  kubectl apply -f cluster-issuer-staging.yaml
else
  echo "APPLYING LETSENCRYPT PROD"
  kubectl apply -f cluster-issuer-prod.yaml
fi
