#!/bin/bash
set -x
PASS="$1"
REPO="$2"
export DEBIAN_FRONTEND=noninteractive
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
mkdir -p /etc/apt/keyrings
apt-get update -y
apt-get install -y fontconfig openjdk-21-jre-headless git curl
curl -fsSL https://get.docker.com | sh
wget -O /etc/apt/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" > /etc/apt/sources.list.d/jenkins.list
apt-get update -y
apt-get install -y jenkins
systemctl stop jenkins
usermod -aG docker jenkins
mkdir -p /var/lib/jenkins/init.groovy.d
cat > /var/lib/jenkins/init.groovy.d/security.groovy << GROOVY
import jenkins.model.*
import hudson.security.*
def j = Jenkins.getInstance()
def realm = new HudsonPrivateSecurityRealm(false)
realm.createAccount("admin", "$PASS")
j.setSecurityRealm(realm)
def s = new FullControlOnceLoggedInAuthorizationStrategy()
s.setAllowAnonymousRead(false)
j.setAuthorizationStrategy(s)
j.save()
GROOVY
chown -R jenkins:jenkins /var/lib/jenkins
mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/o.conf << 'CONF'
[Service]
Environment="JAVA_OPTS=-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false"
CONF
systemctl daemon-reload
systemctl start jenkins
until curl -sf http://localhost:8080/login > /dev/null; do sleep 5; done
curl -s -u admin:$PASS http://localhost:8080/jnlpJars/jenkins-cli.jar -o /tmp/cli.jar
CLI="java -jar /tmp/cli.jar -s http://localhost:8080 -auth admin:$PASS"
for i in 1 2 3 4 5; do $CLI install-plugin workflow-aggregator git && break; sleep 20; done
systemctl restart jenkins
sleep 20
until curl -sf http://localhost:8080/login > /dev/null; do sleep 5; done
cat > /tmp/job.xml << JOB
<flow-definition>
 <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition">
  <scm class="hudson.plugins.git.GitSCM">
   <configVersion>2</configVersion>
   <userRemoteConfigs><hudson.plugins.git.UserRemoteConfig><url>$REPO</url></hudson.plugins.git.UserRemoteConfig></userRemoteConfigs>
   <branches><hudson.plugins.git.BranchSpec><name>*/main</name></hudson.plugins.git.BranchSpec></branches>
  </scm>
  <scriptPath>Jenkinsfile</scriptPath>
  <lightweight>true</lightweight>
 </definition>
</flow-definition>
JOB
$CLI create-job vprofile-pipeline < /tmp/job.xml
$CLI build vprofile-pipeline
