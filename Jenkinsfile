pipeline {
    agent any

    // -------------------------
    // 🔧 Parameters
    // -------------------------
    parameters {
        choice(name: 'ENV', choices: ['dev', 'staging', 'production'], description: 'Select environment to deploy')
    }

    // -------------------------
    // 🌍 Environment Variables
    // -------------------------
    environment {
        AWS_CREDENTIALS = credentials('aws-access-key')
        TF_DIR                = 'terraform/envs'
        DOCKER_REPO           = 'yaramprasanthi/nodeapp'
        DOCKER_IMAGE          = "${DOCKER_REPO}:${params.ENV}-${BUILD_NUMBER}"
        STABLE_IMAGE          = "${DOCKER_REPO}:stable-${params.ENV}"
        KUBECONFIG_PATH       = "/var/lib/jenkins/.kube/${params.ENV}-config"
    }

    // -------------------------
    // 🚦 Stages
    // -------------------------
    stages {

        stages {

            stage('Checkout SCM') {
                steps {
                    checkout scm
                }
            }

        // 🐳 Build and push Docker image for selected environment
        stage('Build & Push Docker Image') {
            steps {
                script {
                    echo "🚀 Building Docker image for ${params.ENV}..."
                    withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                        sh """
                            docker build -t ${DOCKER_IMAGE} ./app
                            echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin
                            docker push ${DOCKER_IMAGE}
                        """
                    }
                }
            }
        }

        // ⚙️ Terraform infra setup for this environment
        stage('Terraform Init & Apply') {
            steps {
                dir("${TF_DIR}/${params.ENV}") {
                    script {
                        sh """
                            terraform init -reconfigure
                            terraform workspace select ${params.ENV} || terraform workspace new ${params.ENV}
                            terraform apply -auto-approve -var='cluster_name=${params.ENV}' -var='region=ap-south-1'
                        """
                    }
                }
            }
        }

        // 📦 Deploy image to Kubernetes cluster
        stage('Deploy to Kubernetes') {
            steps {
                script {
                    echo "🚀 Deploying ${DOCKER_IMAGE} to ${params.ENV} environment..."
                    sh """
                        aws eks update-kubeconfig --name ${params.ENV} --region ap-south-1 --kubeconfig ${KUBECONFIG_PATH}
                        kubectl --kubeconfig=${KUBECONFIG_PATH} set image deployment/nodeapp nodeapp=${DOCKER_IMAGE} --record
                        kubectl --kubeconfig=${KUBECONFIG_PATH} rollout status deployment/nodeapp
                    """
                }
            }
        }

        // 🩺 Verify health of the deployment
        stage('Verify Application Health') {
            steps {
                script {
                    echo "🔍 Checking pod status..."
                    def unhealthyPods = sh(
                        script: "kubectl --kubeconfig=${KUBECONFIG_PATH} get pods -n default --no-headers | awk '{print \$3}' | grep -v Running || true",
                        returnStdout: true
                    ).trim()
                    if (unhealthyPods) {
                        error("❌ Some pods are not running properly: ${unhealthyPods}")
                    }

                    def svcHost = sh(
                        script: "kubectl --kubeconfig=${KUBECONFIG_PATH} get svc nodeapp-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'",
                        returnStdout: true
                    ).trim()

                    if (!svcHost) {
                        error("❌ Service LoadBalancer not ready for ${params.ENV}")
                    }

                    echo "🌐 Testing app endpoint at http://${svcHost}"
                    def httpCode = sh(script: "curl -s -o /dev/null -w '%{http_code}' http://${svcHost}", returnStdout: true).trim()
                    if (httpCode != "200") {
                        error("❌ Health check failed (HTTP ${httpCode})")
                    }

                    echo "✅ App is healthy (HTTP 200)"
                }
            }
        }

        // 🏷️ If all good — tag this image as stable
        stage('Tag Stable Image') {
            steps {
                script {
                    echo "🏷 Updating stable image tag for ${params.ENV}"
                    withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                        sh """
                            echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin
                            docker pull ${DOCKER_IMAGE}
                            docker tag ${DOCKER_IMAGE} ${STABLE_IMAGE}
                            docker push ${STABLE_IMAGE}
                        """
                    }
                }
            }
        }
    }

    // -------------------------
    // 🧩 Post Actions (Success / Failure)
    // -------------------------
    post {

        success {
            echo "🎉 SUCCESS: Deployed ${params.ENV} and updated ${STABLE_IMAGE} as stable."
        }

        failure {
            echo "⚠️ FAILURE: Rolling back to last stable version for ${params.ENV}..."
            script {
                def stableImage = "${STABLE_IMAGE}"
                sh """
                    aws eks update-kubeconfig --name ${params.ENV} --region ap-south-1 --kubeconfig ${KUBECONFIG_PATH}
                    echo "Attempting rollback to ${stableImage}..."
                    kubectl --kubeconfig=${KUBECONFIG_PATH} set image deployment/nodeapp nodeapp=${stableImage} --record || echo "No deployment found"
                    kubectl --kubeconfig=${KUBECONFIG_PATH} rollout status deployment/nodeapp || echo "Rollback failed or not applicable"
                """
            }
            echo "✅ Rollback complete — ${params.ENV} reverted to last stable image."
        }
    }
}
