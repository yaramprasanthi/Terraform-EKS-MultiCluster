// ✅ Slack Notification Function
def sendSlack(msg, color = "#36a64f") {
    withCredentials([string(credentialsId: 'main-branch', variable: 'SLACK_URL')]) {
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
        DEPLOYMENT_NAME = "nodeapp"
        SERVICE_NAME = "nodeapp-service"
        CONTAINER_NAME = "nodeapp"
        TF_BASE = "terraform/envs"
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

        // ✅ Checkout the repository
        stage('Checkout SCM') {
            steps { checkout scm }
        }

        // ✅ Environment setup based on branch
        stage('Set Environment Based on Branch') {
            steps {
                script {
                    if (env.BRANCH_NAME == "dev") {
                        env.WORKSPACE_ENV = "dev"
                        env.DEFAULT_CLUSTER_NAME = "eks-dev"
                        env.KUBECONFIG_PATH = "/var/lib/jenkins/.kube/eks-dev-config"

                    } else if (env.BRANCH_NAME == "staging") {
                        env.WORKSPACE_ENV = "staging"
                        env.DEFAULT_CLUSTER_NAME = "eks-staging"
                        env.KUBECONFIG_PATH = "/var/lib/jenkins/.kube/eks-staging-config"

                    } else if (env.BRANCH_NAME == "main") {
                        env.WORKSPACE_ENV = "prod"
                        env.DEFAULT_CLUSTER_NAME = "eks-prod"
                        env.KUBECONFIG_PATH = "/var/lib/jenkins/.kube/eks-prod-config"

                    } else {
                        error("❌ Unknown branch: ${env.BRANCH_NAME}")
                    }

                    // Assign final cluster name (either param or default)
                    env.CLUSTER_NAME = params.CLUSTER_NAME?.trim() ?: env.DEFAULT_CLUSTER_NAME

                    sendSlack("🔧 Environment set: `${env.WORKSPACE_ENV}` → Cluster `${env.CLUSTER_NAME}`", "#439FE0")
                }
            }
        }


        // ✅ Build the Node.js application and Docker image
        stage('Build Node App') {
            steps {
                dir('app') {
                    sh 'npm install'
                    script { docker.build("yaramprasanthi/nodeapp:${env.WORKSPACE_ENV}") }
                }
                sendSlack("📦 Node.js app built successfully for `${env.WORKSPACE_ENV}`", "#439FE0")
            }
        }

        // ✅ Push Docker image to DockerHub
        stage('Push Docker Image') {
            steps {
                script {
                    docker.withRegistry('', 'dockerhub-creds') {
                        docker.image("yaramprasanthi/nodeapp:${env.WORKSPACE_ENV}").push()
                    }
                }
                sendSlack("📤 Docker image pushed to DockerHub for `${env.WORKSPACE_ENV}`", "#439FE0")
            }
        }

        // ✅ Terraform Apply (Provision/Update Production Cluster)
        stage('Terraform Init & Apply (Create Cluster)') {
            steps {
                dir("${env.TF_BASE}/${env.WORKSPACE_ENV}") {

                    sh 'terraform init -reconfigure'
                    sh "terraform workspace select ${env.WORKSPACE_ENV} || terraform workspace new ${env.WORKSPACE_ENV}"

                    sh """
                        terraform apply -auto-approve \
                          -var='cluster_name=${env.CLUSTER_NAME}' \
                          -var='region=${env.AWS_REGION}'
                    """
                }

                sendSlack("✅ Cluster `${env.CLUSTER_NAME}` created/updated successfully via Terraform.", "#28a745")
            }
        }

        // ✅ Configure Kubeconfig
        stage('Configure kubeconfig') {
            steps {
                sh """
                    aws eks update-kubeconfig \
                        --name ${env.CLUSTER_NAME} \
                        --region ${env.AWS_REGION} \
                        --kubeconfig ${env.KUBECONFIG_PATH}
                """
                sendSlack("🔐 kubeconfig configured for `${env.CLUSTER_NAME}`", "#439FE0")
            }
        }

        // 🚦 Manual Approval before Production Deployment
        stage('Approval Before Production Deployment') {
            when { expression { env.BRANCH_NAME == "main" } }
            steps {
                script {
                    input message: "🚨 Approve deployment to PRODUCTION cluster `${env.CLUSTER_NAME}`?", ok: "Deploy Now"
                    sendSlack("✅ Production deployment approved for cluster `${env.CLUSTER_NAME}`", "#439FE0")
                }
            }
        }

        // ✅ Deploy application manifests to EKS
        stage('Deploy Node App to EKS') {
            steps {
                dir("k8s/${env.WORKSPACE_ENV}") {
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} apply -f deployment.yaml"
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} apply -f service.yaml"
                }
                sendSlack("🚀 Application deployed to production cluster `${env.CLUSTER_NAME}`", "#36a64f")
            }
        }

        // ✅ Verify deployment health and service exposure
        stage('Verify Deployment') {
            steps {
                sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get pods -o wide"
                sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get svc"
                sendSlack("✅ Deployment verification successful for `${env.CLUSTER_NAME}`", "#28a745")
            }
        }
    }

    post {
        // ✅ SUCCESS NOTIFICATION
        success {
            sendSlack("🎉 *SUCCESS* — Production deployment completed successfully for `${env.BRANCH_NAME}`", "#2eb886")
        }

        // ⚠️ FAILURE HANDLER — clean up partially created resources
        failure {
            sendSlack("❌ *FAILURE* — Production pipeline failed for `${env.BRANCH_NAME}`. Starting cleanup...", "#ff0000")

            dir("${env.TF_BASE}/${env.WORKSPACE_ENV}") {
                sh """
                    terraform init -reconfigure
                    terraform workspace select ${env.WORKSPACE_ENV} || terraform workspace new ${env.WORKSPACE_ENV}

                    terraform destroy -auto-approve \
                      -var='cluster_name=${env.CLUSTER_NAME}' \
                      -var='region=${env.AWS_REGION}'
                """
            }

            sendSlack("🧹 Cleanup completed. Partial cluster `${env.CLUSTER_NAME}` removed.", "#ff9900")
        }
    }
}
