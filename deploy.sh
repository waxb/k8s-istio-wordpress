#!/bin/bash

which helm > /dev/null || echo "helm not installed, exiting..."
which kubectl > /dev/null || echo "kubectl not installed, exiting..."

[[ $1 == "-l" || $1 == "--local" ]] && isLocal=true || isLocal=false
trap "{ $isLocal && minikube delete ; }" SIGINT SIGTERM ERR EXIT

#start cluster
if $isLocal ; then
	minikube start --memory 8192 --cpus 4
	minikube tunnel &
fi

if ! kubectl get ns > /dev/null 2>&1 ; then
	echo "cluster not found, exiting..."
	exit
fi

#add istio helm repo
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

#install istio{,-gateway} on cluster
kubectl create namespace istio-system
helm install istio-base istio/base -n istio-system
helm install istiod istio/istiod -n istio-system --wait
helm install istio-ingressgateway istio/gateway -n istio-system --wait

#deploy wordpress
kubectl create ns wp-istio
kubectl label namespace wp-istio istio-injection=enabled
kubectl create secret generic mysql-pass --from-literal=password=s2cr*et -n wp-istio
kubectl apply -f mysql-deployment.yaml -n wp-istio
kubectl apply -f wordpress-deployment.yaml -n wp-istio
kubectl apply -f wordpress-gateway.yaml -n wp-istio

echo "Waiting for WordPress become available"
kubectl wait --for=condition=available deployment/wordpress -n wp-istio --timeout=300s || "Timed out, exiting..."

echo "EXTERNAL IP: $(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath=\'{.status.loadBalancer.ingress[0].ip}\')\nConsume! To finish and clean up, press return!"
read
$isLocal && kill $(ps aux | grep "minikube tunnel" | grep -v grep | awk '{ print $2 }')
