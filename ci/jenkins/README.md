Jenkins Agent Docker image

Overview
This image bundles tools required by the Jenkins pipeline in this repo:
- docker CLI (client only)
- Azure CLI
- kubectl
- helm
- kustomize
- yq (mikefarah)
- trivy (vulnerability scanner)
- gitleaks (secret scanner)
- pytest (for running tests)

Build
  ./ci/jenkins/build-agent-image.sh gkhandale/jenkins-agent:latest

Run (recommended for Docker-based Jenkins agents)
Mount Docker socket if you need to run docker build/push from the agent:
  docker run --rm -it \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "${HOME}/.docker:/home/jenkins/.docker" \
    -v "${PWD}:/workspace" \
    -w /workspace \
    gkhandale/jenkins-agent:latest

Notes
- For security, prefer running builds in Kubernetes with a dedicated service account instead of mounting the host Docker socket.
- The image installs the docker client only; to run docker-in-docker you must provide a daemon (host socket or DinD service).
- If you plan to use this image as an OCI image for Kubernetes agents, push it to your ACR and reference in your Jenkins agent configuration.
