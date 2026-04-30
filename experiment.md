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

Создаем файл spark-kubectl/spark-pi.yaml
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
kubectl apply -f spark-kubectl/spark-pi.yaml
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
     -d @spark-rest-api/spark-pi.json
```

# Airflow
Генерация ключа для добавления в [override-values.yaml](airflow/override-values.yaml)
```shell
python3 -c 'import secrets; print(secrets.token_hex(16))'

```
```
f4765c0e9d5fcd06614d5646e4c2191d
```
Добавляем репо
```shell
helm repo add apache-airflow https://airflow.apache.org
helm repo update
```

```
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "spark-operator" chart repository
...Successfully got an update from the "apache-airflow" chart repository

```
 Устанавливаем Airflow в отдельный namespace
```shell
helm upgrade --install airflow apache-airflow/airflow \
--namespace airflow \
--create-namespace
```
Выполнение займет какое-то время
```
Release "airflow" does not exist. Installing it now.
NAME: airflow
LAST DEPLOYED: Wed Apr 29 13:54:41 2026
NAMESPACE: airflow
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
Thank you for installing Apache Airflow 3.2.0!
.....
```

Доступ к интерфейсу
По умолчанию веб-интерфейс не виден снаружи. Пробросьте порт на свою локальную машину:
```bash
kubectl port-forward svc/airflow-api-server 8080:8080 -n airflow

```
Теперь Airflow доступен по адресу `http://localhost:8080`. Логин/пароль по умолчанию: **admin / admin**.

Пока команда запущена в терминале это будет работать. Если закрыть терминал, то проброс перестанет работать.
Альтернативно можно использовать url на все время работы подов airflow. Вот такую комбинацию

```bash
kubectl patch svc airflow-api-server -n airflow -p '{"spec": {"type": "NodePort"}}'

```
```
service/airflow-api-server patched
```
Чтобы получить адрес
```bash
minikube service airflow-api-server -n airflow --url
```
```
http://192.168.49.2:32146
```

>Полученная ссылка будет доступна до перезагрузки пода
Для продуктового решения нужно использовать SERVICE


RBAC [airflow-spark-role.yaml](airflow/airflow-spark-role.yaml)
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: default
  name: airflow-spark-manager
rules:
  - apiGroups: ["sparkoperator.k8s.io"]
    resources: ["sparkapplications"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: airflow-spark-manager-binding
  namespace: default
subjects:
  - kind: ServiceAccount
    name: airflow-worker  # имя SA, под которым работает воркер Airflow
    namespace: airflow
roleRef:
  kind: Role
  name: airflow-spark-manager
  apiGroup: rbac.authorization.k8s.io

```

```shell
 kubectl apply -f airflow/airflow-spark-role.yaml

```
```
role.rbac.authorization.k8s.io/airflow-spark-manager created
rolebinding.rbac.authorization.k8s.io/airflow-spark-manager-binding created
```
Настройка Airflow Connection
В интерфейсе Airflow (Admin -> Connections) нужно отредактировать соединение kubernetes_default:
Conn Type: Kubernetes Cluster Connection
In Cluster Config: Поставьте галочку (так как Airflow уже внутри кластера).
Namespace: default (где будут запускаться Spark-задачи).

Добавление apache-airflow-providers-cncf-kubernetes
```shell
helm upgrade airflow apache-airflow/airflow -n airflow --reuse-values --set "extraPipPackages={apache-airflow-providers-cncf-kubernetes}"
```

Монтирование каталога для файлов даг в minikube
```shell
minikube mount  $(pwd)/airflow/dags:/data/dags
```
```
📁  Mounting host path /home/dm/airflow/dags into VM as /data/dags ...
    ▪ Mount type:   9p
    ▪ User ID:      docker
    ▪ Group ID:     docker
    ▪ Version:      9p2000.L
    ▪ Message Size: 262144
    ▪ Options:      map[]
    ▪ Bind Address: 192.168.49.1:45123
🚀  Userspace file server: ufs starting
✅  Successfully mounted /home/dm/projects/spark-minikube/airflow/dags to /data/dags

📌  NOTE: This process must stay alive for the mount to be accessible ...

```
[override-values.yaml](airflow/override-values.yaml) будет содержать необходимые изменения для стандартного values.yaml
```shell
helm upgrade airflow apache-airflow/airflow \
  -n airflow \
  -f airflow/override-values.yaml 
```

