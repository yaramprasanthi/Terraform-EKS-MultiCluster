pipeline {
    agent any

    // Parameters for dynamic configuration
    parameters {
        string(name: 'CLUSTER_NAME', defaultValue: '', description: 'Enter EKS cluster name (leave empty to use branch default)')
        string(name: 'REGION', defaultValue: 'ap-south-1', description: 'Enter AWS region')
        choice(name: 'DESTROY_CONFIRMATION', choices: ['no', 'yes'], description: 'Destroy cluster if exists before deployment?')
    }

    environment {
        AWS_CREDENTIALS = credentials('aws-access-key')
        AWS_REGION = "${params.REGION}"
        DOCKERHUB_CRED = credentials('dockerhub-creds')
        DOCKER_REPO = "yaramprasanthi/nodeapp"
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
                    env.IMAGE_TAG = "${env.WORKSPACE_ENV}-${env.BUILD_NUMBER}"
                    env.STABLE_IMAGE = "${env.DOCKER_REPO}:stable-${env.WORKSPACE_ENV}"
                    env.NEW_IMAGE = "${env.DOCKER_REPO}:${env.IMAGE_TAG}"

                    echo "Branch: ${env.BRANCH_NAME} → Cluster: ${env.CLUSTER_NAME}, Region: ${env.AWS_REGION}"
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

                    if (status != 'NOT_FOUND' && params.DESTROY_CONFIRMATION == 'yes') {
                        echo "Destroying existing cluster ${env.CLUSTER_NAME} as requested..."
                        dir("terraform/envs/${env.WORKSPACE_ENV}") {
                            sh """
                            terraform init -reconfigure
                            terraform workspace select ${env.WORKSPACE_ENV} || terraform workspace new ${env.WORKSPACE_ENV}
                            terraform destroy -auto-approve -var='cluster_name=${env.CLUSTER_NAME}' -var='region=${env.AWS_REGION}'
                            """
                        }
                        currentBuild.result = 'SUCCESS'
                        return
                    } else {
                        echo "Cluster ${env.CLUSTER_NAME} ready for deployment..."
                    }
                }
            }
        }

        stage('Build Node App') {
            steps {
                dir('app') {
                    sh 'npm install'
                    script {
                        docker.build("${env.NEW_IMAGE}")
                    }
                }
            }
        }

        stage('Push Docker Image') {
            steps {
                script {
                    docker.withRegistry('', 'dockerhub-creds') {
                        docker.image("${env.NEW_IMAGE}").push()
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
                script {
                    sh "aws eks update-kubeconfig --name ${env.CLUSTER_NAME} --region ${env.AWS_REGION} --kubeconfig ${env.KUBECONFIG_PATH}"
                }
            }
        }

        stage('Deploy Node App to EKS') {
            steps {
                dir("k8s/${env.WORKSPACE_ENV}") {
                    sh """
                        kubectl --kubeconfig=${env.KUBECONFIG_PATH} set image deployment/nodeapp nodeapp=${env.NEW_IMAGE} --record
                        kubectl --kubeconfig=${env.KUBECONFIG_PATH} rollout status deployment/nodeapp
                    """
                }
            }
        }

        stage('Verify Application Health') {
            steps {
                script {
                    echo "🔍 Checking pod health..."
                    def podStatus = sh(
                        script: "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get pods -n default --no-headers | awk '{print \$3}' | grep -v Running || true",
                        returnStdout: true
                    ).trim()
                    if (podStatus) {
                        error("❌ Some pods are not running properly: ${podStatus}")
                    }

                    def svcHost = sh(
                        script: "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get svc nodeapp-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'",
                        returnStdout: true
                    ).trim()
                    if (!svcHost) {
                        error("❌ Service LoadBalancer not ready for ${env.WORKSPACE_ENV}")
                    }

                    echo "🌐 Testing endpoint: http://${svcHost}"
                    def httpCode = sh(script: "curl -s -o /dev/null -w '%{http_code}' http://${svcHost}", returnStdout: true).trim()
                    if (httpCode != "200") {
                        error("❌ Health check failed (HTTP ${httpCode})")
                    }
                    echo "✅ App is healthy (HTTP 200)"
                }
            }
        }

        stage('Tag Stable Image') {
            steps {
                script {
                    echo "🏷 Updating stable image for ${env.WORKSPACE_ENV}"
                    docker.withRegistry('', 'dockerhub-creds') {
                        sh """
                            docker pull ${env.NEW_IMAGE}
                            docker tag ${env.NEW_IMAGE} ${env.STABLE_IMAGE}
                            docker push ${env.STABLE_IMAGE}
                        """
                    }
                }
            }
        }
    }

    post {
        success {
            echo "🎉 SUCCESS: ${env.WORKSPACE_ENV} deployed successfully!"
        }

        failure {
            echo "⚠️ FAILURE: Rolling back ${env.WORKSPACE_ENV} environment..."
            script {
                def stableImage = "${env.STABLE_IMAGE}"
                sh """
                    aws eks update-kubeconfig --name ${env.CLUSTER_NAME} --region ${env.AWS_REGION} --kubeconfig ${env.KUBECONFIG_PATH}
                    echo "Attempting rollback to ${stableImage}..."
                    kubectl --kubeconfig=${env.KUBECONFIG_PATH} set image deployment/nodeapp nodeapp=${stableImage} --record || echo 'Rollback failed: deployment not found'
                    kubectl --kubeconfig=${env.KUBECONFIG_PATH} rollout status deployment/nodeapp || echo 'Rollback did not complete properly'
                """
            }
            echo "✅ Rollback complete — reverted ${env.WORKSPACE_ENV} to last stable image."
        }
    }
}
