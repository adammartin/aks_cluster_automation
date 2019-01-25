#!/usr/bin/env bash
set -e

OPTS=`getopt -o hsrdc: --long help,subscription,resource_group,dnsname,cluster_name: -n 'parse-options' -- "$@"`

if [ $? != 0 ] ; then echo "Failed parsing options." >&2 ; exit 1 ; fi

USAGE=$(cat <<-EOM
  -h --help: Prints available options for the system
  -a --reg_user: registry user account for authentication
  -b --reg_pw: registry user account password for authentication
  -c --cluster_name: Name to apply to the AKS Cluster being created
  -d --dnsname: DNS Name to prepend to the azure c-name
  -e --email: Email to use for AKS to ACR credentials.
  -g --registry_name: Name of registry in ACR [REGISTRY_NAME].azurecr.io
  -k --secret_name: kubernetes secret name to use when pulling containers into AKS
  -l --location: Azure Region to host the application in
  -n --node_count: Number of nodes to create
  -p --cert_provider: Select which lets encrypt provider to use [letsencrypt-prod|letsencrypt-staging]
  -r --resource_group: Resource Group to create or use
  -s --subscription: Subcription to create or use
  -u --delete_creds: Delete current credentials [true|false]
EOM)

while true; do
  case "$1" in
    -h | --help) echo "$USAGE"; exit 0 ;;
    -a | --reg_user) REG_USER=$2; shift 2 ;;
    -b | --reg_pw) REG_PW=$2; shift 2 ;;
    -c | --cluster_name) CLUSTER_NAME=$2; shift 2 ;;
    -d | --dnsname) DNSNAME=$2; shift 2 ;;
    -e | --email) EMAIL=$2; shift 2 ;;
    -g | --registry_name) REGISTRY_NAME=$2; shift 2 ;;
    -k | --secret_name) SECRET_NAME=$2; shift 2 ;;
    -l | --location) LOCATION=$2; shift 2 ;;
    -n | --node_count) NODE_COUNT=$2; shift 2 ;;
    -p | --cert_provider) CERT_PROVIDER=$2; shift 2 ;;
    -r | --resource_group) RESOURCE_GROUP=$2; shift 2 ;;
    -s | --subscription) SUBSCRIPTION=$2; shift 2 ;;
    -u | --delete_creds) DELETE_CUR_CREDENTIALS=$2; shift 2 ;; # Should change this to just true and false
    --) shift ; break ;;
    * ) break ;;
  esac
done

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


function install_nginx_ingress()
{
  echo "INSTALLING nginx-ingress"
  while [ "$(install_ingress)" = "TILLER NOT READY" ]
  do
    echo "WAITING FOR INGRESS INSTALLATION"
    ((ing_count++)) && ((ing_count==12)) && ing_count=0 && break # STOP AFTER 2 MINUTES
    sleep 10
  done
}


function set_dns_name()
{
  local L_DNSNAME=$1
  while [ "$(valid_ip)" != "VALID" ]
  do
    echo "WAITING FOR IP: $(get_ip)"
    ((ip_count++)) && ((ip_count==18)) && ip_count=0 && break # STOP AFTER 3 MINUTES
    sleep 10
  done

  IP="$(get_ip)"
  PUBLICIPID=$(az network public-ip list --query "[?ipAddress!=null]|[?contains(ipAddress, '$IP')].[id]" --output tsv)

  echo "UPDATE PUBLIC IP [$PUBLICIPID] ADDRESS WITH DNS NAME [$L_DNSNAME]"
  az network public-ip update --ids $PUBLICIPID --dns-name $L_DNSNAME
}


function configure_ssl()
{
  local L_CERT_PROVIDER=$1
  echo "INSTALLING LETSENCRYPT CERT MANAGEMENT"
  kubectl apply \
    -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.6/deploy/manifests/00-crds.yaml

  helm install stable/cert-manager \
      --name cert-manager \
      --namespace kube-system \
      --set ingressShim.defaultIssuerName=$L_CERT_PROVIDER \
      --set ingressShim.defaultIssuerKind=ClusterIssuer

  if [ $L_CERT_PROVIDER = "letsencrypt-staging" ] ; then
    echo "APPLYING LETSENCRYPT STAGING"
    kubectl apply -f cluster-issuer-staging.yaml
  else
    echo "APPLYING LETSENCRYPT PROD"
    kubectl apply -f cluster-issuer-prod.yaml
  fi
}


function jsonValue()
{
  KEY=$1
  num=$2
  awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'$KEY'\042/){print $(i+1)}}}' | tr -d '"' | sed -n ${num}p
}


function create_certificate_yaml()
{
  source /dev/stdin <<<"$(echo 'cat <<EOF >certificates.yaml'; cat certificates_template.yaml; echo EOF;)"
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
install_nginx_ingress
export FQDN="$(set_dns_name $DNSNAME | jsonValue fqdn)"
export CERTIFICATE_PROVIDER=$CERT_PROVIDER
configure_ssl $CERT_PROVIDER
create_certificate_yaml

echo "APPLYING LETSENCRYPT AS CERT AUTHORITY"
kubectl apply -f certificates.yaml
rm -f certificates.yaml


echo "CREATING ACR ACCESS"
kubectl create secret docker-registry $SECRET_NAME --docker-server="$REGISTRY_NAME.azurecr.io" --docker-username=$REG_USER --docker-password=$REG_PW --docker-email=$EMAIL
