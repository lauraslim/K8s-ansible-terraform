terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.5.0"
    }
    #https://registry.terraform.io/providers/hashicorp/tls/latest (this is neceesary for key pair)
    tls = {
      source = "hashicorp/tls"
      version = "4.0.5"
    }
    #go to https://registry.terraform.io/providers/ansible/ansible/latest/docs#example-usage
     ansible = {
      source = "ansible/ansible"
      version = "1.3.0"
    }
  }
}
#configure aws provider
provider "aws" {
  region = "us-east-1"
}

#custom vpc
resource "aws_vpc" "kubeadm_demo_vpc" {
  cidr_block = "192.168.0.0/24"
  enable_dns_hostnames = true

  tags = {
    # NOTE: very important to use an uppercase N to set the name in the console
    Name = "kubeadm_demo_vpc"
  } 
}
#subnets
resource "aws_subnet" "kubeadm_demo_subnet" {
  vpc_id = aws_vpc.kubeadm_demo_vpc.id
  cidr_block = "192.168.0.0/25"
  map_public_ip_on_launch = true

  tags = { 
    Name = "kubadm_demo_public_subnet"
  }
}
#internet gateway
resource "aws_internet_gateway" "kubeadm_demo_igw" {
  vpc_id = aws_vpc.kubeadm_demo_vpc.id
  tags = { 
    Name = "Kubeadm Demo Internet GW"
  }
}
#route table

resource "aws_route_table" "kubeadm_demo_routetable" {
  vpc_id = aws_vpc.kubeadm_demo_vpc.id
  route { 
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.kubeadm_demo_igw.id
  }
  tags = {
    Name = "kubeadm Demo IGW route table"
  }
}
#associate route table to subnet
resource "aws_route_table_association" "kubeadm_demo_route_association" {
  subnet_id = aws_subnet.kubeadm_demo_subnet.id
  route_table_id = aws_route_table.kubeadm_demo_routetable.id
  
}
#security group
#for common ports(ssh, https. http)
resource "aws_security_group" "kubeadm_demo_sg_common" {
    name = "kubeadm_demo_sg_common"
    vpc_id = aws_vpc.kubeadm_demo_vpc.id
tags = {
    Name= "kubeadm_demo_sg_common"
}
 ingress {
    description = "Allow SSH"
    protocol = "tcp"
    from_port = 22
    to_port = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP"
    protocol = "tcp"
    from_port = 80
    to_port = 80 
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS"
    protocol = "tcp"
    from_port = 443
    to_port = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "kubeadm_demo_sg_control_plane" {
  name = "kubeadm-control-plane security group"
  vpc_id = aws_vpc.kubeadm_demo_vpc.id
  

  ingress {
    description = "API Server"
    protocol = "tcp"
    from_port = 6443
    to_port = 6443
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kubelet API"
    protocol = "tcp"
    from_port = 2379
    to_port = 2380
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "etcd server client API"
    protocol = "tcp"
    from_port = 10250
    to_port = 10250
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kube Scheduler"
    protocol = "tcp"
    from_port = 10259
    to_port = 10259
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kube Contoller Manager"
    protocol = "tcp"
    from_port = 10257
    to_port = 10257
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { 
    Name = "Control Plane SG"
  }
  
}

resource "aws_security_group" "kubeadm_demo_sg_worker_nodes" {
  name = "kubeadm-worker-node security group"
  vpc_id = aws_vpc.kubeadm_demo_vpc.id

  ingress {
    description = "kubelet API"
    protocol = "tcp"
    from_port = 10250
    to_port = 10250
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "NodePort services"
    protocol = "tcp"
    from_port = 30000
    to_port = 32767
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { 
    Name = "Worker Nodes SG"
  }
  
}
#ports that allow communication between the nodes
resource "aws_security_group" "kubeadm_demo_sg_flannel" {
  name = "flannel-overlay-backend"
  vpc_id = aws_vpc.kubeadm_demo_vpc.id
  tags = {
    Name = "Flannel Overlay backend"
  }

  ingress {
    description = "flannel overlay backend"
    protocol = "udp"
    from_port = 8285
    to_port = 8285
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "flannel vxlan backend"
    protocol = "udp"
    from_port = 8472
    to_port =  8472
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#private key creation
resource "tls_private_key" "kubeadm_demo_pri_key" {
  algorithm = "RSA"
  rsa_bits  = 4096

 provisioner "local-exec" { 
    command = "echo '${self.public_key_pem}' > ./pubkey.pem"
  }
  provisioner "local-exec" {
    command = "echo chmod 400 private_key.pem"
  }
}
  #now we need to store our private key in our local machine ans this will help us to access the machine we created through ssh. therefore, we will create a local file resource in which we will store our private key.go local_file | Resources | hashicorp/local
resource "local_file" "pri-key-pair" {
  content = tls_private_key.kubeadm_demo_pri_key.private_key_pem
  filename = "pri-keypair_pem"
}


#this is the public key creation, we need part of private key to create pub key
resource "aws_key_pair" "kubeadm_demo_pub_key" {
  key_name = var.kubeadm_demo_key
  public_key = tls_private_key.kubeadm_demo_pri_key.public_key_openssh

  provisioner "local-exec" { # Create a "myKey.pem" to your computer!!
    command = "echo '${tls_private_key.kubeadm_demo_pri_key.private_key_pem}' > ./private-key.pem"
  } 
}

# ec2 for the resources
#control_plane instance
resource "aws_instance" "kubeadm_demo_control_plane" {
  ami = var.kubeadm_demo_ami
  instance_type = "t2.medium"
  key_name = aws_key_pair.kubeadm_demo_pub_key.key_name
  associate_public_ip_address = true
  subnet_id = aws_subnet.kubeadm_demo_subnet.id
  vpc_security_group_ids = [ aws_security_group.kubeadm_demo_sg_common.id,
  aws_security_group.kubeadm_demo_sg_control_plane.id,
  aws_security_group.kubeadm_demo_sg_flannel.id, ]
  
  root_block_device {
    volume_type = "gp2"
    volume_size = 14
  }

  tags = {
    Name = "Kubeadm Master"
    Role = "control_plane"
  }
  #go in your working directory and create a folder called files, then..
  provisioner "local-exec" {
    command = "echo 'master ${self.public_ip}' >> ./files/hosts"
  }
}

#worker-nodes instance
resource "aws_instance" "kubeadm_demo_worker_nodes" {
  count = var.worker_nodes_count
  ami = var.kubeadm_demo_ami
  instance_type = "t2.micro"
  key_name = aws_key_pair.kubeadm_demo_pub_key.key_name
  associate_public_ip_address = true
  subnet_id = aws_subnet.kubeadm_demo_subnet.id
  vpc_security_group_ids = [ aws_security_group.kubeadm_demo_sg_common.id,
  aws_security_group.kubeadm_demo_sg_worker_nodes.id,
  aws_security_group.kubeadm_demo_sg_flannel.id, ]

  root_block_device {
    volume_type = "gp2"
    volume_size = 8
  }

  tags = {
    Name = "Kubeadm Worker ${count.index}"
    Role = "worker_nodes"
  }

  provisioner "local-exec" {
    command = "echo 'worker-${count.index} ${self.public_ip}' >> ./files/hosts"
  }
  
}
#create a file call inventory.yml in your working directory, the go to https://www.ansible.com/blog/providing-terraform-with-that-ansible-magic/ and copy the plugin : plugin: cloud.terraform.terraform_provider and paste it in your inventory file.

#then go to https://galaxy.ansible.com/ui/repo/published/cloud/terraform/ and copy the installation cmd:ansible-galaxy collection install cloud.terraform and paste it in your working directory and run it

# ansible hosts to configure our instances
resource "ansible_host" "kubadm_demo_control_plane_host" {
  depends_on = [
    aws_instance.kubeadm_demo_control_plane
  ]
  #this name should match some data that we will put in our playbook
  name = "control_plane"
  groups = ["master"]
  variables = {
    ansible_user = "ubuntu"
    ansible_host = aws_instance.kubeadm_demo_control_plane.public_ip
    ansible_ssh_private_key_file = "./pri-keypair_pem"
    #the node_hostname should match the name in the hosts file
    node_hostname = "master"
  }
}
resource "ansible_host" "kubadm_demo_worker_nodes_host" {
  depends_on = [
    aws_instance.kubeadm_demo_worker_nodes
  ]
  count = var.worker_nodes_count
  name = "worker-${count.index}"
  groups = ["workers"]
  variables = {
    node_hostname = "worker-${count.index}"
    ansible_user = "ubuntu"
    ansible_host = aws_instance.kubeadm_demo_worker_nodes[count.index].public_ip
    ansible_ssh_private_key_file = "./pri-keypair_pem"
  }
}
#now if we run ansible-inventory -i inventory.yml --graph, we will get the goups name the we created in our ansible-hosts.(master and workers)

