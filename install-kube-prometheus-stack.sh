#!/bin/bash
#
# this script depends on:
# 1 - helm being installed
# 2 - the existance of the namespace 'monitoring' 
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install -n monitoring kube-prometheus-stack prometheus-community/kube-prometheus-stack
