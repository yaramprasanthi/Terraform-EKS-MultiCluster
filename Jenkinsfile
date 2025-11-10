pipeline {
    agent any

    environment {
        AWS_CREDENTIALS = credentials('aws-access-key')
        // Auto-detect branch environment
        BRANCH_ENV = "${BRANCH_NAME == 'main' ? 'prod' : (BRANCH_NAME == 'staging' ? 'staging' : 'dev')}"
        CLUSTER_NAME = "eks-${BRANCH_ENV}"
        TERRAFORM_WORKSPACE = "${BRANCH_ENV}"
        KUBECONFIG_PATH = "/var/lib/jenkins/.kube/${CLUSTER_NAME}-config"
        TERRAFORM_DIR = "terraform"
        K8S_NAMESPACE = "${BRANCH_ENV}"
    }

    parameters {
        choice(name: 'DESTROY_CONFIRMATION', choices: ['no', 'yes'], description: 'Confirm destroy if cluster exists')
    }

    stages {

        stage('Checkout SCM') {
            steps { checkout scm }
        }

        stage('Check Cluster Status') {
            steps {
                echo "🔍 Checking if cluster ${CLUSTER_NAME} exists in AWS..."
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-access-key']]) {
                    script {
                        def check = sh(
                            script: "aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.status' --output text 2>/dev/null || echo 'NOT_FOUND'",
                            returnStdout: true
                        ).trim()
                        env.CLUSTER_EXISTS = (check != 'NOT_FOUND') ? "true" : "false"
                        echo env.CLUSTER_EXISTS == 'true' ? "🧨 Cluster exists (status: ${check})" : "✨ Cluster not found — will create a new one."
                    }
                }
            }
        }

        stage('User Confirmation to Destroy') {
            when { expression { env.CLUSTER_EXISTS == 'true' } }
            steps {
                script {
                    if (params.DESTROY_CONFIRMATION == 'yes') {
                        echo "⚠️ User confirmed destroy for cluster ${CLUSTER_NAME}"
                        env.ACTION = "destroy"
                    } else {
                        echo "🚫 Destroy not confirmed — aborting pipeline."
                        currentBuild.result = 'ABORTED'
                        error("Pipeline stopped: Destroy not confirmed for ${CLUSTER_NAME}")
                    }
                }
            }
        }

        stage('Build Node App') {
            when { expression { env.CLUSTER_EXISTS == 'false' } }
            steps {
                dir('app') {
                    echo "📦 Building Node.js app for branch ${BRANCH_NAME}..."
                    sh """
                        npm install
                        docker build -t yaramprasanthi/nodeapp:${BRANCH_NAME} .
                    """
                }
            }
        }

        stage('Push Docker Image') {
            when { expression { env.CLUSTER_EXISTS == 'false' } }
            steps {
                echo "🚀 Pushing Docker image..."
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                    sh """
                        echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin
                        docker push yaramprasanthi/nodeapp:${BRANCH_NAME}
                    """
                }
            }
        }

        stage('Terraform Init & Workspace') {
            steps {
                dir("${TERRAFORM_DIR}") {
                    echo "🧱 Initializing Terraform in ${TERRAFORM_DIR}..."
                    sh "terraform init -reconfigure"
                    sh "terraform workspace new ${TERRAFORM_WORKSPACE} || true"
                    sh "terraform workspace select ${TERRAFORM_WORKSPACE}"
                }
            }
        }

        stage('Terraform Apply/Destroy') {
            steps {
                dir("${TERRAFORM_DIR}") {
                    withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-access-key']]) {
                        script {
                            if (env.ACTION == "destroy") {
                                echo "🔥 Destroying EKS cluster: ${CLUSTER_NAME}"
                                sh "terraform destroy -auto-approve -var=cluster_name=${CLUSTER_NAME} -var=region=${AWS_REGION}"
                            } else if (env.CLUSTER_EXISTS == "false") {
                                echo "🚀 Creating EKS cluster: ${CLUSTER_NAME}"
                                sh "terraform apply -auto-approve -var=cluster_name=${CLUSTER_NAME} -var=region=${AWS_REGION}"
                            } else {
                                echo "✅ No Terraform action required."
                            }
                        }
                    }
                }
            }
        }

        stage('Configure kubeconfig') {
            when { expression { env.CLUSTER_EXISTS == 'false' } }
            steps {
                echo "⚙️ Configuring kubeconfig for ${CLUSTER_NAME}..."
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-access-key']]) {
                    sh """
                        mkdir -p \$(dirname ${KUBECONFIG_PATH})
                        aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME} --kubeconfig ${KUBECONFIG_PATH}
                        kubectl create namespace ${K8S_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
                    """
                }
            }
        }

        stage('Deploy Node App to EKS') {
            when { expression { env.CLUSTER_EXISTS == 'false' } }
            steps {
                dir('k8s') {
                    echo "📤 Deploying app to ${K8S_NAMESPACE} namespace..."
                    sh """
                        kubectl apply -f deployment.yaml --namespace ${K8S_NAMESPACE} --kubeconfig ${KUBECONFIG_PATH}
                        kubectl apply -f service.yaml --namespace ${K8S_NAMESPACE} --kubeconfig ${KUBECONFIG_PATH}
                        DEPLOY_NAME=\$(kubectl get deploy -n ${K8S_NAMESPACE} -o jsonpath="{.items[0].metadata.name}" --kubeconfig ${KUBECONFIG_PATH})
                        kubectl rollout status deployment/\$DEPLOY_NAME --namespace ${K8S_NAMESPACE} --timeout=180s --kubeconfig ${KUBECONFIG_PATH}
                    """
                }
            }
        }

        stage('Verify Deployment') {
            when { expression { env.CLUSTER_EXISTS == 'false' } }
            steps {
                sh """
                    kubectl get pods -n ${K8S_NAMESPACE} --kubeconfig ${KUBECONFIG_PATH}
                    kubectl get svc -n ${K8S_NAMESPACE} --kubeconfig ${KUBECONFIG_PATH}
                """
            }
        }

    }

    post {
        success {
            echo "✅ Pipeline completed for branch ${BRANCH_NAME} (env: ${BRANCH_ENV})!"
        }
        failure {
            echo "❌ Pipeline failed for branch ${BRANCH_NAME}!"
        }
        aborted {
            echo "⚠️ Pipeline aborted by user."
        }
    }
}
