pipeline {
    agent any

    parameters {
        string(name: 'CLUSTER_NAME', defaultValue: '', description: 'Enter EKS cluster name (leave empty to use branch default)')
        string(name: 'REGION', defaultValue: 'ap-south-1', description: 'Enter AWS region')
        choice(name: 'DESTROY_CONFIRMATION', choices: ['no', 'yes'], description: 'Destroy cluster if exists before deployment?')
    }

    environment {
        AWS_CREDENTIALS = credentials('aws-access-key')
        AWS_REGION = "${params.REGION}"
        DOCKERHUB_CRED = credentials('dockerhub-creds')

        // flag for stopping pipeline after destroy
        STOP_AFTER_DESTROY = 'false'
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
                    if (env.BRANCH_NAME == "dev") {
                        env.WORKSPACE_ENV = 'dev'
                        env.DEFAULT_CLUSTER_NAME = 'eks-dev'
                        env.KUBECONFIG_PATH = "/var/lib/jenkins/.kube/eks-dev-config"
                    } else if (env.BRANCH_NAME == "staging") {
                        env.WORKSPACE_ENV = 'staging'
                        env.DEFAULT_CLUSTER_NAME = 'eks-staging'
                        env.KUBECONFIG_PATH = "/var/lib/jenkins/.kube/eks-staging-config"
                    } else if (env.BRANCH_NAME == "main") {
                        env.WORKSPACE_ENV = 'prod'
                        env.DEFAULT_CLUSTER_NAME = 'eks-prod'
                        env.KUBECONFIG_PATH = "/var/lib/jenkins/.kube/eks-prod-config"
                    } else {
                        error("Unknown branch: ${env.BRANCH_NAME}")
                    }

                    env.CLUSTER_NAME = params.CLUSTER_NAME?.trim() ?: env.DEFAULT_CLUSTER_NAME
                    echo "Branch ${env.BRANCH_NAME} → Cluster ${env.CLUSTER_NAME}, Region ${env.AWS_REGION}"
                }
            }
        }

        stage('Check & Destroy Cluster (Optional)') {
            steps {
                script {
                    def status = sh(
                        script: """
                            aws eks describe-cluster \
                            --name ${env.CLUSTER_NAME} \
                            --region ${env.AWS_REGION} \
                            --query cluster.status --output text 2>/dev/null || echo NOT_FOUND
                        """,
                        returnStdout: true
                    ).trim()

                    if (status != 'NOT_FOUND' && params.DESTROY_CONFIRMATION == 'yes') {

                        echo "Destroying existing cluster ${env.CLUSTER_NAME} ..."

                        dir("terraform/envs/${env.WORKSPACE_ENV}") {
                            sh """
                                terraform init -reconfigure
                                terraform workspace select ${env.WORKSPACE_ENV} || terraform workspace new ${env.WORKSPACE_ENV}
                                terraform destroy -auto-approve \
                                  -var='cluster_name=${env.CLUSTER_NAME}' \
                                  -var='region=${env.AWS_REGION}'
                            """
                        }

                        echo "Cluster destroyed. Stopping pipeline."
                        env.STOP_AFTER_DESTROY = 'true'
                    }
                }
            }
        }

        stage('Build Node App') {
            when { expression { env.STOP_AFTER_DESTROY != 'true' } }
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
            when { expression { env.STOP_AFTER_DESTROY != 'true' } }
            steps {
                script {
                    docker.withRegistry('', 'dockerhub-creds') {
                        docker.image("yaramprasanthi/nodeapp:${env.WORKSPACE_ENV}").push()
                    }
                }
            }
        }

        stage('Terraform Init & Apply') {
            when { expression { env.STOP_AFTER_DESTROY != 'true' } }
            steps {
                dir("terraform/envs/${env.WORKSPACE_ENV}") {
                    sh """
                        terraform init -reconfigure
                        terraform workspace select ${env.WORKSPACE_ENV} || terraform workspace new ${env.WORKSPACE_ENV}
                        terraform apply -auto-approve \
                          -var='cluster_name=${env.CLUSTER_NAME}' \
                          -var='region=${env.AWS_REGION}'
                    """
                }
            }
        }

        stage('Configure kubeconfig') {
            when { expression { env.STOP_AFTER_DESTROY != 'true' } }
            steps {
                sh "aws eks update-kubeconfig --name ${env.CLUSTER_NAME} --region ${env.AWS_REGION} --kubeconfig ${env.KUBECONFIG_PATH}"
            }
        }

        stage('Deploy Node App to EKS') {
            when { expression { env.STOP_AFTER_DESTROY != 'true' } }
            steps {
                dir("k8s/${env.WORKSPACE_ENV}") {
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} apply -f deployment.yaml"
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} apply -f service.yaml"
                }
            }
        }

        stage('Verify Deployment') {
            when { expression { env.STOP_AFTER_DESTROY != 'true' } }
            steps {
                sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get pods -o wide"
                sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get svc"
            }
        }

    }  // END stages

    post {
        success {
            script {
                if (env.STOP_AFTER_DESTROY == 'true') {
                    echo "✅ Cluster destroyed successfully."
                } else {
                    echo "✅ Deployment completed successfully."
                }
            }
        }

        failure {
            echo "❌ Pipeline failed!"
        }
    }
}
