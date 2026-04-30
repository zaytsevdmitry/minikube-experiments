#!/bin/sh
# 1. Получаем адрес API-сервера Minikube
APISERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

# 2. Создаем временный токен для ServiceAccount (нужен kubectl 1.24+)
TOKEN=$(kubectl create token spark)

curl -k -X POST "$APISERVER/apis/sparkoperator.k8s.io/v1beta2/namespaces/default/sparkapplications" \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d @spark-pi.json