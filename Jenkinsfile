pipeline {
  agent any

  parameters {
    choice(name: 'ACTION', choices: ['deploy', 'destroy-only'], description: 'Pick what to do')
    string(name: 'CLUSTER_NAME', defaultValue: '', description: 'EKS cluster name (blank = default per branch)')
    string(name: 'REGION', defaultValue: 'ap-south-1', description: 'AWS region')
  }

  environment {
    AWS_REGION = "${params.REGION}"
    AWS_CREDENTIALS = credentials('aws-access-key')
    DOCKERHUB_CRED = credentials('dockerhub-creds')
  }

  stages {

    stage('Checkout SCM') {
      steps { checkout scm }
    }

    stage('Set Environment Based on Branch') {
      steps {
        script {
          if (env.BRANCH_NAME == 'dev') {
            env.WORKSPACE_ENV = 'dev'
            env.DEFAULT_CLUSTER_NAME = 'eks-dev'
            env.KUBECONFIG_PATH = "/var/lib/jenkins/.kube/eks-dev-config"
          } else if (env.BRANCH_NAME == 'staging') {
            env.WORKSPACE_ENV = 'staging'
            env.DEFAULT_CLUSTER_NAME = 'eks-staging'
            env.KUBECONFIG_PATH = "/var/lib/jenkins/.kube/eks-staging-config"
          } else if (env.BRANCH_NAME == 'main') {
            env.WORKSPACE_ENV = 'prod'
            env.DEFAULT_CLUSTER_NAME = 'eks-prod'
            env.KUBECONFIG_PATH = "/var/lib/jenkins/.kube/eks-prod-config"
          } else {
            error("Unknown branch: ${env.BRANCH_NAME}")
          }

          env.CLUSTER_NAME = (params.CLUSTER_NAME?.trim()) ? params.CLUSTER_NAME.trim() : env.DEFAULT_CLUSTER_NAME
          echo "Branch ${env.BRANCH_NAME} → Env ${env.WORKSPACE_ENV} → Cluster ${env.CLUSTER_NAME} → Region ${env.AWS_REGION}"
        }
      }
    }

    stage('Destroy (when ACTION = destroy-only)') {
      when { expression { params.ACTION == 'destroy-only' } }
      steps {
        script {
          // Check if cluster exists via exit code
          def rc = sh(returnStatus: true, script: """
            aws eks describe-cluster \
              --name ${env.CLUSTER_NAME} \
              --region ${env.AWS_REGION} >/dev/null 2>&1
          """)

          if (rc == 0) {
            echo "Cluster ${env.CLUSTER_NAME} exists → destroying… (workspace: ${env.WORKSPACE_ENV})"
            dir("terraform/envs/${env.WORKSPACE_ENV}") {
              sh """
                terraform init -reconfigure
                terraform workspace select ${env.WORKSPACE_ENV} || terraform workspace new ${env.WORKSPACE_ENV}
                terraform destroy -auto-approve -var='cluster_name=${env.CLUSTER_NAME}' -var='region=${env.AWS_REGION}'
              """
            }
          } else {
            echo "Cluster ${env.CLUSTER_NAME} NOT found in AWS. Nothing to destroy."
          }

          echo "Destroy-only completed. Skipping remaining stages."
        }
      }
    }

    // All stages below run only for deploy
    stage('Build Node App') {
      when { expression { params.ACTION == 'deploy' } }
      steps {
        dir('app') {
          sh 'npm install'
          script { docker.build("yaramprasanthi/nodeapp:${env.WORKSPACE_ENV}") }
        }
      }
    }

    stage('Push Docker Image') {
      when { expression { params.ACTION == 'deploy' } }
      steps {
        script {
          docker.withRegistry('', 'dockerhub-creds') {
            docker.image("yaramprasanthi/nodeapp:${env.WORKSPACE_ENV}").push()
          }
        }
      }
    }

    stage('Terraform Init & Apply') {
      when { expression { params.ACTION == 'deploy' } }
      steps {
        dir("terraform/envs/${env.WORKSPACE_ENV}") {
          sh """
            terraform init -reconfigure
            terraform workspace select ${env.WORKSPACE_ENV} || terraform workspace new ${env.WORKSPACE_ENV}
            terraform apply -auto-approve -var='cluster_name=${env.CLUSTER_NAME}' -var='region=${env.AWS_REGION}'
          """
        }
      }
    }

    stage('Configure kubeconfig') {
      when { expression { params.ACTION == 'deploy' } }
      steps {
        sh "aws eks update-kubeconfig --name ${env.CLUSTER_NAME} --region ${env.AWS_REGION} --kubeconfig ${env.KUBECONFIG_PATH}"
      }
    }

    stage('Deploy to EKS') {
      when { expression { params.ACTION == 'deploy' } }
      steps {
        dir("k8s/${env.WORKSPACE_ENV}") {
          sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} apply -f deployment.yaml"
          sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} apply -f service.yaml"
        }
      }
    }

    stage('Verify Deployment') {
      when { expression { params.ACTION == 'deploy' } }
      steps {
        sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get pods -o wide"
        sh "kubectl --kubeconfig=${env.KUBECONFIG_PATH} get svc"
      }
    }
  }

  post {
    success {
      echo (params.ACTION == 'destroy-only'
        ? "✅ Destroy-only run finished successfully."
        : "✅ Deploy run finished successfully.")
    }
    failure {
      echo "❌ Pipeline failed. Attempting cleanup (only for deploy runs)…"
      script {
        if (params.ACTION == 'deploy') {
          dir("terraform/envs/${env.WORKSPACE_ENV}") {
            sh """
              terraform init -reconfigure
              terraform workspace select ${env.WORKSPACE_ENV} || terraform workspace new ${env.WORKSPACE_ENV}
              terraform destroy -auto-approve -var='cluster_name=${env.CLUSTER_NAME}' -var='region=${env.AWS_REGION}' || echo 'Nothing to destroy'
            """
          }
        } else {
          echo "Destroy-only run failed earlier; skipping auto-clean."
        }
      }
    }
  }
}
