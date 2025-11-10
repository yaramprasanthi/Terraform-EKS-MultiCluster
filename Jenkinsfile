pipeline {
    agent any

    environment {
        // AWS credentials stored in Jenkins (replace with your credential IDs)
        AWS_CREDENTIALS = credentials('aws-access-key')

        TERRAFORM_WORKSPACE   = '' // will be set per branch
        ENV_FOLDER            = '' // will be set per branch
    }

    options {
        // Keep only last 10 builds
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
    }

    stages {

        stage('Set Environment') {
            steps {
                script {
                    if (env.BRANCH_NAME == 'dev') {
                        ENV_FOLDER = 'terraform/envs/dev'
                        TERRAFORM_WORKSPACE = 'dev'
                    } else if (env.BRANCH_NAME == 'staging') {
                        ENV_FOLDER = 'terraform/envs/staging'
                        TERRAFORM_WORKSPACE = 'staging'
                    } else if (env.BRANCH_NAME == 'main') {
                        ENV_FOLDER = 'terraform/envs/production'
                        TERRAFORM_WORKSPACE = 'prod'
                    } else {
                        error("Branch ${env.BRANCH_NAME} is not configured for deployment")
                    }
                    echo "Deploying branch '${env.BRANCH_NAME}' to environment '${ENV_FOLDER}'"
                }
            }
        }

        stage('Terraform Init') {
            steps {
                dir("${ENV_FOLDER}") {
                    sh '''
                        terraform init -input=false
                        terraform workspace new ${TERRAFORM_WORKSPACE} || terraform workspace select ${TERRAFORM_WORKSPACE}
                    '''
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                dir("${ENV_FOLDER}") {
                    sh 'terraform plan -out=tfplan -input=false'
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                dir("${ENV_FOLDER}") {
                    sh 'terraform apply -auto-approve tfplan'
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    def imageTag = "${env.BRANCH_NAME}-nodeapp:latest"
                    sh """
                        docker build -t ${imageTag} app/
                        docker tag ${imageTag} yaramprasanthi/${imageTag}
                        echo "${DOCKERHUB_PASSWORD}" | docker login -u "yaramprasanthi" --password-stdin
                        docker push yaramprasanthi/${imageTag}
                    """
                }
            }
        }

        stage('Deploy Kubernetes') {
            steps {
                dir('k8s') {
                    script {
                        sh """
                        kubectl apply -f deployment.yaml
                        kubectl apply -f service.yaml
                        """
                    }
                }
            }
        }
    }

    post {
        success {
            echo "Deployment of branch ${env.BRANCH_NAME} completed successfully!"
        }
        failure {
            echo "Deployment failed. Consider rollback."
        }
    }
}

