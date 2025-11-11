pipeline {
    agent any

    // Parameters for dynamic configuration
    parameters {
        string(name: 'CLUSTER_NAME', defaultValue: '', description: 'Enter EKS cluster name (leave empty to use branch default)')
        string(name: 'REGION', defaultValue: 'ap-south-1', description: 'Enter AWS region')
        choice(name: 'DESTROY_CONFIRMATION', choices: ['no', 'yes'], description: 'Destroy cluster if exists before deployment?')
    }

    environment {
        AWS_REGION = "${params.REGION}"
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

                    // Use parameterized cluster name if provided
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

                    // ✅ Correct AWS credentials binding
                    withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                        credentialsId: 'aws-access-key']]) {

                        // ✅ Correct cluster existence check using exit code
                        def clusterExists = sh(
                            script: """
                                set +e
                                aws eks describe-cluster --name ${env.CLUSTER_NAME} --region ${env.AWS_REGION} >/dev/null 2>&1
                                echo \$?
                            """,
                            returnStdout: true
                        ).trim()

                        // ✅ Destroy mode
                        if (params.DESTROY_CONFIRMATION == 'yes') {

                            if (clusterExists == "0") {
                                echo "Cluster exists → Destroying cluster ${env.CLUSTER_NAME}"

                                dir("terraform/envs/${env.WORKSPACE_ENV}") {
                                    sh """
                                    terraform init -reconfigure
                                    terraform workspace select ${env.WORKSPACE_ENV} || terraform workspace new ${env.WORKSPACE_ENV}
                                    terraform destroy -auto-approve -var='cluster_name=${env.CLUSTER_NAME}' -var='region=${env.AWS_REGION}'
                                    """
                                }

                            } else {
                                echo "Cluster does not exist. Nothing to destroy."
                            }

                            echo "Stopping pipeline because DESTROY_CONFIRMATION = yes"
                            currentBuild.result = 'SUCCESS'
                            error("STOP_PIPELINE_AFTER_DESTROY")
                        }

                        echo "Destroy not selected → proceeding with deployment"
                    }
                }
            }
        }

        stage('Build Node App') {
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
            steps {
                script {
                    docker.withRegistry('', 'dockerhub-creds') {
                        docker.image("yaramprasanthi/nodeapp:${env.WORKSPACE_ENV}").push()
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
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} apply -f deployment.yaml"
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} apply -f service.yaml"
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                script {
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get pods -o wide"
                    sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get svc"
                }
            }
        }
    }

    post {
        success { echo "✅ Pipeline succeeded for branch ${env.BRANCH_NAME}!" }
        failure { echo "❌ Pipeline failed." }
    }
}
