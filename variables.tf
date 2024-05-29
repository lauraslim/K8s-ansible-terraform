variable "kubeadm_demo_key" {
  type = string
description = "key pair name"
default = "kubeadm_demo_pub_key"
}

variable "kubeadm_demo_ami" {
    type = string
    default = "ami-04b70fa74e45c3917"
}

variable "worker_nodes_count" {
    type = number
    default = 2
  
}