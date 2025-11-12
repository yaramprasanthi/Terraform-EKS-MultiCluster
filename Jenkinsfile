// ✅ Slack Notification Function
def sendSlack(msg, color = "#36a64f") {
    withCredentials([string(credentialsId: 'staging-branch', variable: 'SLACK_URL')]) {
        sh """
            curl -X POST -H 'Content-type: application/json' \
            --data '{ "attachments": [ { "color": "${color}", "text": "${msg}" } ] }' \
            $SLACK_URL
        """
    }
}

// ✅ KEY FIX — declare control variable
def stopPipeline = false

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
                    } else {
                        error("Unknown branch: ${env.BRANCH_NAME}")
                    }

                    env.CLUSTER_NAME = params.CLUSTER_NAME?.trim() ?: env.DEFAULT_CLUSTER_NAME

                    echo "Branch ${env.BRANCH_NAME} → Cluster ${env.CLUSTER_NAME}, Region ${env.AWS_REGION}"

                    sendSlack("🚀 Pipeline started for *${env.BRANCH_NAME}* → Cluster `${env.CLUSTER_NAME}`", "#439FE0")
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
                            echo "Destroying existing cluster ${env.CLUSTER_NAME}..."

                            sendSlack("🛑 Destroying cluster `${env.CLUSTER_NAME}` as requested…", "#ff0000")

                            dir("terraform/envs/${env.WORKSPACE_ENV}") {
                                sh """
                                    terraform init -reconfigure
                                    terraform workspace select ${env.CLUSTER_NAME} || terraform workspace new ${env.CLUSTER_NAME}
                                    terraform destroy -auto-approve -var='cluster_name=${env.CLUSTER_NAME}' -var='region=${env.AWS_REGION}'
                                """
                            }
                        } else {
                            echo "Cluster not found → Nothing to destroy."
                            sendSlack("⚠️ Cluster `${env.CLUSTER_NAME}` not found. Nothing to destroy.", "#ffaa00")
                        }

                        echo "Cluster destroyed. Stopping pipeline."
                        sendSlack("✅ Cluster `${env.CLUSTER_NAME}` destroyed successfully. Pipeline stopping.", "#28a745")

                        stopPipeline = true
                    } else {
                        echo "Destroy not selected → Continuing deployment."
                    }
                }
            }
        }

        // ✅ All later stages run only if stopPipeline == false

        stage('Build Node App') {
            when { expression { stopPipeline == false } }
            steps {
                dir('app') {
                    sh 'npm install'
                    script { docker.build("yaramprasanthi/nodeapp:${env.WORKSPACE_ENV}") }
                }
                sendSlack("📦 Node app build completed for `${env.WORKSPACE_ENV}`", "#439FE0")
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
                sendSlack("📤 Docker image pushed for `${env.WORKSPACE_ENV}`", "#439FE0")
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
                sendSlack("✅ Terraform Apply completed. Cluster `${env.CLUSTER_NAME}` created.", "#28a745")
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
                sendSlack("🚀 Application deployed to `${env.CLUSTER_NAME}`", "#36a64f")
            }
        }

        stage('Verify Deployment') {
            when { expression { stopPipeline == false } }
            steps {
                sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get pods -o wide"
                sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get svc"
                sendSlack("✅ Deployment verification completed for `${env.CLUSTER_NAME}`", "#28a745")
            }
        }
    }

    post {
        success {
            echo "✅ Pipeline succeeded for branch ${env.BRANCH_NAME}!"
            sendSlack("🎉 *Pipeline Success:* Branch `${env.BRANCH_NAME}` completed successfully!", "#2eb886")
        }
        failure {
            echo "❌ Pipeline failed."
            sendSlack("❌ *Pipeline FAILED* for branch `${env.BRANCH_NAME}`", "#ff0000")
        }
    }
}
