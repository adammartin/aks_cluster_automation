#!/bin/bash

IP="40.70.78.214"
DNSNAME="dev-mednax-kubernetes"
CERT_PROVIDER="letsencrypt-prod" # letsencrypt-staging

# Get the resource-id of the public ip
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
