# Общие начальные действия
Запуск minikube с ресурсами
```shell
minikube start --cpus 4 --memory 8192
```
Учетка и креды
```shell
kubectl create serviceaccount spark -n default
```
```
serviceaccount/spark created
```

```shell
 kubectl create clusterrolebinding spark-role --clusterrole=edit --serviceaccount=default:spark --namespace=default
```
```
clusterrolebinding.rbac.authorization.k8s.io/spark-role created
```


Стандартной роли edit в Kubernetes не хватает прав на чтение Custom Resource Definitions (CRD), которые добавил сам оператор.
Дополнительно делаем файл spark-rbac.yaml
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: spark-operator-role
rules:
- apiGroups: ["sparkoperator.k8s.io"]
  resources: ["sparkapplications", "scheduledsparkapplications", "sparkapplications/status"]
  verbs: ["*"]
- apiGroups: [""]
  resources: ["pods", "configmaps", "services", "secrets", "persistentvolumeclaims"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: spark-operator-role-binding
subjects:
- kind: ServiceAccount
  name: spark
  namespace: default
roleRef:
  kind: ClusterRole
  name: spark-operator-role
  apiGroup: rbac.authorization.k8s.io

```
Передаем конфигурацию 
```shell
kubectl apply -f spark-rbac.yaml
```

# Варианты экспериментов

## Spark operator + kubectl
Добавляем helm, он развернет оператор Spark
```shell
helm repo add spark-operator https://kubeflow.github.io/spark-operator

helm repo update
```
Развернем оператор
```shell
helm install my-spark-operator spark-operator/spark-operator \
--namespace spark-operator \
--create-namespace \
--set webhook.enable=true
```
Проверяем, помним что для развертывания может потребоваться какое то время
```shell
kubectl get pods -n spark-operator
```

```
NAME                                            READY   STATUS              RESTARTS   AGE
my-spark-operator-controller-6bdc5dc844-ppq4t   0/1     ContainerCreating   0          12s
my-spark-operator-webhook-7c5bdff685-gsdzl      0/1     ContainerCreating   0          12s
```
Немного позднее
```shell
kubectl get pods -n spark-operator
```
```
NAME                                            READY   STATUS    RESTARTS   AGE
my-spark-operator-controller-6bdc5dc844-ppq4t   1/1     Running   0          4m9s
my-spark-operator-webhook-7c5bdff685-gsdzl      1/1     Running   0          4m9s
```

Создаем файл spark-pi.yaml
```yaml
apiVersion: "sparkoperator.k8s.io/v1beta2"
kind: SparkApplication
metadata:
  name: spark-pi
  namespace: default
spec:
  type: Scala
  mode: cluster
  image: "apache/spark:3.5.0"
  imagePullPolicy: IfNotPresent
  mainClass: org.apache.spark.examples.SparkPi
  mainApplicationFile: "local:///opt/spark/examples/jars/spark-examples_2.12-3.5.0.jar"
  sparkVersion: "3.5.0"
  restartPolicy:
    type: Never
  driver:
    cores: 1
    memory: "512m"
    labels:
      version: 3.5.0
    serviceAccount: spark # Тот самый SA, для которого мы правили RBAC
  executor:
    cores: 1
    instances: 1
    memory: "512m"
    labels:
      version: 3.5.0

```
Запускаем 
```shell
kubectl apply -f spark-pi.yaml
```

Тут опять можно немного подождать. Во-первых, может не быть локального образа. Скачивание займет некоторое время при первой попытке
Во-вторых инициализация контейнера и старт задачи.
Проверяем логи
```shell
kubectl logs spark-pi-driver
```
Как понять что все хорошо? Цел работы кода вычислить число "пи" ищем в логе:
Pi is roughly 3.14...

# Curl + Rest API
Конфигурацию задачи переносим в json

```json
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
```
Проверяем логи
```shell
kubectl logs spark-pi-curl-direct-driver
```
Как понять что все хорошо? Цель работы кода вычислить число "пи" ищем в логе:
Pi is roughly 3.14...


Для работы через Rest API  потребуется токен. Готовый можно взять локально в настройках kubectl

```shell
# 1. Получаем адрес API-сервера Minikube
APISERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

# 2. Создаем временный токен для ServiceAccount (нужен kubectl 1.24+)
TOKEN=$(kubectl create token spark)

curl -k -X POST "$APISERVER/apis/sparkoperator.k8s.io/v1beta2/namespaces/default/sparkapplications" \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d @spark-pi.json
```

