#!/bin/sh
# 1. Получаем адрес API-сервера Minikube
APISERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

# 2. Создаем временный токен для ServiceAccount (нужен kubectl 1.24+)
TOKEN=$(kubectl create token spark)

# 3. Конвертируем ваш YAML в JSON (требуется установленный python или jq)
# Если нет python, можно просто скопировать JSON из блока ниже
cat <<EOF > spark-pi.json
{
  "apiVersion": "sparkoperator.k8s.io/v1beta2",
  "kind": "SparkApplication",
  "metadata": {
    "name": "spark-pi-curl-direct"
  },
  "spec": {
    "type": "Scala",
    "mode": "cluster",
    "image": "apache/spark:3.5.0",
    "mainClass": "org.apache.spark.examples.SparkPi",
    "mainApplicationFile": "local:///opt/spark/examples/jars/spark-examples_2.12-3.5.0.jar",
    "sparkVersion": "3.5.0",
    "driver": {
      "cores": 1,
      "memory": "512m",
      "serviceAccount": "spark"
    },
    "executor": {
      "cores": 1,
      "instances": 1,
      "memory": "512m"
    }
  }
}
EOF
