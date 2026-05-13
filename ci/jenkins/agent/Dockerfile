FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
     ca-certificates curl wget gnupg lsb-release git python3 python3-pip jq unzip sudo apt-transport-https gnupg2 && \
  rm -rf /var/lib/apt/lists/*

# Install Docker CLI
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list \
  && apt-get update && apt-get install -y --no-install-recommends docker-ce-cli \
  && rm -rf /var/lib/apt/lists/*

# Install Azure CLI
RUN curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /usr/share/keyrings/microsoft.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/azure-cli.list \
  && apt-get update && apt-get install -y --no-install-recommends azure-cli \
  && rm -rf /var/lib/apt/lists/*

# kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
  && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

# helm
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kustomize
RUN KUSTOMIZE_VER=v5.0.1 \
  && curl -sLO "https://github.com/kubernetes-sigs/kustomize/releases/download/${KUSTOMIZE_VER}/kustomize_${KUSTOMIZE_VER}_linux_amd64.tar.gz" \
  && tar -xzf kustomize_${KUSTOMIZE_VER}_linux_amd64.tar.gz && mv kustomize /usr/local/bin/ && rm kustomize_${KUSTOMIZE_VER}_linux_amd64.tar.gz

# yq (mikefarah)
RUN wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/v4.35.1/yq_linux_amd64 && chmod +x /usr/local/bin/yq

# trivy
RUN TRIVY_VER=$(curl -s https://api.github.com/repos/aquasecurity/trivy/releases/latest | grep -Po '"tag_name": "\\K.*?(?=\")') \
  && curl -sL "https://github.com/aquasecurity/trivy/releases/download/${TRIVY_VER}/trivy_${TRIVY_VER}_Linux-64bit.tar.gz" -o /tmp/trivy.tar.gz || true \
  && if [ -f /tmp/trivy.tar.gz ]; then tar xzf /tmp/trivy.tar.gz -C /tmp && mv /tmp/trivy /usr/local/bin/ || true; fi || true

# gitleaks
RUN GITLEAKS_VER=$(curl -s https://api.github.com/repos/zricethezav/gitleaks/releases/latest | grep -Po '"tag_name": "\\K.*?(?=\")') \
  && curl -sL "https://github.com/zricethezav/gitleaks/releases/download/${GITLEAKS_VER}/gitleaks_${GITLEAKS_VER}_Linux_x86_64.tar.gz" -o /tmp/gitleaks.tar.gz || true \
  && if [ -f /tmp/gitleaks.tar.gz ]; then tar xzf /tmp/gitleaks.tar.gz -C /tmp && mv /tmp/gitleaks /usr/local/bin/ || true; fi || true

# Install Python tools
RUN pip3 install --no-cache-dir pytest

# Small user for Jenkins
RUN useradd -m -s /bin/bash jenkins \
  && echo "jenkins ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/jenkins

WORKDIR /home/jenkins
USER jenkins
ENV PATH=/usr/local/bin:$PATH
ENTRYPOINT ["/bin/bash"]
