# All parameters must be provided as environment variables.
# When run via Ownstack, these are injected automatically.
# For manual runs, export them before calling this script:
#
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
#   export jenkins_github_org_folder_name="Repositories"          # optional, this is the default
#   export jenkins_github_org_folder_repo_filter="*"              # optional, wildcard filter for repos to include
#   export jenkins_jenkinsfile_path="infrastructure/Jenkinsfile"  # optional, path to Jenkinsfile inside each repo
#
# This script runs directly on the VPS. All prerequisites are installed automatically.
# cloudflare is the DNS nameserver and proxy must be disabled for the subdomains.
# github_pat created with permissions to create repos, list and clone.

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

# Install k3s
retry_command "curl -sfL https://get.k3s.io | sh -s - --disable=traefik"

# Set up kubeconfig
mkdir -p ~/.kube
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
chmod 600 ~/.kube/config

# Install Docker and base packages
export DEBIAN_FRONTEND=noninteractive
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  apt-get remove -y --force-yes $pkg
done
apt-get update
apt-get install -y --force-yes ca-certificates curl git jq
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y --force-yes docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Install Helm
retry_command "curl -sfL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"

# Install Helmfile
HELMFILE_VERSION=0.171.0
retry_command "curl -sSL \"https://github.com/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION}_linux_amd64.tar.gz\" | tar -xz -C /usr/local/bin helmfile"

# Install yq
YQ_VERSION=4.44.2
retry_command "curl -sSL \"https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64\" -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq"

# Deploy the system using Helmfile
cd ./system
retry_command "helmfile sync"
cd ..

# Create the Cloudflare token secret for Traefik DNS challenge
retry_command 'kubectl create secret generic cloudflare-token --from-literal=token="$cloudflare_token" -n traefik \
  --dry-run=client -o yaml | kubectl apply -f -'

# Jenkins github PAT
retry_command 'kubectl create secret generic github-pat --from-literal=username="$git_username" --from-literal=password="$github_pat" --namespace jenkins \
  --type=Opaque --dry-run=client -o yaml | kubectl label --local -f - jenkins.io/credentials-type=usernamePassword \
  --dry-run=client -o yaml | kubectl apply -f -'

./setup_jenkins_harbor.sh

end_time=$(date +%s)
duration=$((end_time - start_time))
echo "End:   $(date)"
echo "Duration: ${duration}s"
