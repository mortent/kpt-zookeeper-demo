#!/bin/bash
# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

export PROMPT_TIMEOUT=1

########################
# include the magic
########################
. demo-magic.sh

rm -fr hydrated
rm -fr envs
rm -fr bases/zookeeper

# hide the evidence
clear

pwd

bold=$(tput bold)
normal=$(tput sgr0)

# start demo
clear
p "# fetch version v0.1.0 of the published package"
pe "kpt pkg get https://github.com/mortent/kpt-packages/zookeeper@v0.1.0 bases/zookeeper"
wait

p "# look at the setters"
pe "kpt cfg list-setters bases/zookeeper"
wait

p "# set number of replicas to 1 and try it out. We use a kpt function to generate the correct list of replicas for ZOO_SERVERS"
pe "kpt cfg set bases/zookeeper replicas 1"
pe "kpt live init bases/zookeeper"
pe "kpt fn source bases/zookeeper | kpt fn run | kpt live apply --reconcile-timeout=10m --output=table"
wait

p "# remove the installed package and the inventory template"
pe "kpt live destroy bases/zookeeper"
pe "rm bases/zookeeper/inventory-template.yaml"
wait

p "# manually reduce the zookeeper tick time in the fork"
pe "sed -i '' 's/"2000"/"1000"/g' bases/zookeeper/statefulset.yaml"
wait

p "# add a kustomization file so we can use this package as the base for kustomize overlays"
pe 'cat <<EOF >bases/zookeeper/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
- statefulset.yaml
- svc-headless.yaml
- svc.yaml
EOF
'
wait

p "# commit and push the forked version of the package"
pe "git add bases && git commit -m \"zookeeper\""
pe "git push origin master"
pe "git tag bases/zookeeper/v0.1.0"
pe "git push origin bases/zookeeper/v0.1.0"
wait

p "# create configuration for dev and staging envs. Both will deploy into the preprod namespace"
pe "mkdir -p envs/dev/zookeeper"
pe 'cat <<EOF >envs/dev/zookeeper/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
- github.com/mortent/kpt-zookeeper-demo/bases/zookeeper?ref=bases/zookeeper/v0.1.0

namePrefix: "dev-"
commonLabels:
  environment: dev
namespace: preprod
patchesStrategicMerge:
- |-
  apiVersion: apps/v1
  kind: StatefulSet
  metadata:
    name: zookeeper
  spec:
    replicas: 3
EOF
'
pe "mkdir -p envs/staging/zookeeper"
pe 'cat <<EOF >envs/staging/zookeeper/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
- github.com/mortent/kpt-zookeeper-demo/bases/zookeeper?ref=bases/zookeeper/v0.1.0

namePrefix: "staging-"
commonLabels:
  environment: staging
namespace: preprod
patchesStrategicMerge:
- |-
  apiVersion: apps/v1
  kind: StatefulSet
  metadata:
    name: zookeeper
  spec:
    replicas: 5
EOF
'
wait

p "# generate the hydrated verson of the config for both envs"
pe "mkdir -p hydrated/dev/zookeeper"
pe "kustomize build envs/dev/zookeeper | kpt fn run | kpt fn sink hydrated/dev/zookeeper"
pe "mkdir -p hydrated/staging/zookeeper"
pe "kustomize build envs/staging/zookeeper | kpt fn run | kpt fn sink hydrated/staging/zookeeper"
wait

p "# create inventory templates for both envs"
pe "kpt live init hydrated/dev/zookeeper"
pe "kpt live init hydrated/staging/zookeeper"
pe "cat hydrated/dev/zookeeper/inventory-template.yaml"
wait

p "# apply both envs"
pe "kubectl create ns preprod"
pe "kpt live apply hydrated/dev/zookeeper --reconcile-timeout=2m --output=table"
pe "kpt live apply hydrated/staging/zookeeper --reconcile-timeout=2m --output=table"
pe "kubectl -n preprod get sts"
wait

p "# pull in updates from upstream to the fork. Upstream package now contains a PDB"
pe "kpt pkg update bases/zookeeper@v0.2.0 --strategy=resource-merge"
pe "cat bases/zookeeper/pdb.yaml"
wait

p "# update the kustomization file to include the newly added pdb.yaml manifest"
pe 'cat <<EOF >bases/zookeeper/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
- statefulset.yaml
- svc-headless.yaml
- svc.yaml
- pdb.yaml
EOF
'
wait

p "# commit the changes to my fork and tag the new version"
pe "git add bases && git commit -m \"zookeeper updates\""
pe "git push origin master"
pe "git tag bases/zookeeper/v0.2.0"
pe "git push origin bases/zookeeper/v0.2.0"
wait

p "# update the dev configuration to use the new version of the fork and increase the number of replicas to 5"
pe "sed -i '' 's/v0.1.0/v0.2.0/g' envs/dev/zookeeper/kustomization.yaml"
pe "sed -i '' 's/replicas: 3/replicas: 5/g' envs/dev/zookeeper/kustomization.yaml"
wait

p "# hydrate the new configuration for dev and apply it to the cluster"
pe "kustomize build envs/dev/zookeeper | kpt fn run | kpt fn sink hydrated/dev/zookeeper"
pe "kpt live apply hydrated/dev/zookeeper --reconcile-timeout=2m --output=table"
wait