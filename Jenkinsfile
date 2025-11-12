// ✅ Slack Notification Helper
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
        string(name: 'CLUSTER_NAME', defaultValue: '', description: 'EKS cluster name (leave empty to use branch default)')
        string(name: 'REGION', defaultValue: 'ap-south-1', description: 'AWS region')
    }

    environment {
        AWS_CREDENTIALS = credentials('aws-access-key')
        DOCKERHUB_CRED  = credentials('dockerhub-creds')
        DEPLOYMENT_NAME = "nodeapp"
        SERVICE_NAME    = "nodeapp-service"
        CONTAINER_NAME  = "nodeapp"
        TF_BASE         = "terraform/envs"
    }

    stages {

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
                    } else {
                        error("Unknown branch: ${env.BRANCH_NAME}")
                    }

                    env.CLUSTER_NAME  = params.CLUSTER_NAME?.trim() ?: env.DEFAULT_CLUSTER_NAME
                    env.IMAGE_NAME    = "yaramprasanthi/nodeapp:${env.WORKSPACE_ENV}-${env.BUILD_NUMBER}"
                    env.STABLE_IMAGE  = "yaramprasanthi/nodeapp:stable-${env.WORKSPACE_ENV}"

                    echo "Branch: ${env.BRANCH_NAME} → Cluster: ${env.CLUSTER_NAME}, Region: ${params.REGION}"
                    sendSlack("🔧 Environment set for `${env.BRANCH_NAME}` → Cluster `${env.CLUSTER_NAME}`", "#439FE0")
                }
            }
        }

        stage('Build Node App') {
            steps {
                dir('app') {
                    sh 'npm install'
                    script { docker.build("${env.IMAGE_NAME}") }
                }
                script {
                    sendSlack("📦 Node.js app built successfully → `${env.IMAGE_NAME}`", "#439FE0")
                }
            }
        }

        stage('Push Docker Image') {
            steps {
                script {
                    withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                        sh """
                            echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                            docker push ${env.IMAGE_NAME}
                        """
                    }
                    sendSlack("📤 Docker image pushed: `${env.IMAGE_NAME}`", "#439FE0")
                }
            }
        }

        stage('Terraform Init & Apply') {
            steps {
                dir("${TF_BASE}/${env.WORKSPACE_ENV}") {
                    sh 'terraform init -reconfigure'
                    sh "terraform workspace select ${env.WORKSPACE_ENV} || terraform workspace new ${env.WORKSPACE_ENV}"
                    sh "terraform apply -auto-approve -var='cluster_name=${env.CLUSTER_NAME}' -var='region=${params.REGION}'"
                }
                script {
                    sendSlack("✅ Terraform applied → EKS cluster `${env.CLUSTER_NAME}` created/updated", "#28a745")
                }
            }
        }

        stage('Configure kubeconfig') {
            steps {
                sh "aws eks update-kubeconfig --name ${env.CLUSTER_NAME} --region ${params.REGION} --kubeconfig ${env.KUBECONFIG_PATH}"
                script { sendSlack("🔐 Kubeconfig configured for cluster `${env.CLUSTER_NAME}`", "#439FE0") }
            }
        }

        stage('Deploy Node App to EKS') {
            steps {
                dir("k8s/${env.WORKSPACE_ENV}") {
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} apply -f deployment.yaml"
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} apply -f service.yaml"
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} set image deployment/${env.DEPLOYMENT_NAME} ${env.CONTAINER_NAME}=${env.IMAGE_NAME}"
                }
                script { sendSlack("🚀 App deployed to EKS cluster `${env.CLUSTER_NAME}`", "#36a64f") }
            }
        }

        stage('Verify Application Health') {
            steps {
                script {
                    echo "⏳ Checking rollout..."
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} rollout status deployment/${env.DEPLOYMENT_NAME} --timeout=180s"
                    echo "🌐 Fetching external IP..."
                    sh """
                        kubectl --kubeconfig=${env.KUBECONFIG_PATH} get svc ${env.SERVICE_NAME} \
                        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || \
                        kubectl --kubeconfig=${env.KUBECONFIG_PATH} get svc ${env.SERVICE_NAME} \
                        -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
                    """
                    sendSlack("🌐 App verified and running on `${env.CLUSTER_NAME}`", "#28a745")
                }
            }
        }

        stage('Tag Stable Image') {
            steps {
                script {
                    echo "🏷️ Tagging ${env.IMAGE_NAME} as stable image..."
                    withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                        sh """
                            echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                            docker pull ${env.IMAGE_NAME}
                            docker tag ${env.IMAGE_NAME} ${env.STABLE_IMAGE}
                            docker push ${env.STABLE_IMAGE}
                        """
                    }
                    sendSlack("🏷️ Tagged new stable image → `${env.STABLE_IMAGE}`", "#28a745")
                }
            }
        }
    }

    post {
        success {
            echo "✅ Deployment succeeded for ${env.WORKSPACE_ENV}!"
            sendSlack("🎉 *SUCCESS* — Deployment completed for `${env.WORKSPACE_ENV}` (`${env.IMAGE_NAME}`)", "#2eb886")
        }

        failure {
            echo "⚠️ FAILURE: Rolling back ${env.WORKSPACE_ENV}..."
            script {
                sendSlack("❌ *FAILURE* — Rolling back `${env.WORKSPACE_ENV}` to last stable image...", "#ff0000")

                sh "aws eks update-kubeconfig --name ${env.CLUSTER_NAME} --region ${params.REGION} --kubeconfig ${env.KUBECONFIG_PATH}"
                sh """
                    echo "Attempting rollback to ${env.STABLE_IMAGE}..."
                    kubectl --kubeconfig=${env.KUBECONFIG_PATH} set image deployment/${env.DEPLOYMENT_NAME} ${env.CONTAINER_NAME}=${env.STABLE_IMAGE} || echo 'Rollback failed: deployment not found'
                    kubectl --kubeconfig=${env.KUBECONFIG_PATH} rollout status deployment/${env.DEPLOYMENT_NAME} || echo 'Rollback did not complete properly'
                """
                sendSlack("✅ Rollback complete → reverted to `${env.STABLE_IMAGE}`", "#ff9900")
            }
        }
    }
}
