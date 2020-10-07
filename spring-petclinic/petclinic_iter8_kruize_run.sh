#!/bin/bash
#
# Copyright (c) 2020, 2020 Red Hat Corporation and others.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

CPUS=7
MEMORY=8500
ISTIO_VER="1.6.8"
ARCH="x86_64"
JDURATION=300
JUSERS=500

LOGFILE="${PWD}/setup.log

function err_exit() {
	if [ $? != 0 ]; then
		printf "$*"
		echo
		echo "See ${LOGFILE} for more details"
		exit -1
	fi
}

function install_minikube() {
	echo "==========================================================="
	echo "Downloading and Installing minikube..."
	echo "==========================================================="
	# Download kubectl
	curl -LO "https://storage.googleapis.com/kubernetes- release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl" >>${LOGFILE}
	err_exit "Error: Error downloading kubectl"

	chmod +x ./kubectl
	sudo mv ./kubectl /usr/local/bin/kubectl
	kubectl version --client >>${LOGFILE}
	err_exit "Error: kubectl is not working"

	#Download minikube
	curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 >>${LOGFILE}
	err_exit "Error: Error downloading minikube"

	chmod +x minikube
	sudo install minikube /usr/local/bin/ >>${LOGFILE}
	err_exit "Error: Error installing minikube"
}

function start_minikube() {
	echo "==========================================================="
	echo "Starting minikube..."
	echo "==========================================================="
	minikube start --vm-driver=kvm2 --cpus ${CPUS} --memory ${MEMORY} >>${LOGFILE}
	err_exit "Error: Error starting minikube"
	minikube status >>${LOGFILE}
}

function install_istio() {
	echo "==========================================================="
	echo "Downloading and Installing Istio..."
	echo "==========================================================="
	# Download istio. Using 1.6.8 instead of latest to avoid issues.
	curl -L https://istio.io/downloadIstio | ISTIO_VERSION=${ISTIO_VER} TARGET_ARCH=${ARCH} sh - >>${LOGFILE}
	err_exit "Error: Error downloading istio"
	export PATH=$PWD/istio-${ISTIO_VER}/bin:$PATH
	
	#Install the demo profile.
	istioctl install --set profile=demo >>${LOGFILE}
	err_exit "Error: Error installing Istio"

	#Enable telemtry,pilot, prometheus
	istioctl install --set components.telemetry.enabled=true >>${LOGFILE}
	err_exit "Error: Error installing components"
	istioctl install --set components.pilot.enabled=true >>${LOGFILE}
	err_exit "Error: Error installing components"

	istioctl install --set components.prometheus.enabled=true >>${LOGFILE}

	#Enable Grafana
	istioctl install --set addonComponents.grafana.enabled=true >>${LOGFILE}
	err_exit "Error: Error installing components"

	kubectl get pods --all-namespaces 
	sleep 120
	#
	export INGRESS_HOST=$(minikube ip)
	export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
	export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT
}

function install_iter8() {
	echo "==========================================================="
	echo "Installing iter8..."
	echo "==========================================================="
	curl -L -s https://raw.githubusercontent.com/iter8-tools/iter8/v1.0.0-rc3/install/install.sh | /bin/bash - >>${LOGFILE}
	err_exit "Error: Error installing iter8" 
	kubectl get pods -n iter8

	#Wait till all pods come into running state
	sleep 120
}

function deploy_petclinic() {
	echo "==========================================================="
	echo "Deploying petclinic first version..."
	echo "==========================================================="
	kubectl apply -f petclinic-namespace.yaml >>${LOGFILE}
	err_exit "Error: Error creating namespace"

	kubectl --namespace petclinic-iter8 apply -f petclinic-app.yaml >>${LOGFILE}
	kubectl --namespace petclinic-iter8 get pods
	sleep 120

	#Expose the application
	kubectl --namespace petclinic-iter8 apply -f petclinic-gateway.yaml >>${LOGFILE}
	err_exit "Error: Error exposing the application"
	kubectl --namespace petclinic-iter8 get gateway,virtualservice >>${LOGFILE}
	#Check if the application is running without issues
	curl --header 'Host: petclinic.example.com' -o /dev/null -s -w "%{http_code}\n" "http://${GATEWAY_URL}/owners" >>${LOGFILE}
}

function install_kruize() {
	echo "==========================================================="
	echo "Cloning and deploying kruize..."
	echo "==========================================================="
	#git clone git@github.com:kruize/kruize.git >>${LOGFILE}
	#pushd kruize
	#./deploy.sh -c minikube >>${LOGFILE}
	#popd

	#Expose kruize
	KRUIZE_POD=`kubectl get pods -n monitoring | grep kruize | tr -s " " | cut -d " " -f1` 
	kubectl port-forward -n monitoring $KRUIZE_POD 31313:31313 >>${LOGFILE} & 
	err_exit "Error: Error exposing the kruize application"

	echo "Use http://localhost:31313/recommendations to look for recommedations"
}
function deploy_iter8_dashboard() {
	echo "==========================================================="
	echo "Deploying iter8 dashboard..."
	echo "==========================================================="
	kubectl -n istio-system port-forward $(kubectl -n istio-system get pod -l app=grafana -o jsonpath='{.items[0].metadata.name}') 3000:3000 >>${LOGFILE} &
	curl -L -s https://raw.githubusercontent.com/iter8-tools/iter8/v1.0.0-rc3/integrations/grafana/install_dashboard.sh \ >>${LOGFILE}
| /bin/bash -

	echo "Use http://localhost:3000 for iter8 dashboard"

}
function setup_jmeter() {
	echo "==========================================================="
	echo "Setting up jmeter..."
	echo "==========================================================="
	wget https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-5.3.tgz >>${LOGFILE}
	err_exit "Error: Error downloading jmeter"

	#Extract the jmeter
	tar -xzf apache-jmeter-5.3.tgz >>${LOGFILE}
}
function generate_load() {
	echo "==========================================================="
	echo "Generating the load with jmeter"
	echo "==========================================================="
	JDURATION=$1
	JUSERS=$2

	./apache-jmeter-5.3/bin/jmeter -n -t petclinic-iter8.jmx -j ${PWD}/petclinic.stats -JPETCLINIC_HOST=${INGRESS_HOST} -JPETCLINIC_PORT=${INGRESS_PORT} -Jduration=$JDURATION -Jusers=$JUSERS > jmeter.log &
}

function get_recommendations() {
	echo "==========================================================="
	echo "Getting recommendations from kruize..."
	echo "==========================================================="
	# Get recommendations for petclinic-v1
	curl http://localhost:31313/recommendations?application_name=petclinic-v1 >>${LOGFILE}
}
function prepare_petclinic_with_recomm() {
	echo "==========================================================="
	echo "Preparing another instance of petclinic with kruize recommendations..."
	echo "==========================================================="
	APP_INST=$1

	# Get request/limit cpu and mem
	REQ_MEM=`curl -s http://localhost:31313/recommendations?application_name=petclinic-v1 | grep "memory" | cut -d ":" -f2 | cut -d "," -f1 | cut -d "\"" -f2 | head -1`
	LIM_MEM=`curl -s http://localhost:31313/recommendations?application_name=petclinic-v1 | grep "memory" | cut -d ":" -f2 | cut -d "," -f1 | cut -d "\"" -f2 | tail -1`
	
	REQ_CPU=`curl -s http://localhost:31313/recommendations?application_name=petclinic-v1 | grep "cpu" | cut -d ":" -f2 | cut -d " " -f2 |  head -1`
	LIM_CPU=`curl -s http://localhost:31313/recommendations?application_name=petclinic-v1 | grep "cpu" | cut -d ":" -f2 | cut -d " " -f2 |  tail -1 `

	echo $REQ_MEM $LIM_MEM $REQ_CPU $LIM_CPU

	# Update petclinic-2 yaml
	sed 's/REQ_MEM/'${REQ_MEM}'/g' petclinic-app-resource-template.yaml > petclinic-app-${APP_INST}.yaml
	sed -i 's/REQ_CPU/'${REQ_CPU}'/g' petclinic-app-${APP_INST}.yaml
	sed -i 's/LIM_MEM/'${LIM_MEM}'/g' petclinic-app-${APP_INST}.yaml
	sed -i 's/LIM_CPU/'${LIM_CPU}'/g' petclinic-app-${APP_INST}.yaml

	#Update version name
	sed -i 's/APP_VERSION/v'$APP_INST'/g' petclinic-app-${APP_INST}.yaml
}
function deploy_petclinic_other() {
	echo "==========================================================="
	echo "Deploying another instance of petclinic..."
	echo "==========================================================="
	APP_INST=$1
	kubectl --namespace petclinic-iter8 apply -f petclinic-app-${APP_INST}.yaml >>${LOGFILE}
	err_exit "Error: Error deploying another version of petclinic"
}

function create_experiment() {
	echo "==========================================================="
	echo "Creating iter8 experiment..."
	echo "==========================================================="
	kubectl --namespace petclinic-iter8 apply -f petclinic-experiment-uniform.yaml >>${LOGFILE}
	err_exit "Error: Error creating the experiment"
}

function get_experiment_status() {
	echo "==========================================================="
	echo "Watch the experiment status..."
	echo "==========================================================="
	kubectl --namespace petclinic-iter8 get experiment --watch
}

#install_minikube
start_minikube
install_istio
install_iter8
deploy_petclinic
install_kruize

deploy_iter8_dashboard
setup_jmeter
generate_load 300 500
sleep 300
get_recommendations
prepare_petclinic_with_recomm 2
deploy_petclinic_other 2
generate_load 700 500
create_experiment

