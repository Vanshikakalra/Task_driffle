# Provider
provider "aws" {
  region = "us-east-1"  
}

# VPC
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"  

  tags = {
    Name = "my-vpc"
  }
}

# ECR repo
resource "aws_ecr_repository" "my_ecr_repo" {
  name = "my-ecr-repo"

  tags = {
    Name = "my-ecr-repo"
  }
}

# EC2 Sg 
resource "aws_security_group" "my_sg" {
  name        = "my-security-group"
  description = "Allow SSH and HTTP inbound traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "my-security-group"
  }
}

# EC2 
resource "aws_instance" "my_ec2_instance" {
  ami           = "ami-0c94855ba95c71c99"  
  instance_type = "t2.micro"  
  vpc_security_group_ids = [aws_security_group.my_sg.id]
  key_name      = "my-keypair"  

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y jenkins git docker.io",
      "sudo usermod -aG docker ${USER}",
      "sudo su - ${USER}",
      "git clone https://github.com/your-repo.git"  # URL of repo you want to clone
    ]
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"  
    private_key = file("~/path-to-pem-file/my-keypair.pem")  
    host        = self.public_ip
  }

  tags = {
    Name = "my-ec2-instance"
  }
}

# ELB
resource "aws_elb" "my_elb" {
  name               = "my-elb"
  security_groups    = [aws_security_group.my_sg.id]
  availability_zones = ["us-east-1a", "us-east-1b"]  

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }

  instances = [aws_instance.my_ec2_instance.id]

  tags = {
    Name = "my-elb"
  }
}

# Adding Dockerfile and Jenkinsfile 
resource "null_resource" "add_files_and_push" {
  triggers = {
    instance_id = aws_instance.my_ec2_instance.id
  }

  provisioner "local-exec" {
    command = <<EOT
      cd directory-where-repo-is-cloned  
      echo 'FROM adoptopenjdk:11-jdk-hotspot
      WORKDIR /app
      COPY build/libs/project.jar /app/project.jar
      EXPOSE 9000
      CMD ["java", "-jar", "project.jar"]' > Dockerfile
      
      echo '''pipeline {
        agent any
        
        stages {
          stage('Build Docker Image') {
            steps {
              script {
                // Build Docker image
                docker.build('my-java-app')
              }
            }
          }
          
          stage('Push to ECR') {
            steps {
              script {
                // Authenticate with ECR
                withCredentials([string(credentialsId: 'aws-credentials', variable: 'AWS_ACCESS_KEY_ID'),
                                 string(credentialsId: 'aws-credentials', variable: 'AWS_SECRET_ACCESS_KEY')]) {
                  sh 'aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <your-account-id>.dkr.ecr.us-east-1.amazonaws.com'
                }
                
                // Tag the Docker image
                docker.image('my-java-app').tag("<your-account-id>.dkr.ecr.us-east-1.amazonaws.com/my-ecr-repo:latest")
                
                // Push the Docker image to ECR
                docker.image('my-java-app').push("<your-account-id>.dkr.ecr.us-east-1.amazonaws.com/my-ecr-repo:latest")
              }
            }
          }
          
          stage('Run Container on EC2') {
            steps {
              script {
                sshagent(["my-ssh-credentials"]) {
                  sh 'ssh -o StrictHostKeyChecking=no -i ~/path-to-pem-file/my-keypair.pem ubuntu@${aws_instance.my_ec2_instance.public_ip} "docker stop my-container || true && docker rm my-container || true"'
                  sh 'ssh -o StrictHostKeyChecking=no -i ~/path-to-pem-file/my-keypair.pem ubuntu@${aws_instance.my_ec2_instance.public_ip} "docker run -d -p 9000:9000 --name my-container <your-account-id>.dkr.ecr.us-east-1.amazonaws.com/my-ecr-repo:latest"'
                }
              }
            }
          }
          
          stage('Attach ELB') {
            steps {
              script {
                withCredentials([string(credentialsId: 'aws-credentials', variable: 'AWS_ACCESS_KEY_ID'),
                                 string(credentialsId: 'aws-credentials', variable: 'AWS_SECRET_ACCESS_KEY')]) {
                  def elbDnsName = sh(
                    returnStdout: true,
                    script: 'aws elbv2 describe-load-balancers --region us-east-1 --query "LoadBalancers[?LoadBalancerName==\'my-elb\'].DNSName" --output text'
                  ).trim()
  
                  sh 'aws elbv2 register-targets --region us-east-1 --target-group-arn ${aws_elb.my_elb.arn} --targets Id=$(aws ec2 describe-instances --region us-east-1 --filters Name=tag:Name,Values=my-ec2-instance --query "Reservations[].Instances[].InstanceId" --output text)'
                  sh "sed -i 's|ELB_DNS_NAME|${elbDnsName}|g' user-data.txt"
                  sh 'aws ec2 create-tags --region us-east-1 --resources $(aws ec2 describe-instances --region us-east-1 --filters Name=tag:Name,Values=my-ec2-instance --query "Reservations[].Instances[].InstanceId" --output text) --tags Key=user-data,Value="$(cat user-data.txt)"'
                }
              }
            }
          }
        }
      }''' > Jenkinsfile
      
      git add .
      git commit -m "Add Dockerfile and Jenkinsfile"
      git push
    EOT
  }
}
