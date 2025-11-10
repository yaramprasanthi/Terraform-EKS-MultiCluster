pipeline {
    agent any

    parameters {
        string(name: 'REGION', defaultValue: 'ap-south-1', description: 'AWS region for EKS cluster')
    }

    environment {
        // Jenkins credentials (stored under "Manage Jenkins" → "Credentials")
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

                    echo """
                    🌿 Branch: ${env.BRANCH_NAME}
                    🏗️  Environment: ${env.WORKSPACE_ENV}
                    ☁️  Cluster: ${env.CLUSTER_NAME}
                    🌎 Region: ${env.AWS_REGION}
                    """
                }
            }
        }

        stage('Check Cluster Status') {
            steps {
                script {
                    def status = sh(
                        script: """
                            AWS_ACCESS_KEY_ID=${AWS_CREDENTIALS_USR} \
                            AWS_SECRET_ACCESS_KEY=${AWS_CREDENTIALS_PSW} \
                            aws eks describe-cluster --name ${env.CLUSTER_NAME} \
                            --region ${env.AWS_REGION} \
                            --query cluster.status --output text 2>/dev/null || echo NOT_FOUND
                        """,
                        returnStdout: true
                    ).trim()

                    if (status == 'NOT_FOUND') {
                        echo "❌ Cluster ${env.CLUSTER_NAME} not found — creating new one."
                    } else {
                        echo "✅ Cluster ${env.CLUSTER_NAME} exists with status: ${status}"
                    }
                }
            }
        }

        stage('Build Node App') {
            steps {
                dir('app') {
                    sh 'npm install'
                    script {
                        docker.build("yaramprasanthi/nodeapp:${env.CLUSTER_NAME}")
                    }
                }
            }
        }

        stage('Push Docker Image') {
            steps {
                script {
                    docker.withRegistry('', 'dockerhub-creds') {
                        docker.image("yaramprasanthi/nodeapp:${env.CLUSTER_NAME}").push()
                    }
                }
            }
        }

        stage('Terraform Init & Workspace') {
            steps {
                dir("terraform/envs/${env.WORKSPACE_ENV}") {
                    withEnv(["AWS_ACCESS_KEY_ID=${AWS_CREDENTIALS_USR}",
                             "AWS_SECRET_ACCESS_KEY=${AWS_CREDENTIALS_PSW}"]) {
                        sh 'terraform init -reconfigure'
                        sh "terraform workspace select ${env.WORKSPACE_ENV} || terraform workspace new ${env.WORKSPACE_ENV}"
                    }
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                dir("terraform/envs/${env.WORKSPACE_ENV}") {
                    withEnv(["AWS_ACCESS_KEY_ID=${AWS_CREDENTIALS_USR}",
                             "AWS_SECRET_ACCESS_KEY=${AWS_CREDENTIALS_PSW}"]) {
                        sh """
                            terraform apply -auto-approve \
                                -var='cluster_name=${env.CLUSTER_NAME}' \
                                -var='region=${env.AWS_REGION}'
                        """
                    }
                }
            }
        }

        stage('Configure kubeconfig') {
            steps {
                script {
                    withEnv(["AWS_ACCESS_KEY_ID=${AWS_CREDENTIALS_USR}",
                             "AWS_SECRET_ACCESS_KEY=${AWS_CREDENTIALS_PSW}"]) {
                        sh """
                            mkdir -p /var/lib/jenkins/.kube
                            aws eks update-kubeconfig \
                                --name ${env.CLUSTER_NAME} \
                                --region ${env.AWS_REGION} \
                                --kubeconfig ${env.KUBECONFIG_PATH}
                        """
                    }
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
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get pods -o wide"
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get svc"
                }
            }
        }
    }

    post {
        success {
            echo "✅ Pipeline succeeded for branch ${env.BRANCH_NAME}!"
        }
        failure {
            echo "❌ Pipeline failed for branch ${env.BRANCH_NAME}! Triggering rollback..."
            dir("terraform/envs/${env.WORKSPACE_ENV}") {
                script {
                    withEnv(["AWS_ACCESS_KEY_ID=${AWS_CREDENTIALS_USR}",
                             "AWS_SECRET_ACCESS_KEY=${AWS_CREDENTIALS_PSW}"]) {
                        sh "terraform destroy -auto-approve || echo '⚠️ Rollback failed; manual intervention required.'"
                    }
                }
            }
        }
    }
}
