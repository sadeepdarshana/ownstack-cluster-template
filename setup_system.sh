# All parameters must be provided as environment variables.
# When run via Ownstack, these are injected by the backend.
# For manual runs, export them before calling this script:
#
#   export vps=1.2.3.4
#   export git_username=youruser
#   export git_user_path=https://github.com/youruser
#   export github_pat=ghp_...
#   export system_root_app_repo=https://github.com/youruser/your-cluster
#   export system_root_app_path=system
#   export cloudflare_token=...
#   export harbor_hostname=harbor.example.com
#   export harbor_initial_password=...
#   export harbor_chart_version=1.17.2
#   export traefik_dashboard=traefik.example.com
#   export traefik_email=you@example.com
#   export traefik_chart_version=36.3.0
#   export jenkins_hostname=jenkins.example.com
#   export jenkins_initial_password=...
#   export jenkins_chart_version=5.8.79
#   export jenkins_pipeline_library_repo=https://github.com/youruser/your-cluster.git
#   export jenkins_pipeline_library_path=jenkins_pipeline_library
#   export jenkins_github_org_folder_name="Repositories"     # optional, this is the default
#   export jenkins_github_org_folder_repo_filter="*"         # optional, wildcard filter for repos to include
#   export jenkins_jenkinsfile_path="infrastructure/Jenkinsfile"  # optional, path to Jenkinsfile inside each repo

# Prerequisites
# Make sure the SSH is setup from local machine to the VPS
# curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/arm64/kubectl" # installs kubectl on local machine
# brew install helm helmfile
# cloudflare is the DNS nameserver and proxy is preferably disabled
# github_pat created with permissions to list and clone repos

# Script
start_time=$(date +%s)
echo "Start: $(date)"

retry_command() {
  sleep 5
  local cmd="$1"
  echo -e "\033[34mRunning $cmd\033[0m"
  until eval "$cmd"; do
    echo -e "\033[31mRetrying $cmd\033[0m"
    sleep 15
  done
}

# Logging in SSH and installing k3s
ssh-keygen -R $vps
retry_command "ssh -o StrictHostKeyChecking=accept-new root@$vps \"curl -sfL https://get.k3s.io | sh -s - --disable=traefik\""
retry_command "scp root@$vps:/etc/rancher/k3s/k3s.yaml ~/.kube/config"
retry_command "sed -i.bak \"s/127\.0\.0\.1/$vps/g\" ~/.kube/config" # replaces 127.0.0.1 with the public IP

# Install Docker
ssh root@$vps 'bash -s' << 'EOF'
export DEBIAN_FRONTEND=noninteractive
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
 apt-get remove -y --force-yes $pkg
done
apt-get update
apt-get install -y --force-yes ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
 -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo \"${UBUNTU_CODENAME:-$VERSION_CODENAME}\") stable" \
| tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y --force-yes docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
EOF

# Deploy the system using Helmfile
cd ./system
retry_command "helmfile sync"
cd ..

# Create the Cloudflare token secret for Traefik DNS challenge
retry_command "kubectl create secret generic cloudflare-token --from-literal=token=$cloudflare_token -n traefik" # for DNS challenge

# Jenkins github PAT
retry_command 'kubectl create secret generic github-pat --from-literal=username="$git_username" --from-literal=password="$github_pat" --namespace jenkins \
  --type=Opaque --dry-run=client -o yaml | kubectl label --local -f - jenkins.io/credentials-type=usernamePassword \
  --dry-run=client -o yaml | kubectl apply -f -'

./setup_jenkins_harbor.sh

end_time=$(date +%s)
duration=$((end_time - start_time))
echo "End:   $(date)"
echo "Duration: ${duration}s"
