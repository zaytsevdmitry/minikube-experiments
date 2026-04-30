from airflow import DAG
from airflow.providers.cncf.kubernetes.operators.spark_kubernetes import SparkKubernetesOperator
from airflow.providers.cncf.kubernetes.sensors.spark_kubernetes import SparkKubernetesSensor
from airflow.providers.cncf.kubernetes.operators.resource import KubernetesDeleteResourceOperator
from datetime import datetime
import json
with DAG(
    dag_id='spark_pi_on_k8s',
    schedule=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['spark', 'kubernetes'],
    # Указываем Airflow искать шаблоны в папка c DAG-ами
    template_searchpath='/opt/airflow/dags',
) as dag:

    submit_job = SparkKubernetesOperator(
        task_id='spark_pi_submit',
        namespace='default',
        application_file='spark-pi.json',
        kubernetes_conn_id='kubernetes_default',
        random_name_suffix=False,
    )
    submit_job