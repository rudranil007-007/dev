pipeline {
  agent any
  triggers { pollSCM('H/2 * * * *') }
  environment {
    AWS_REGION         = 'ap-southeast-2'
    AWS_DEFAULT_REGION = 'ap-southeast-2'
    ACCOUNT_ID         = '124118675423'
    REGISTRY           = "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    IMAGE              = "${REGISTRY}/vprofile-app:${BUILD_NUMBER}"
    CLUSTER            = 'vprofile'
  }
  stages {
    stage('Build image') {
      steps { sh 'docker build -t $IMAGE .' }
    }
    stage('Push to ECR') {
      steps {
        sh '''
          aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $REGISTRY
          docker push $IMAGE
        '''
      }
    }
    stage('Deploy to EKS') {
      steps {
        sh '''
          aws eks update-kubeconfig --name $CLUSTER --region $AWS_REGION
          kubectl apply -f aws/gp3-sc.yaml
          kubectl patch sc gp2 -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' || true
          kubectl get namespace vprofile || kubectl create namespace vprofile
          kubectl -n vprofile create configmap db-init --from-file=db_backup.sql=src/main/resources/db_backup.sql --dry-run=client -o yaml | kubectl apply -f -
          sed "s|image: vprofile-app:v1|image: $IMAGE|" k8s/vprofile.yaml | kubectl apply -f - || true
          kubectl apply -f k8s/web01-svc.yaml
          kubectl -n vprofile rollout status deployment/app01 --timeout=900s
        '''
      }
    }
  }
}
