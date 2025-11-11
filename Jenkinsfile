def stopPipeline = false   // <-- KEY FIX

pipeline {
    agent any

    parameters {
        string(name: 'CLUSTER_NAME', defaultValue: '', description: 'Enter EKS cluster name')
        string(name: 'REGION', defaultValue: 'ap-south-1', description: 'Enter AWS region')
        choice(name: 'DESTROY_CONFIRMATION', choices: ['no', 'yes'], description: 'Destroy cluster?')
    }

    environment {
        AWS_CREDENTIALS = credentials('aws-access-key')
        AWS_REGION = "${params.REGION}"
        DOCKERHUB_CRED = credentials('dockerhub-creds')
    }

    stages {

        stage('Checkout SCM') {
            steps { checkout scm }
        }

        stage('Set Environment Based on Branch') {
            steps {
                script {
                    if ("${env.BRANCH_NAME}" == "dev") {
                        env.WORKSPACE_ENV = 'dev'
                        env.DEFAULT_CLUSTER_NAME = 'eks-dev'
                        env.KUBECONFIG_PATH = "/var/lib/jenkins/.kube/eks-dev-config"
                    } else if ("${env.BRANCH_NAME}" == "staging") {
                        env.WORKSPACE_ENV = 'staging'
                        env.DEFAULT_CLUSTER_NAME = 'eks-staging'
                        env.KUBECONFIG_PATH = "/var/lib/jenkins/.kube/eks-staging-config"
                    } else if ("${env.BRANCH_NAME}" == "main") {
                        env.WORKSPACE_ENV = 'prod'
                        env.DEFAULT_CLUSTER_NAME = 'eks-prod'
                        env.KUBECONFIG_PATH = "/var/lib/jenkins/.kube/eks-prod-config"
                    }

                    env.CLUSTER_NAME = params.CLUSTER_NAME?.trim() ?: env.DEFAULT_CLUSTER_NAME

                    echo "Branch: ${env.BRANCH_NAME}"
                    echo "Environment: ${env.WORKSPACE_ENV}"
                    echo "Cluster Name: ${env.CLUSTER_NAME}"
                    echo "AWS Region: ${env.AWS_REGION}"
                }
            }
        }

        stage('Check & Destroy Cluster (Optional)') {
            steps {
                script {
                    def status = sh(
                        script: "aws eks describe-cluster --name ${env.CLUSTER_NAME} --region ${env.AWS_REGION} --query cluster.status --output text || echo NOT_FOUND",
                        returnStdout: true
                    ).trim()

                    if (params.DESTROY_CONFIRMATION == 'yes') {

                        if (status != 'NOT_FOUND') {
                            echo "Cluster exists → Destroying ${env.CLUSTER_NAME}"

                            dir("terraform/envs/${env.WORKSPACE_ENV}") {
                                sh """
                                    terraform init -reconfigure
                                    terraform workspace select ${env.CLUSTER_NAME} || terraform workspace new ${env.CLUSTER_NAME}
                                    terraform destroy -auto-approve -var='cluster_name=${env.CLUSTER_NAME}' -var='region=${env.AWS_REGION}'
                                """
                            }
                        } else {
                            echo "Cluster not found → Nothing to destroy."
                        }

                        echo "Cluster destroyed. Stopping pipeline."
                        stopPipeline = true            // <-- KEY FIX
                    } else {
                        echo "Destroy not selected → Continue deployment."
                    }
                }
            }
        }

        stage('Build Node App') {
            when { expression { stopPipeline == false } }
            steps {
                dir('app') {
                    sh 'npm install'
                    script {
                        docker.build("yaramprasanthi/nodeapp:${env.WORKSPACE_ENV}")
                    }
                }
            }
        }

        stage('Push Docker Image') {
            when { expression { stopPipeline == false } }
            steps {
                script {
                    docker.withRegistry('', 'dockerhub-creds') {
                        docker.image("yaramprasanthi/nodeapp:${env.WORKSPACE_ENV}").push()
                    }
                }
            }
        }

        stage('Terraform Init & Apply') {
            when { expression { stopPipeline == false } }
            steps {
                dir("terraform/envs/${env.WORKSPACE_ENV}") {
                    sh 'terraform init -reconfigure'
                    sh "terraform workspace select ${env.CLUSTER_NAME} || terraform workspace new ${env.CLUSTER_NAME}"
                    sh "terraform apply -auto-approve -var='cluster_name=${env.CLUSTER_NAME}' -var='region=${env.AWS_REGION}'"
                }
            }
        }

        stage('Configure kubeconfig') {
            when { expression { stopPipeline == false } }
            steps {
                sh "aws eks update-kubeconfig --name ${env.CLUSTER_NAME} --region ${env.AWS_REGION} --kubeconfig ${env.KUBECONFIG_PATH}"
            }
        }

        stage('Deploy Node App to EKS') {
            when { expression { stopPipeline == false } }
            steps {
                dir("k8s/${env.WORKSPACE_ENV}") {
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} apply -f deployment.yaml"
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} apply -f service.yaml"
                }
            }
        }

        stage('Verify Deployment') {
            when { expression { stopPipeline == false } }
            steps {
                sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get pods -o wide"
                sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get svc"
            }
        }
    }

    post {
        success { echo "✅ Pipeline completed successfully!" }
        failure { echo "❌ Pipeline failed!" }
    }
}
