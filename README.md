# vProfile: Java app on Docker, Kubernetes, Jenkins and AWS

Multi-tier Java web app (Nginx, Tomcat, MariaDB, Memcached, RabbitMQ), based on the open-source vprofile course project. My work is the DevOps layer around it.

## What I built
- Manual VM setup with Vagrant (vagrant/)
- Multi-stage Dockerfile (Maven build, Tomcat 10.1 runtime)
- Docker Compose for all 5 services
- Kubernetes manifests: Deployments, Services, Secret, ConfigMaps, PVC, init container, probes (k8s/)
- Jenkins pipeline and AWS EKS deployment (in progress)

## Architecture
Browser -> Nginx -> Tomcat -> MariaDB, Memcached, RabbitMQ

## Run with Docker Compose
    docker compose up -d --build
Open http://localhost

## Run on Kubernetes
    docker build -t vprofile-app:v1 .
    kubectl create namespace vprofile
    kubectl -n vprofile create configmap db-init --from-file=db_backup.sql=src/main/resources/db_backup.sql
    kubectl apply -f k8s/
