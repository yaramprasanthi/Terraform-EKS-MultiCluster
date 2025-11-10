pipeline {
    agent any

    parameters {
        string(name: 'CLUSTER_NAME', defaultValue: '', description: 'Enter EKS cluster name (optional)')
        string(name: 'REGION', defaultValue: '', description: 'Enter AWS region (optional)')
        choice(name: 'DESTROY_CONFIRMATION', choices: ['no', 'yes'], description: 'If cluster exists, do you want to destroy it?')
    }

    environment {
        AWS_CREDENTIALS = credentials('aws-access-key')
        KUBECONFIG_BASE = "/var/lib/jenkins/.kube"
        DOCKER_IMAGE = "yaramprasanthi/nodeapp"
    }

    stages {
        stage('Set Environment Based on Branch') {
            steps {
                script {
                    if (env.BRANCH_NAME == 'dev') {
                        env.CLUSTER_NAME = params.CLUSTER_NAME ?: "eks-dev"
                        env.AWS_REGION = params.REGION ?: "ap-south-1"
                        env.TF_WORKSPACE = "dev"
                    } else if (env.BRANCH_NAME == 'staging') {
                        env.CLUSTER_NAME = params.CLUSTER_NAME ?: "eks-staging"
                        env.AWS_REGION = params.REGION ?: "ap-south-1"
                        env.TF_WORKSPACE = "staging"
                    } else if (env.BRANCH_NAME == 'main') {
                        env.CLUSTER_NAME = params.CLUSTER_NAME ?: "eks-prod"
                        env.AWS_REGION = params.REGION ?: "ap-south-1"
                        env.TF_WORKSPACE = "prod"
                    } else {
                        error("Branch ${env.BRANCH_NAME} is not mapped to an environment")
                    }

                    env.KUBECONFIG_PATH = "${env.KUBECONFIG_BASE}/${env.CLUSTER_NAME}-config"

                    echo "🌎 Branch ${env.BRANCH_NAME} → Cluster ${env.CLUSTER_NAME}, Region ${env.AWS_REGION}, Workspace ${env.TF_WORKSPACE}"
                }
            }
        }

        stage('Check Cluster Status') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-access-key']]) {
                    script {
                        def check = sh(
                            script: """aws eks describe-cluster \
                                --name ${env.CLUSTER_NAME} \
                                --region ${env.AWS_REGION} \
                                --query 'cluster.status' --output text 2>/dev/null || echo 'NOT_FOUND'""",
                            returnStdout: true
                        ).trim()

                        if (check != 'NOT_FOUND') {
                            echo "🧨 Cluster ${env.CLUSTER_NAME} already exists (status: ${check})"
                            env.CLUSTER_EXISTS = "true"
                        } else {
                            echo "✨ Cluster ${env.CLUSTER_NAME} not found — will create a new one."
                            env.CLUSTER_EXISTS = "false"
                        }
                    }
                }
            }
        }

        stage('User Confirmation to Destroy') {
            when { expression { env.CLUSTER_EXISTS == 'true' } }
            steps {
                script {
                    if (params.DESTROY_CONFIRMATION == 'yes') {
                        echo "⚠️ User confirmed destroy for cluster ${env.CLUSTER_NAME}"
                        env.ACTION = "destroy"
                    } else {
                        echo "🚫 Destroy not confirmed — skipping destroy. Aborting pipeline."
                        currentBuild.result = 'ABORTED'
                        error("Pipeline stopped: Destroy not confirmed for ${env.CLUSTER_NAME}")
                    }
                }
            }
        }

        stage('Build Node App') {
            when { expression { env.CLUSTER_EXISTS == 'false' } }
            steps {
                echo "📦 Building Node.js Application..."
                dir('app') {
                    sh '''
                        npm install
                        docker build -t ${DOCKER_IMAGE}:${CLUSTER_NAME} .
                    '''
                }
            }
        }

        stage('Push Docker Image') {
            when { expression { env.CLUSTER_EXISTS == 'false' } }
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                    sh '''
                        echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin
                        docker push ${DOCKER_IMAGE}:${CLUSTER_NAME}
                    '''
                }
            }
        }

        stage('Terraform Init & Workspace') {
            steps {
                script {
                    dir("terraform") {
                        sh 'rm -rf .terraform'
                        sh 'terraform init -reconfigure'

                        // Create/select workspace
                        sh "terraform workspace select ${env.TF_WORKSPACE} || terraform workspace new ${env.TF_WORKSPACE}"
                    }
                }
            }
        }

        stage('Terraform Apply/Destroy') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-access-key']]) {
                    script {
                        dir("terraform") {
                            if (env.ACTION == "destroy") {
                                echo "🔥 Destroying EKS cluster: ${env.CLUSTER_NAME}"
                                sh """
                                    terraform destroy -auto-approve \
                                        -var=cluster_name=${env.CLUSTER_NAME} \
                                        -var=region=${env.AWS_REGION}
                                """
                            } else if (env.CLUSTER_EXISTS == "false") {
                                echo "🚀 Applying Terraform to create EKS cluster: ${env.CLUSTER_NAME}"
                                sh """
                                    terraform apply -auto-approve \
                                        -var=cluster_name=${env.CLUSTER_NAME} \
                                        -var=region=${env.AWS_REGION}
                                """
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
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-access-key']]) {
                    sh """
                        mkdir -p \$(dirname ${env.KUBECONFIG_PATH})
                        aws eks update-kubeconfig --region ${env.AWS_REGION} --name ${env.CLUSTER_NAME} --kubeconfig ${env.KUBECONFIG_PATH}
                        kubectl get nodes --kubeconfig ${env.KUBECONFIG_PATH}
                    """
                }
            }
        }

        stage('Deploy Node App to EKS') {
            when { expression { env.CLUSTER_EXISTS == 'false' } }
            steps {
                dir('k8s') {
                    sh """
                        kubectl apply -f deployment.yaml --kubeconfig ${env.KUBECONFIG_PATH}
                        kubectl apply -f service.yaml --kubeconfig ${env.KUBECONFIG_PATH}
                        DEPLOY_NAME=\$(kubectl get deploy -o jsonpath="{.items[0].metadata.name}" --kubeconfig ${env.KUBECONFIG_PATH})
                        kubectl rollout status deployment/\$DEPLOY_NAME --timeout=180s --kubeconfig ${env.KUBECONFIG_PATH}
                    """
                }
            }
        }

        stage('Verify Deployment') {
            when { expression { env.CLUSTER_EXISTS == 'false' } }
            steps {
                sh """
                    kubectl get pods -o wide --kubeconfig ${env.KUBECONFIG_PATH}
                    kubectl get svc --kubeconfig ${env.KUBECONFIG_PATH}
                """
            }
        }

        stage('Force Cleanup') {
            when { expression { env.ACTION == 'destroy' } }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-access-key']]) {
                    sh """
                        set +e
                        VPC_ID=\$(aws ec2 describe-vpcs --region ${env.AWS_REGION} --filters "Name=tag:Name,Values=${env.CLUSTER_NAME}-vpc" --query "Vpcs[0].VpcId" --output text 2>/dev/null)
                        if [ "\$VPC_ID" != "None" ] && [ "\$VPC_ID" != "" ]; then
                            for IGW in \$(aws ec2 describe-internet-gateways --region ${env.AWS_REGION} --filters "Name=attachment.vpc-id,Values=\$VPC_ID" --query "InternetGateways[].InternetGatewayId" --output text); do
                                aws ec2 detach-internet-gateway --internet-gateway-id \$IGW --vpc-id \$VPC_ID --region ${env.AWS_REGION}
                                aws ec2 delete-internet-gateway --internet-gateway-id \$IGW --region ${env.AWS_REGION}
                            done
                            for SUBNET in \$(aws ec2 describe-subnets --region ${env.AWS_REGION} --filters "Name=vpc-id,Values=\$VPC_ID" --query "Subnets[].SubnetId" --output text); do
                                aws ec2 delete-subnet --subnet-id \$SUBNET --region ${env.AWS_REGION}
                            done
                            aws ec2 delete-vpc --vpc-id \$VPC_ID --region ${env.AWS_REGION}
                        fi
                    """
                }
            }
        }
    }

    post {
        success {
            script {
                if (env.ACTION == 'destroy') {
                    echo "✅ Successfully destroyed EKS cluster ${env.CLUSTER_NAME}!"
                } else if (env.CLUSTER_EXISTS == 'false') {
                    echo "✅ EKS Cluster ${env.CLUSTER_NAME} created successfully and app deployed!"
                } else {
                    echo "✅ No action performed."
                }
            }
        }
        failure {
            echo "❌ Pipeline failed for ${env.CLUSTER_NAME}!"
        }
        aborted {
            echo "⚠️ Pipeline aborted by user (no destroy confirmation)."
        }
    }
}
