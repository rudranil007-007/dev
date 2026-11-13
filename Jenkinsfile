pipeline {
  agent any
  triggers { pollSCM('* * * * *') }
  stages {
    stage('Build') {
      steps { sh 'docker compose build' }
    }
    stage('Deploy') {
      steps { sh 'docker compose up -d --remove-orphans' }
    }
  }
}
