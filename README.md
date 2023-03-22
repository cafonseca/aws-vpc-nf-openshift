# aws-vpc-nf-openshift <!-- omit from toc -->

The terraform in this repo creates an AWS VPC with public, private, and firewall subnets for use with the  [OpenShift IPI installer](https://github.com/openshift/installer).  The AWS Network Firewall provides improved protection and improved logging for compliance.

See the [Terraform Getting Started](https://developer.hashicorp.com/terraform/tutorials/aws-get-started) for more information on Terraform.


![High-level architecture](/images/aws-vpc-openshift.png)

* 1 Internet Gateway that provides access to the internet
* 1 or more Public subnets in each availability zone
* 1 or more Private subnets in each availability zone
* 1 or more Firewall subnets in each availability zone
* 1 or more public NAT gateway in each availability zone
* VPC flow logs
* 1 AWS Network Firewall with base stateless and stateful rules for the allowed networks only.
* Network Firewall logs to Cloudwatch
* Default VPC Security group
* Security group for only the allowed networks
* Route table configurations for all the subnets
* s3, ec2, and elasticloadbalancing service endpoints

All traffic in/out flows through the AWS Network Firewall.  The firewall is configured to only allow external connections from allowed networks.

#### Table of contents
- [Requirements](#requirements)
- [Create the VPC for the modified OpenShift IPI installer](#create-the-vpc-for-the-modified-openshift-ipi-installer)
  - [Create the VPC](#create-the-vpc)
  - [Install OpenShift](#install-openshift)
- [Create the VPC for the original OpenShift IPI installer](#create-the-vpc-for-the-original-openshift-ipi-installer)
  - [Create the VPC](#create-the-vpc-1)
  - [Install OpenShift](#install-openshift-1)
  - [Update VPC](#update-vpc)


## Requirements

* AWS Account with IAM Admin role
* AWS Route 53 hosted zone

See the [OpenShift Container Platform - Installing a cluster on AWS into an existing VPC](https://docs.openshift.com/container-platform/4.12/installing/installing_aws/installing-aws-vpc.html) document for a complete list of requirements.

1. Fork this repository and then clone the forked repo to your system
2. Switch to the cloned directory on your system

Before creating the VPC update the ```main.tf``` line 25 to match the AWS account profile name in your ~/.aws/config file. See the [limits in AWS](https://github.com/openshift/installer/blob/master/docs/user/aws/limits.md). You may need to open up a support case with AWS to increase the limits. Pick a region with atleast 3 availability zones.

1. Update ```variables.tf``` file line 16 to the region you selected
2. Update ```variables.tf``` file line 22 to include the external networks allowed to connect. These can include the IP ranges from your company campus internet egress.
3. Update ```variables.tf``` file line 51 to list the availability zones for the region you selected

## Create the VPC for the modified OpenShift IPI installer

Changes to the original 4.12 installer were made in order to detect the private/public subnets.  The original IPI looks for the Internet Gateway in the route tables to determine which are the public subnets.  In this VPC, the Internet Gateway routes are not associated with the public subnets.  The modified IPI installer also looks for public NAT gateways in the subnets if it doesn't find the Internet Gateway routes for the public subnets.  See [https://github.com/cafonseca/openshift-installer/tree/release-4.12](https://github.com/cafonseca/openshift-installer/tree/release-4.12) to build the modified IPI installer.


### Create the VPC

1. ```terraform init```
2. ```terraform apply``` Give the name of the VPC, the owner email and then type yes to create the VPC.  You can also do ```terraform apply -var vpc_name=test-east-vpc -var owner=john-doe@gmail.com```

### Install OpenShift

You can refer to the [Installing OpenShift on existing VPC in AWS](https://docs.openshift.com/container-platform/4.12/installing/installing_aws/installing-aws-vpc.html) documentation for detailed information. See [https://github.com/cafonseca/openshift-installer/tree/release-4.12](https://github.com/cafonseca/openshift-installer/tree/release-4.12) to build the modified IPI installer.

The ```install-config.yaml``` file is an example without the pull secret and ssh key.  You will need to update the region, availability zones, add your ssh key, and the pull secret in the following steps.

1. Copy the installer to the cloned directory on your system.
2. Remove the install directory if it already exists ```rm -rf aws-cluster-install-dir```
3. Create the install-config. yaml file ```./openshift-install create install-config --dir aws-cluster-install-dir``` 
4. Update the ```aws-cluster-install-dir/install-config.yaml``` file using the install-config.yaml as an example.  You will need to update the region, availability zones, subnet ids, etc...
5. Copy the ```aws-cluster-install-dir/install-config.yaml``` to another location because the installation program will delete it from the install directory.
6. Create the cluster ```./openshift-install create cluster --dir aws-cluster-install-dir --log-level=info```


## Create the VPC for the original OpenShift IPI installer

The OpenShift IPI installer checks that an Internet Gateway is in the route table for the public subnets but in this VPC, the public subnets are routed to the AWS Network firewall so IPI doesn't work.  To get around this, we can add the Internet Gateway to the public subnets routing table temporally.  Then after the IPI installs the cluster, we can update the routing so everything goes through the firewall.

### Create the VPC

1. In the ```main.tf``` file, comment out line 451 ```# vpc_endpoint_id = element(local.vpc_endpoint_ids[*], count.index)```
2. In the ```main.tf``` file, uncomment line 452 ```gateway_id    = aws_internet_gateway.gw.id```
3. In the ```main.tf``` file, comment out lines 482-485
4. ```terraform init```
5. ```terraform apply``` Give the name of the VPC, the owner email and then type yes to create the VPC.  You can also do ```terraform apply -var vpc_name=test-east-vpc -var owner=john-doe@gmail.com```

### Install OpenShift

You can refer to the [Installing OpenShift on existing VPC in AWS](https://docs.openshift.com/container-platform/4.12/installing/installing_aws/installing-aws-vpc.html) documentation for detailed information. You need to obtain IPI installer for your OS.  You can download here: [installer](https://console.redhat.com/openshift/downloads). You can also download the installers and clients from the [ocp mirrors](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/).

The ```install-config.yaml``` file is an example without the pull secret and ssh key.  You will need to update the region, availability zones, add your ssh key, and the pull secret in the following steps.

1. Copy the installer to the cloned directory on your system.
2. Remove the install directory if it already exists ```rm -rf aws-cluster-install-dir```
3. Create the install-config. yaml file ```./openshift-install create install-config --dir aws-cluster-install-dir``` 
4. Update the ```aws-cluster-install-dir/install-config.yaml``` file using the install-config.yaml as an example.  You will need to update the region, availability zones, subnet ids, etc...
5. Copy the ```aws-cluster-install-dir/install-config.yaml``` to another location because the installation program will delete it from the install directory.
6. Create the cluster ```./openshift-install create cluster --dir aws-cluster-install-dir --log-level=info```

### Update VPC

The following steps updates the VPC routing tables so that everything flows through the AWS Network Firewall.

1. In the ```main.tf``` file, Uncomment line 451 ```vpc_endpoint_id = element(local.vpc_endpoint_ids[*], count.index)```
2. In the ```main.tf``` file, comment out line 452 ```# gateway_id    = aws_internet_gateway.gw.id```
3. In the ```main.tf``` file, Uncomment lines 482-485
4. ```terraform apply``` Give the name of the VPC, the owner email and then type yes to create the VPC.  You can also do ```terraform apply -var vpc_name=test-east-vpc -var owner=john-doe@gmail.com```
   

