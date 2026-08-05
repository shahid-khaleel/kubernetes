# Jenkins controller image with the Docker CLI and kubectl added, so the
# pipeline's "Build image" and "Deploy to Minikube" stages don't need a
# separate build agent.
#
# NOTE (local-demo tradeoff, not a production pattern): this image talks to
# Docker by mounting the host's /var/run/docker.sock (see deployment.yaml),
# which grants the Jenkins pod root-equivalent access to the node. That's
# acceptable for a throwaway local Minikube cluster; for a real cluster use
# Kaniko or a rootless BuildKit sidecar instead so Jenkins never touches a
# privileged socket. See the project README's "Production considerations"
# section.
FROM jenkins/jenkins:lts-jdk17

USER root

ARG DOCKER_CLI_VERSION=25.0.3
ARG KUBECTL_VERSION=v1.29.3

RUN curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_CLI_VERSION}.tgz" -o /tmp/docker.tgz \
    && tar xzf /tmp/docker.tgz -C /tmp \
    && mv /tmp/docker/docker /usr/local/bin/docker \
    && rm -rf /tmp/docker /tmp/docker.tgz \
    && curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl

# The host's docker.sock is typically owned by a "docker" group whose GID
# varies by host. Simplest fix for a local demo: let the jenkins user use
# sudo-free access by adding it to a docker group matching the mounted
# socket's GID at deploy time (see README "Docker socket permissions").
RUN groupadd -f docker && usermod -aG docker jenkins

USER jenkins

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
