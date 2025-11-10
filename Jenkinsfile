pipeline {
  agent any
  environment { AWS_REGION = 'ap-south-1' }

  stages {
    stage('Checkout') {
      steps {
        git branch: "${BRANCH_NAME}", url: 'https://github.com/yaramprasanthi/Terraform-EKS-MultiClusters.git', credentialsId: 'git-creds'
      }
    }
    stage('Terraform Init') {
      steps { sh "cd terraform/envs/${BRANCH_NAME} && terraform init" }
    }
    stage('Terraform Plan') {
      steps { sh "cd terraform/envs/${BRANCH_NAME} && terraform plan -out=tfplan" }
    }
    stage('Terraform Apply') {
      steps { sh "cd terraform/envs/${BRANCH_NAME} && terraform apply -auto-approve tfplan" }
    }
    stage('Deploy App to EKS') {
      steps {
        sh "kubectl apply -f k8s/${BRANCH_NAME}/deployment.yaml"
        sh "kubectl apply -f k8s/${BRANCH_NAME}/service.yaml"
      }
    }
  }
  post {
    failure {
      steps {
        echo "Rollback triggered!"
        sh "cd terraform/envs/${BRANCH_NAME} && terraform destroy -auto-approve"
      }
    }
  }
}

