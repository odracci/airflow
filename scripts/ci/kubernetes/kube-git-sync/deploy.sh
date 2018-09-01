#!/usr/bin/env bash
#
#  Licensed to the Apache Software Foundation (ASF) under one   *
#  or more contributor license agreements.  See the NOTICE file *
#  distributed with this work for additional information        *
#  regarding copyright ownership.  The ASF licenses this file   *
#  to you under the Apache License, Version 2.0 (the            *
#  "License"); you may not use this file except in compliance   *
#  with the License.  You may obtain a copy of the License at   *
#                                                               *
#    http://www.apache.org/licenses/LICENSE-2.0                 *
#                                                               *
#  Unless required by applicable law or agreed to in writing,   *
#  software distributed under the License is distributed on an  *
#  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY       *
#  KIND, either express or implied.  See the License for the    *
#  specific language governing permissions and limitations      *
#  under the License.                                           *

set -x

IMAGE=${1:-airflow/ci}
TAG=${2:-latest}
DIRNAME=$(cd "$(dirname "$0")"; pwd)

# Fix file permissions
sudo chown -R travis.travis $HOME/.kube $HOME/.minikube

configmap_template=`cat "$DIRNAME/configmaps.template.yaml" | sed "s|{{TRAVIS_BRANCH}}|$TRAVIS_BRANCH|g" | sed "s|{{TRAVIS_REPO_SLUG}}|$TRAVIS_REPO_SLUG|g"`
airflow_template=`cat "$DIRNAME/airflow.template.yaml" | sed "s|{{TRAVIS_BRANCH}}|$TRAVIS_BRANCH|g" | sed "s|{{TRAVIS_REPO_SLUG}}|$TRAVIS_REPO_SLUG|g"`

kubectl delete -f $DIRNAME/postgres.yaml
echo "$airflow_template" kubectl delete -f -
kubectl delete -f $DIRNAME/secrets.yaml

set -e

kubectl apply -f $DIRNAME/secrets.yaml
echo "$configmap_template" | kubectl apply -f -
kubectl apply -f $DIRNAME/postgres.yaml
kubectl apply -f $DIRNAME/volumes.yaml
echo "$airflow_template" | kubectl apply -f -

# wait for up to 10 minutes for everything to be deployed
for i in {1..150}
do
  echo "------- Running kubectl get pods -------"
  PODS=$(kubectl get pods | awk 'NR>1 {print $0}')
  echo "$PODS"
  NUM_AIRFLOW_READY=$(echo $PODS | grep airflow | awk '{print $2}' | grep -E '([0-9])\/(\1)' | wc -l | xargs)
  NUM_POSTGRES_READY=$(echo $PODS | grep postgres | awk '{print $2}' | grep -E '([0-9])\/(\1)' | wc -l | xargs)
  if [ "$NUM_AIRFLOW_READY" == "1" ] && [ "$NUM_POSTGRES_READY" == "1" ]; then
    break
  fi
  sleep 4
done

POD=$(kubectl get pods -o go-template --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | grep airflow | head -1)

echo "------- pod description -------"
kubectl describe pod $POD
echo "------- webserver init container logs - init -------"
kubectl logs $POD init
echo "------- webserver init container logs - git-sync-clone -------"
kubectl logs $POD git-sync-clone
echo "------- webserver logs -------"
kubectl logs $POD webserver
echo "------- scheduler logs -------"
kubectl logs $POD scheduler
echo "--------------"
