pipeline {
    agent any

    parameters {
        string(name: 'CLUSTER_NAME', defaultValue: 'EKS', description: 'Enter EKS cluster name')
        string(name: 'REGION', defaultValue: 'ap-south-1', description: 'Enter AWS region')
        choice(name: 'DESTROY_CONFIRMATION', choices: ['no', 'yes'], description: 'If cluster exists, do you want to destroy it before running pipeline?')
    }

    environment {
        AWS_CREDENTIALS = credentials('aws-access-key')
        AWS_REGION = "${params.REGION}"
        DOCKERHUB_CRED = credentials('dockerhub-creds')
    }

    stages {

        stage('Checkout SCM') {
            steps {
                checkout scm
            }
        }

        stage('Set Environment Based on Branch') {
            steps {
                script {
                    if ("${env.BRANCH_NAME}" == "dev") {
                        env.WORKSPACE_ENV = 'dev'
                        env.CLUSTER_NAME = 'eks-dev'
                        env.KUBECONFIG_PATH = "/var/lib/jenkins/.kube/eks-dev-config"
                    } else if ("${env.BRANCH_NAME}" == "staging") {
                        env.WORKSPACE_ENV = 'staging'
                        env.CLUSTER_NAME = 'eks-staging'
                        env.KUBECONFIG_PATH = "/var/lib/jenkins/.kube/eks-staging-config"
                    } else if ("${env.BRANCH_NAME}" == "main") {
                        env.WORKSPACE_ENV = 'prod'
                        env.CLUSTER_NAME = 'eks-prod'
                        env.KUBECONFIG_PATH = "/var/lib/jenkins/.kube/eks-prod-config"
                    } else {
                        error("Unknown branch: ${env.BRANCH_NAME}")
                    }

                    echo "Branch ${env.BRANCH_NAME} → Cluster ${env.CLUSTER_NAME}, Region ${env.AWS_REGION}"
                }
            }
        }

        stage('Check Cluster Status') {
            steps {
                script {
                    def status = sh(
                        script: "aws eks describe-cluster --name ${env.CLUSTER_NAME} --region ${env.AWS_REGION} --query cluster.status --output text || echo NOT_FOUND",
                        returnStdout: true
                    ).trim()

                    if (status == 'NOT_FOUND') {
                        echo "✅ Cluster ${env.CLUSTER_NAME} not found — will create a new one."
                    } else {
                        echo "⚠️ Cluster ${env.CLUSTER_NAME} exists with status: ${status}"

                        // Handle manual destroy option
                        if (params.DESTROY_CONFIRMATION == 'yes') {
                            echo "User opted to destroy existing cluster before redeploy..."
                            dir("terraform/envs/${env.WORKSPACE_ENV}") {
                                sh """
                                terraform init -reconfigure
                                terraform destroy -auto-approve -var='cluster_name=${env.CLUSTER_NAME}' -var='region=${env.AWS_REGION}'
                                """
                            }
                        } else {
                            echo "Keeping existing cluster as per user choice (DESTROY_CONFIRMATION=no)"
                        }
                    }
                }
            }
        }

        stage('Build Node App') {
            steps {
                dir('app') {
                    sh 'npm install'
                    script {
                        def tag = env.WORKSPACE_ENV
                        docker.build("yaramprasanthi/nodeapp:${tag}")
                    }
                }
            }
        }

        stage('Push Docker Image') {
            steps {
                script {
                    def tag = env.WORKSPACE_ENV
                    docker.withRegistry('', 'dockerhub-creds') {
                        docker.image("yaramprasanthi/nodeapp:${tag}").push()
                    }
                }
            }
        }

        stage('Terraform Init & Apply') {
            steps {
                dir("terraform/envs/${env.WORKSPACE_ENV}") {
                    sh """
                    terraform init -reconfigure
                    terraform workspace select ${env.WORKSPACE_ENV} || terraform workspace new ${env.WORKSPACE_ENV}
                    terraform apply -auto-approve -var='cluster_name=${env.CLUSTER_NAME}' -var='region=${env.AWS_REGION}'
                    """
                }
            }
        }

        stage('Configure kubeconfig') {
            steps {
                script {
                    sh "aws eks update-kubeconfig --name ${env.CLUSTER_NAME} --region ${env.AWS_REGION} --kubeconfig ${env.KUBECONFIG_PATH}"
                }
            }
        }

        stage('Deploy Node App to EKS') {
            steps {
                dir("k8s/${env.WORKSPACE_ENV}") {
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} apply -f deployment.yaml"
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} apply -f service.yaml"
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                script {
                    echo "Verifying deployment in ${env.WORKSPACE_ENV} environment..."
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get pods -o wide"
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get svc"
                }
            }
        }
    }

    post {
        success {
            echo "✅ Pipeline succeeded for ${env.WORKSPACE_ENV} (${env.BRANCH_NAME})!"
        }

        failure {
            echo "❌ Pipeline failed! Initiating rollback cleanup..."
            dir("terraform/envs/${env.WORKSPACE_ENV}") {
                sh """
                terraform init -reconfigure
                terraform destroy -auto-approve -var='cluster_name=${env.CLUSTER_NAME}' -var='region=${env.AWS_REGION}' || echo 'Rollback cleanup failed but continuing...'
                """
            }
        }

        always {
            echo "📋 Pipeline finished for ${env.BRANCH_NAME}"
        }
    }
}
