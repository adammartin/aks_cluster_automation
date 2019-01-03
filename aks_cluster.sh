#!/usr/bin/env bash
set -e

# VARIABLES TO EXTRACT
SUBSCRIPTION=ApplicationDevelopment_DEV
LOCATION=eastus2
RESOURCE_GROUP=SharedApplicationCluster
CLUSTER_NAME=azshrappaks01d
NODE_COUNT=2
DNSNAME="dev-mednax-kubernetes"
CERT_PROVIDER="letsencrypt-prod" # letsencrypt-staging
DELETE_CUR_CREDENTIALS="true"

function valid_ip()
{
    local ip="$(get_ip)"
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "VALID"
    else
        echo "INVALID"
    fi
}

function get_ip()
{
  kubectl get service -l app=nginx-ingress --namespace kube-system | awk 'FNR == 2 {print $4}'
}

az account set -s $SUBSCRIPTION
echo "EXECUTING SCRIPTS FOR THE FOLLOWING SUBSCRIPTIONS:"
az account show
echo "CREATING/UPDATING THE FOLLOWING RESOURCE GROUP:"
az group create --name $RESOURCE_GROUP --location $LOCATION
echo "CREATING/UPDATING AKS CLUSTER:"
# --subscription $SUBSCRIPTION --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --node-count $NODE_COUNT --enable-addons monitoring --generate-ssh-keys
az aks create --subscription $SUBSCRIPTION --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --node-count $NODE_COUNT --generate-ssh-keys

# NOTE: You can run into a pain point if your local ~/.kube/config file already has the same named cluster in place.
if [ $DELETE_CUR_CREDENTIALS = "true" ] ; then
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

echo "PAUSING 10 SECONDS FOR AZURE TO SPIN UP"
sleep 10

echo "INSTALLING nginx-ingress"
helm install stable/nginx-ingress --namespace kube-system --set controller.replicaCount=$NODE_COUNT --version 0.23.0
IP=kubectl get service -l app=nginx-ingress --namespace kube-system | awk 'FNR == 2 {print $4}'

while [ "$(valid_ip)" != "VALID" ]
do
  echo "WAITING FOR IP: $(get_ip)"
  ((count++)) && ((count==18)) && count=0 && break # STOP AFTER 3 MINUTES
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
# Continue from: https://docs.microsoft.com/en-us/azure/aks/ingress-tls#configure-a-dns-name
