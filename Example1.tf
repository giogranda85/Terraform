##################################################################################
# VARIABLES
##################################################################################

variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "private_key_path" {}
variable "key_name" {
  default = "Giovanni"
}
variable "network_address" {
	default = "10.2.0.0/16"
}
variable "subnet1_address" {
	default = "10.2.0.0/24"
}
variable "subnet2_address" {
	default = "10.2.1.0/24"
}

##################################################################################
# PROVIDERS
##################################################################################

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "us-east-2"
}

##################################################################################
# DATA
##################################################################################
#This section is to pull data from provider about the environment

#The following line will query AWS to name all the avaialability zones then dump them into an array for reference. They can later be references by specified the array and the element number. 
data "aws_availability_zones" "available" {}

##################################################################################
# AWS RESOURCES - Subnet, route, load balancer, security policy, VPC
##################################################################################

##### Creating a basic security group in the default VPC of an ec2 instance availability zone
#
#resource "aws_security_group" "SSH-HTTP" {
#	name = "Allow SSH and HTTP"
#      	description = "Default Group for Web and SSH access"
#      	ingress {
#        	from_port = 80
#        	to_port = 80
#        	protocol = "tcp"
#        	cidr_blocks = ["0.0.0.0/0"]
#      		}
#      	ingress {
#        	from_port = 22
#        	to_port = 22
#        	protocol = "tcp"
#        	cidr_blocks = ["0.0.0.0/0"]
#      		}		    
#      	egress {
#        	from_port = 0
#        	to_port = 0
#        	protocol = "-1"
#        	cidr_blocks = ["0.0.0.0/0"]
#      		}
#    	}


#### Creating dedicated VPC

resource "aws_vpc" "vpc_gio" {
	cidr_block = "${var.network_address}"
	enable_dns_hostnames = "true"
}

#### setting external GW for VPC

resource "aws_internet_gateway" "igw_gio" {
	vpc_id = "${aws_vpc.vpc_gio.id}"
}


#### creating the subnets within the VPC

resource "aws_subnet" "subnet1_gio" {
	cidr_block	=	"${var.subnet1_address}"
	vpc_id		=	"${aws_vpc.vpc_gio.id}"
	map_public_ip_on_launch	=	"true"
	availability_zone	=	"${data.aws_availability_zones.available.names[0]}"
}


resource "aws_subnet" "subnet2_gio" {
	cidr_block	=	"${var.subnet2_address}"
	vpc_id		=	"${aws_vpc.vpc_gio.id}"
	map_public_ip_on_launch	=	"true"
	availability_zone	=	"${data.aws_availability_zones.available.names[1]}"
}

#### creating the routing table for the VPC and specifying the external GW. 
resource "aws_route_table" "rtb_gio" {
	vpc_id = "${aws_vpc.vpc_gio.id}"

	route {
		cidr_block = "0.0.0.0/0"
		gateway_id = "${aws_internet_gateway.igw_gio.id}"
	}
}

#### associating the routing table with the two subnets defined in the VPC
resource "aws_route_table_association" "rta-subnet1" {
	subnet_id	=	"${aws_subnet.subnet1_gio.id}"
	route_table_id 	=	"${aws_route_table.rtb_gio.id}"
}

resource "aws_route_table_association" "rta-subnet2" {
	subnet_id	=	"${aws_subnet.subnet2_gio.id}"
	route_table_id 	=	"${aws_route_table.rtb_gio.id}"
}


#### Creating a security group within a specific VPC

### We will be creating two different security groups, one for internal traffic and the second for external. When mounting the security policies, one will be directly associated with the ec2 instance while the other will be associated witht he load balance. The purpose of this is to restrict external traffic from hitting the node directly without going through the load balancer. 

### Internal security group which is only allowing traffic from its own subnet to connect to the node. 

resource "aws_security_group" "SSH-HTTP" {
	name = "Allow SSH and HTTP"
	vpc_id	=	"${aws_vpc.vpc_gio.id}"
      	description = "Default Group for Web and SSH access"

	ingress {
        	from_port = 80
        	to_port = 80
        	protocol = "tcp"
        	cidr_blocks = ["${var.network_address}"]
      		}
      	ingress {
        	from_port = 22
        	to_port = 22
        	protocol = "tcp"
        	cidr_blocks = ["0.0.0.0/0"]
      		}		    
      	egress {
        	from_port = 0
        	to_port = 0
        	protocol = "-1"
        	cidr_blocks = ["0.0.0.0/0"]
      		}
    	}

#### External security group which will be associated with LB

resource "aws_security_group" "elb_gio" {
	name	=	"Load_Balancer_SG"
	vpc_id	=	"${aws_vpc.vpc_gio.id}"

#allow from any incoming address to hit port 80
	ingress {
        	from_port = 80
        	to_port = 80
        	protocol = "tcp"
        	cidr_blocks = ["0.0.0.0/0"]
      		}

#allow all outbound traffic

	egress {
        	from_port = 0
        	to_port = 0
        	protocol = "-1"
        	cidr_blocks = ["0.0.0.0/0"]
      		}
    	}


### Creating a Load Balancer

resource "aws_elb" "lb_gio" {
	name = "gioelb"
	subnets	=	["${aws_subnet.subnet1_gio.id}","${aws_subnet.subnet2_gio.id}"]
	security_groups = ["${aws_security_group.elb_gio.id}"]
	instances	= ["${aws_instance.nginx-gio.id}","${aws_instance.nginx-gio2.id}"]
	
	listener {
		instance_port	= 80
		instance_protocol = "http"
		lb_port	=	80
		lb_protocol	= "http"
	}
}


#### Defining first ec2 instance and specifying the security group and vpc/subnet it should reside on:

resource "aws_instance" "nginx-gio" {
	ami           = "ami-0520e698dd500b1d1"
  	instance_type = "t2.micro"
	subnet_id 	= "${aws_subnet.subnet1_gio.id}"
	vpc_security_group_ids	=	["${aws_security_group.SSH-HTTP.id}"]
  	key_name        = "${var.key_name}"
		

#  	connection {
#    		user        = "ec2-user"
#  		private_key = "${file(var.private_key_path)}"

#security_groups = ["${aws_security_group.SSH-HTTP.name}"]

  	tags = {
    		name = "Gio-deployed-by-terra"
  	}

	provisioner "remote-exec" {
	
	inline = [
			"sudo yum install nginx -y",
			"sudo systemctl start nginx",
      			"echo '<html><head><title>Blue Team Server</title></head><body style=\"background-color:#1F778D\"><p style=\"text-align: center;\"><span style=\"color:#FFFFFF;\"><span style=\"font-size:28px;\">Blue Team</span></span></p></body></html>' | sudo tee /usr/share/nginx/html/index.html"
			]			

  	connection {
    		host	= "${aws_instance.nginx-gio.public_dns}"
		type	= "ssh"
		user        = "ec2-user"
  		private_key = "${file(var.private_key_path)}"

		}	
	
	}
}


#### Defining second ec2 instance and specifying the security group and vpc/subnet it should reside on:

resource "aws_instance" "nginx-gio2" {
	ami           = "ami-0520e698dd500b1d1"
  	instance_type = "t2.micro"
	subnet_id 	= "${aws_subnet.subnet2_gio.id}"
	vpc_security_group_ids	=	["${aws_security_group.SSH-HTTP.id}"]
  	key_name        = "${var.key_name}"
		

#security_groups = ["${aws_security_group.SSH-HTTP.name}"]
#
#  	tags = {
#    		name = "Gio-deployed-by-terra"
#  	}
#
	provisioner "remote-exec" {
	
	inline = [
			"sudo yum install nginx -y",
			"sudo systemctl start nginx",
      			"echo '<html><head><title>Green Team Server</title></head><body style=\"background-color:#228B22\"><p style=\"text-align: center;\"><span style=\"color:#FFFFFF;\"><span style=\"font-size:28px;\">Green Team</span></span></p></body></html>' | sudo tee /usr/share/nginx/html/index.html"
			]			

  	connection {
    		host	= "${aws_instance.nginx-gio2.public_dns}"
		type	= "ssh"
		user        = "ec2-user"
  		private_key = "${file(var.private_key_path)}"

		}	
	
	}

}

##################################################################################
# OUTPUT
##################################################################################

#dumping the DNS name for single instances which was specified above
output "aws_instance_public_dns" {
    value = ["${aws_instance.nginx-gio.public_dns}","${aws_instance.nginx-gio2.public_dns}"]
}

output "aws_elb_public_dns" {
	value = "${aws_elb.lb_gio.dns_name}"
}

output "aws_availability_zones" {
	value = "${data.aws_availability_zones.available.names[0]}"
}
