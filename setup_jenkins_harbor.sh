# Arguments
username="admin"
harbor_project_name="product"

# Use environment variables passed from setup_system.sh
password="$harbor_initial_password"
harbor_url="https://$harbor_hostname"

# Prerequisites
# yq needs to be installed
#   brew install yq
# jq needs to be installed
#   brew install jq

# Script
retry_command() {
  local cmd="$1"
  echo -e "\033[34mRunning $cmd\033[0m"
  until eval "$cmd"; do
    echo -e "\033[31mRetrying $cmd\033[0m"
    sleep 15
  done
}

assert_eq() {
  expected="$1"
  actual="$2"

  if [ "$expected" != "$actual" ]; then
    echo "assert_eq failed: expected '$expected', got '$actual'" >&2
    return 1
  fi
}

escape_dollar() {
  local input="$1"
  # Replace every $ with \$
  printf '%s\n' "${input//\$/\\\$}"
}

retry_command 'assert_eq "healthy" "$(curl -s -u "$username:$password" "$harbor_url/api/v2.0/health" | yq ".components[0].status")"'

# Delete all existing projects
project_names=$(curl -s -u "$username:$password" "$harbor_url/api/v2.0/projects" | yq '.[].name')
for name in $project_names; do
  echo "Deleting project: $name"
  curl -s -X DELETE -u "$username:$password" "$harbor_url/api/v2.0/projects/$name"
done

# Create new project
echo "Creating project: $harbor_project_name"
curl -X POST "$harbor_url/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "Authorization: Basic $(printf '%s:%s' "$username" "$password" | base64)" \
  -d "{\"project_name\":\"$harbor_project_name\",\"public\":false}"

# Create robot account
echo "Creating robot: $harbor_project_name"
output=$(curl -X POST "$harbor_url/api/v2.0/robots" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "Authorization: Basic $(printf '%s:%s' "$username" "$password" | base64)" \
  -d '{
        "name": "supermario",
        "level": "system",
        "disable": false,
        "duration": -1,
        "permissions": [
          {
            "access": [
                { "action": "push", "resource": "repository" },
                { "action": "pull", "resource": "repository" },
                { "action": "create", "resource": "tag" },
                { "action": "delete", "resource": "tag" }
            ],
            "kind": "project",
            "namespace": "*"
          }
        ]
      }')
harbor_robot_name=$(echo "$output" | jq -r '.name')
harbor_robot_name_escaped="$(escape_dollar "$harbor_robot_name")"
harbor_robot_secret=$(echo "$output" | jq -r '.secret')
retry_command 'kubectl create secret generic harbor-robot --from-literal=username="$harbor_robot_name_escaped" --from-literal=password="$harbor_robot_secret" --namespace jenkins \
  --type=Opaque --dry-run=client -o yaml | kubectl label --local -f - jenkins.io/credentials-type=usernamePassword \
  --dry-run=client -o yaml | kubectl apply -f -'

kubectl create namespace dev
kubectl create namespace qa
kubectl create namespace prod

kubectl create secret docker-registry harbor-robot --docker-server="$harbor_hostname" --docker-username="$harbor_robot_name" \
  --docker-password="$harbor_robot_secret" --docker-email=ci@example.com -n dev
kubectl create secret docker-registry harbor-robot --docker-server="$harbor_hostname" --docker-username="$harbor_robot_name" \
  --docker-password="$harbor_robot_secret" --docker-email=ci@example.com -n qa
kubectl create secret docker-registry harbor-robot --docker-server="$harbor_hostname" --docker-username="$harbor_robot_name" \
  --docker-password="$harbor_robot_secret" --docker-email=ci@example.com -n prod
