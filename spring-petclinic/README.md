# Using kruize and iter8 on spring-petclinic benchmark

petclinic_iter8_kruize_run.sh		Script to install and deploy minikube,istio,iter8,kruize and petclinic and run an experiment.

This script by default uses: 

* 7 cpus ; 8500MB memory

* x86_64 architecture  - required to install istio

* duration the jmeter load is run : 300 secs

* no.of users jmeter uses for load simulation : 500

Edit the script if you don't want to call any functionalities related to installing minikube,istio, iter8 etc.

# Other configuration files used:

petclinic-app.yaml :                    deploy petclinic app with no requests/limits set.

petclinic-app-resource-template.yaml :  template yaml to use with requests/limits set to use with kruize recommendations.

petclinic-experiment-uniform.yaml	:     to create an iter8 experiment - which uses Uniform strategy and split the load by 50% from start of the experiment.

petclinic-iter8.jmx :                   to drive the load using jmeter.
