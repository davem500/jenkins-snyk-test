#!/bin/bash

dnf update -y
dnf install -y dnf-plugins-core fontconfig java-21-amazon-corretto-devel jq

dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
dnf install -y terraform

wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
dnf install -y jenkins

# 1. EBS TEMP DIRECTORY
mkdir -p /var/lib/jenkins/tmp
chown jenkins:jenkins /var/lib/jenkins/tmp
chmod 700 /var/lib/jenkins/tmp

mkdir -p /etc/systemd/system/jenkins.service.d
cat <<EOF > /etc/systemd/system/jenkins.service.d/override.conf
[Service]
Environment="JAVA_OPTS=-Djava.awt.headless=true -Djava.io.tmpdir=/var/lib/jenkins/tmp"
Environment="JENKINS_JAVA_CMD=/usr/bin/java"
EOF
systemctl daemon-reload

# Generates unique 24-character password @ runtime
RANDOM_PWD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 24)

# Logs secret password to cloud-init log
echo "JENKINS INITIAL ADMIN PASSWORD: $RANDOM_PWD" | tee -a /var/log/cloud-init-output.log

# 6.Bypass Wizard & Setup
mkdir -p /var/lib/jenkins/init.groovy.d/

# Bypass the wizard
echo "2.462" > /var/lib/jenkins/jenkins.install.UpgradeWizard.state
echo "2.462" > /var/lib/jenkins/jenkins.install.InstallUtil.lastExecVersion

# Groovy script to create user 'admin' with $RANDOM_PWD
cat <<EOF > /var/lib/jenkins/init.groovy.d/basic-security.groovy
#!groovy
import jenkins.model.*
import hudson.security.*

def instance = Jenkins.get()
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount('admin', '$RANDOM_PWD') 
instance.setSecurityRealm(hudsonRealm)

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)
instance.save()
EOF

chown -R jenkins:jenkins /var/lib/jenkins

# 7. PLUGIN BOOTSTRAP 
cat <<EOF > /tmp/plugins.yaml
plugins:
  - aws-credentials:latest
  - pipeline-aws:latest
  - ec2:latest
  - amazon-ecs:latest
  - codedeploy:latest
  - aws-lambda:latest
  - aws-codebuild:latest
  - aws-bucket-credentials:latest
  - aws-secrets-manager-secret-source:latest
  - aws-codepipeline:latest
  - configuration-as-code-secret-ssm:latest
  - cloudformation:latest
  - aws-sam:latest
  - terraform:latest
  - kubernetes:latest
  - google-storage-plugin:latest
  - google-kubernetes-engine:latest
  - google-oauth-plugin:latest
  - pipeline-gcp:latest
  - snyk-security-scanner:latest
  - sonar:latest
  - aqua-security-scanner:latest
  - aqua-microscanner:latest
  - github:latest
  - github-oauth:latest
  - pipeline-github:latest
  - pipeline-githubnotify-step:latest
  - maven-plugin:latest
  - pipeline-maven:latest
  - publish-over-ssh:latest
EOF

curl -fLs -o /tmp/jenkins-plugin-manager.jar https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.14.0/jenkins-plugin-manager-2.14.0.jar

# Run plugin installations as the 'jenkins' user
sudo -u jenkins java -jar /tmp/jenkins-plugin-manager.jar \
  --war /usr/share/java/jenkins.war \
  --plugin-download-directory /var/lib/jenkins/plugins \
  --plugin-file /tmp/plugins.yaml

# 8. START THE DAMN SERVICE!!!
systemctl enable --now jenkins	