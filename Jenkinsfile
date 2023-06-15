pipeline {
  agent any

  stages {
    stage("Build Docker Image") {
      steps {
        script {
          // Build Docker image
          docker.build('my-java-app')
        }
      }
    }

    stage("Push to ECR") {
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

    stage("Run Container on EC2") {
      steps {
        script {
          sshagent(["my-ssh-credentials"]) {
            sh 'ssh -o StrictHostKeyChecking=no -i ~/path-to-pem-file/my-keypair.pem ubuntu@${aws_instance.my_ec2_instance.public_ip} "docker stop my-container || true && docker rm my-container || true"'
            sh 'ssh -o StrictHostKeyChecking=no -i ~/path-to-pem-file/my-keypair.pem ubuntu@${aws_instance.my_ec2_instance.public_ip} "docker run -d -p 9000:9000 --name my-container <your-account-id>.dkr.ecr.us-east-1.amazonaws.com/my-ecr-repo:latest"'
          }
        }
      }
    }

    stage("Attach ELB") {
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
            sh 'aws ec2 modify-instance-attribute --region us-east-1 --instance-id $(aws ec2 describe-instances --region us-east-1 --filters Name=tag:Name,Values=my-ec2-instance --query "Reservations[].Instances[].InstanceId" --output text) --user-data file://user-data.txt'
            sh 'aws ec2 reboot-instances --region us-east-1 --instance-ids $(aws ec2 describe-instances --region us-east-1 --filters Name=tag:Name,Values=my-ec2-instance --query "Reservations[].Instances[].InstanceId" --output text)'
          }
        }
      }
    }
  }
}
