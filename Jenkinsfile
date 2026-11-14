pipeline {
  agent any
  triggers { pollSCM('* * * * *') }
  environment {
    KUBECONFIG = '/etc/rancher/k3s/k3s.yaml'
    IMG        = "vprofile-app:${BUILD_NUMBER}"
  }
  stages {
    stage('Build image') {
      steps { sh 'docker build -t $IMG .' }
    }
    stage('Load into Kubernetes') {
      steps {
        sh '''
          docker save $IMG -o /tmp/vprofile.tar
          sudo /usr/local/bin/k3s ctr -n k8s.io images import /tmp/vprofile.tar
          rm -f /tmp/vprofile.tar
        '''
      }
    }
    stage('Deploy') {
      steps {
        sh '''
          kubectl get namespace vprofile || kubectl create namespace vprofile
          kubectl -n vprofile create configmap db-init --from-file=db_backup.sql=src/main/resources/db_backup.sql --dry-run=client -o yaml | kubectl apply -f -
          sed "s|image: vprofile-app:v1|image: $IMG|" k8s/vprofile.yaml | kubectl apply -f - || true
          kubectl apply -f k8s/web01-svc.yaml
          kubectl -n vprofile rollout status deployment/app01 --timeout=600s
          kubectl -n vprofile get pods
        '''
      }
    }
  }
}
