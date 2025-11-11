// ✅ Slack Notification Function
def sendSlack(msg, color = "#36a64f") {
    withCredentials([string(credentialsId: 'slack-webhook', variable: 'SLACK_URL')]) {
        sh """
            curl -X POST -H 'Content-type: application/json' \
            --data '{ "attachments": [ { "color": "${color}", "text": "${msg}" } ] }' \
            $SLACK_URL
        """
    }
}

pipeline {
    agent any

    parameters {
        string(name: 'CLUSTER_NAME', defaultValue: '', description: 'Enter EKS cluster name (optional)')
        string(name: 'REGION', defaultValue: 'ap-south-1', description: 'Enter AWS region')
    }

    environment {
        AWS_CREDENTIALS = credentials('aws-access-key')
        AWS_REGION = "${params.REGION}"
        DOCKERHUB_CRED = credentials('dockerhub-creds')
    }

    stages {

        // ✅ Pipeline Start Notification
        stage('Start Notification') {
            steps {
                script {
                    sendSlack("🚀 *Pipeline Started* for branch `${env.BRANCH_NAME}`", "#439FE0")
                }
            }
        }

        stage('Checkout SCM') {
            steps { checkout scm }
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

                    sendSlack("🔧 Environment set: `${env.WORKSPACE_ENV}` → Cluster `${env.CLUSTER_NAME}`", "#439FE0")
                }
            }
        }

        stage('Build Node App') {
            steps {
                dir('app') {
                    sh 'npm install'
                    script { docker.build("yaramprasanthi/nodeapp:${env.WORKSPACE_ENV}") }
                }
                sendSlack("📦 Node app build completed for `${env.WORKSPACE_ENV}`", "#439FE0")
            }
        }

        stage('Push Docker Image') {
            steps {
                script {
                    docker.withRegistry('', 'dockerhub-creds') {
                        docker.image("yaramprasanthi/nodeapp:${env.WORKSPACE_ENV}").push()
                    }
                }
                sendSlack("📤 Docker image pushed for `${env.WORKSPACE_ENV}`", "#439FE0")
            }
        }

        // ✅ Create Cluster Only (NO destroy logic)
        stage('Terraform Init & Apply (Create Cluster)') {
            steps {
                dir("terraform/envs/${env.WORKSPACE_ENV}") {
                    sh 'terraform init -reconfigure'
                    sh "terraform workspace select ${env.CLUSTER_NAME} || terraform workspace new ${env.CLUSTER_NAME}"
                    sh """
                        terraform apply -auto-approve \
                        -var='cluster_name=${env.CLUSTER_NAME}' \
                        -var='region=${env.AWS_REGION}'
                    """
                }
                sendSlack("✅ Cluster `${env.CLUSTER_NAME}` created successfully!", "#28a745")
            }
        }

        stage('Configure kubeconfig') {
            steps {
                sh """
                    aws eks update-kubeconfig \
                    --name ${env.CLUSTER_NAME} \
                    --region ${env.AWS_REGION} \
                    --kubeconfig ${env.KUBECONFIG_PATH}
                """
            }
        }

        stage('Deploy Node App to EKS') {
            steps {
                dir("k8s/${env.WORKSPACE_ENV}") {
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} apply -f deployment.yaml"
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} apply -f service.yaml"
                }
                sendSlack("🚀 Application deployed to cluster `${env.CLUSTER_NAME}`", "#36a64f")
            }
        }

        stage('Verify Deployment') {
            steps {
                sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get pods -o wide"
                sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get svc"
                sendSlack("✅ Deployment verified for cluster `${env.CLUSTER_NAME}`", "#28a745")
            }
        }
    }

    post {
        success {
            sendSlack("🎉 *Pipeline Success* for `${env.BRANCH_NAME}`", "#2eb886")
        }

        failure {
            sendSlack("❌ *Pipeline FAILED* for `${env.BRANCH_NAME}` — starting cleanup…", "#ff0000")

            // ✅ Cleanup partial cluster ONLY on failure
            dir("terraform/envs/${env.WORKSPACE_ENV}") {
                sh """
                    terraform init -reconfigure
                    terraform workspace select ${env.CLUSTER_NAME} || terraform workspace new ${env.CLUSTER_NAME}
                    
                    terraform destroy -auto-approve \
                      -var='cluster_name=${env.CLUSTER_NAME}' \
                      -var='region=${env.AWS_REGION}' \
                      || echo 'No resources to destroy'
                """
            }

            sendSlack("🧹 Cleanup completed. Partial cluster `${env.CLUSTER_NAME}` removed.", "#ff9900")
        }
    }
}
