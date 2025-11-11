pipeline {
    agent any

    parameters {
        string(name: 'REGION', defaultValue: 'ap-south-1', description: 'AWS Region')
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
                        env.WORKSPACE_ENV = 'production'
                        env.CLUSTER_NAME = 'eks-prod'
                        env.KUBECONFIG_PATH = "/var/lib/jenkins/.kube/eks-prod-config"
                    } else {
                        error("Unknown branch: ${env.BRANCH_NAME}")
                    }

                    // Versioned image tag based on Jenkins build number
                    env.IMAGE_TAG = "${env.WORKSPACE_ENV}-v${env.BUILD_NUMBER}"

                    echo "Branch: ${env.BRANCH_NAME} → Env: ${env.WORKSPACE_ENV} → Tag: ${env.IMAGE_TAG}"
                }
            }
        }

        stage('Build Node.js App') {
            steps {
                dir('app') {
                    sh 'npm install'
                }
            }
        }

        stage('Build & Push Docker Image') {
            steps {
                script {
                    docker.build("yaramprasanthi/nodeapp:${env.IMAGE_TAG}")

                    docker.withRegistry('', 'dockerhub-creds') {
                        sh "docker push yaramprasanthi/nodeapp:${env.IMAGE_TAG}"
                    }
                }
            }
        }

        stage('Terraform Init & Apply') {
            steps {
                dir("terraform/envs/${env.WORKSPACE_ENV}") {
                    sh 'terraform init -reconfigure'
                    sh "terraform workspace select ${env.WORKSPACE_ENV} || terraform workspace new ${env.WORKSPACE_ENV}"
                    sh "terraform apply -auto-approve -var='cluster_name=${env.CLUSTER_NAME}' -var='region=${env.AWS_REGION}'"
                }
            }
        }

        stage('Configure kubeconfig') {
            steps {
                sh "aws eks update-kubeconfig --name ${env.CLUSTER_NAME} --region ${env.AWS_REGION} --kubeconfig ${env.KUBECONFIG_PATH}"
            }
        }

        stage('Deploy Node App to EKS') {
            steps {
                dir("k8s/${env.WORKSPACE_ENV}") {
                    sh """
                    kubectl --kubeconfig=${env.KUBECONFIG_PATH} set image deployment/nodeapp-deployment \
                    nodeapp=yaramprasanthi/nodeapp:${env.IMAGE_TAG} --record || \
                    (kubectl --kubeconfig=${env.KUBECONFIG_PATH} apply -f deployment.yaml && \
                    kubectl --kubeconfig=${env.KUBECONFIG_PATH} apply -f service.yaml)
                    """
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                script {
                    echo "Verifying pods and services..."
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get pods -o wide"
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get svc"
                }
            }
        }
    }

    post {
        success {
            echo "✅ Successfully deployed ${env.CLUSTER_NAME} with image tag ${env.IMAGE_TAG}"
        }

        failure {
            script {
                echo "❌ Deployment failed! Rolling back or cleaning up..."

                // Manual input for rollback decision
                def userChoice = input(
                    id: 'rollbackChoice', message: 'Deployment failed! What do you want to do?',
                    parameters: [
                        choice(
                            choices: ['Rollback Last Stable Version', 'Destroy Infrastructure', 'Skip'],
                            description: 'Choose rollback or full teardown',
                            name: 'ACTION'
                        )
                    ]
                )

                if (userChoice == 'Rollback Last Stable Version') {
                    echo "Rolling back application to last stable deployment..."
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} rollout undo deployment/nodeapp-deployment || echo 'No previous revision found — rollback skipped.'"
                } else if (userChoice == 'Destroy Infrastructure') {
                    echo "Destroying infrastructure via Terraform..."
                    dir("terraform/envs/${env.WORKSPACE_ENV}") {
                        sh "terraform destroy -auto-approve"
                    }
                } else {
                    echo "Skipping rollback/destroy as per user choice."
                }
            }
        }
    }
}
