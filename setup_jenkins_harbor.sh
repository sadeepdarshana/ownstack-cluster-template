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

# Create Jenkins GitHub Organization Folder
jenkins_url="https://$jenkins_hostname"
org_folder_name="${jenkins_github_org_folder_name:-Repositories}"
encoded_folder_name=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$org_folder_name")
org_repo_filter="${jenkins_github_org_folder_repo_filter:-*}"
org_jenkinsfile_path="${jenkins_jenkinsfile_path:-infrastructure/Jenkinsfile}"

org_folder_xml=$(cat <<XML
<?xml version='1.1' encoding='UTF-8'?>
<jenkins.branch.OrganizationFolder plugin="branch-api">
  <actions/>
  <description></description>
  <properties>
    <jenkins.branch.OrganizationChildHealthMetricsProperty>
      <templates>
        <com.cloudbees.hudson.plugins.folder.health.NamedChildHealthMetric plugin="cloudbees-folder">
          <childName></childName>
        </com.cloudbees.hudson.plugins.folder.health.NamedChildHealthMetric>
        <com.cloudbees.hudson.plugins.folder.health.WorstChildHealthMetric plugin="cloudbees-folder">
          <nonRecursive>false</nonRecursive>
        </com.cloudbees.hudson.plugins.folder.health.WorstChildHealthMetric>
      </templates>
    </jenkins.branch.OrganizationChildHealthMetricsProperty>
    <jenkins.branch.OrganizationChildOrphanedItemsProperty>
      <strategy class="jenkins.branch.OrganizationChildOrphanedItemsProperty\$Inherit"/>
    </jenkins.branch.OrganizationChildOrphanedItemsProperty>
    <jenkins.branch.OrganizationChildTriggersProperty>
      <templates>
        <com.cloudbees.hudson.plugins.folder.computed.PeriodicFolderTrigger plugin="cloudbees-folder">
          <spec>H H/4 * * *</spec>
          <interval>86400000</interval>
        </com.cloudbees.hudson.plugins.folder.computed.PeriodicFolderTrigger>
      </templates>
    </jenkins.branch.OrganizationChildTriggersProperty>
    <jenkins.branch.NoTriggerOrganizationFolderProperty>
      <branches>main</branches>
      <strategy>NONE</strategy>
    </jenkins.branch.NoTriggerOrganizationFolderProperty>
  </properties>
  <folderViews class="jenkins.branch.OrganizationFolderViewHolder">
    <owner reference="../.."/>
  </folderViews>
  <healthMetrics/>
  <icon class="jenkins.branch.MetadataActionFolderIcon">
    <owner class="jenkins.branch.OrganizationFolder" reference="../.."/>
  </icon>
  <orphanedItemStrategy class="com.cloudbees.hudson.plugins.folder.computed.DefaultOrphanedItemStrategy" plugin="cloudbees-folder">
    <pruneDeadBranches>true</pruneDeadBranches>
    <daysToKeep>-1</daysToKeep>
    <numToKeep>-1</numToKeep>
    <abortBuilds>false</abortBuilds>
  </orphanedItemStrategy>
  <triggers>
    <com.cloudbees.hudson.plugins.folder.computed.PeriodicFolderTrigger plugin="cloudbees-folder">
      <spec>H H/4 * * *</spec>
      <interval>86400000</interval>
    </com.cloudbees.hudson.plugins.folder.computed.PeriodicFolderTrigger>
  </triggers>
  <disabled>false</disabled>
  <navigators>
    <org.jenkinsci.plugins.github__branch__source.GitHubSCMNavigator plugin="github-branch-source">
      <repoOwner>$git_username</repoOwner>
      <apiUri>https://api.github.com</apiUri>
      <credentialsId>github-pat</credentialsId>
      <enableAvatar>false</enableAvatar>
      <traits>
        <jenkins.scm.impl.trait.WildcardSCMSourceFilterTrait plugin="scm-api">
          <includes>$org_repo_filter</includes>
          <excludes></excludes>
        </jenkins.scm.impl.trait.WildcardSCMSourceFilterTrait>
        <org.jenkinsci.plugins.github__branch__source.BranchDiscoveryTrait>
          <strategyId>1</strategyId>
        </org.jenkinsci.plugins.github__branch__source.BranchDiscoveryTrait>
        <org.jenkinsci.plugins.github__branch__source.OriginPullRequestDiscoveryTrait>
          <strategyId>2</strategyId>
        </org.jenkinsci.plugins.github__branch__source.OriginPullRequestDiscoveryTrait>
        <org.jenkinsci.plugins.github__branch__source.ForkPullRequestDiscoveryTrait>
          <strategyId>2</strategyId>
          <trust class="org.jenkinsci.plugins.github_branch_source.ForkPullRequestDiscoveryTrait\$TrustPermission"/>
        </org.jenkinsci.plugins.github__branch__source.ForkPullRequestDiscoveryTrait>
      </traits>
    </org.jenkinsci.plugins.github__branch__source.GitHubSCMNavigator>
  </navigators>
  <projectFactories>
    <org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProjectFactory plugin="workflow-multibranch">
      <scriptPath>$org_jenkinsfile_path</scriptPath>
    </org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProjectFactory>
  </projectFactories>
  <buildStrategies/>
  <strategy class="jenkins.branch.DefaultBranchPropertyStrategy">
    <properties class="empty-list"/>
  </strategy>
</jenkins.branch.OrganizationFolder>
XML
)

create_jenkins_org_folder() {
  # Idempotency: skip if folder already exists
  if curl -sf -u "admin:$jenkins_initial_password" "$jenkins_url/job/$encoded_folder_name/api/json" > /dev/null 2>&1; then
    echo "Jenkins org folder '$org_folder_name' already exists, skipping"
    return 0
  fi

  crumb_json=$(curl -sf -u "admin:$jenkins_initial_password" "$jenkins_url/crumbIssuer/api/json") || return 1
  crumb=$(echo "$crumb_json" | jq -r '.crumb')
  crumb_field=$(echo "$crumb_json" | jq -r '.crumbRequestField')

  curl -sf -X POST "$jenkins_url/createItem?name=$encoded_folder_name" \
    -H "Content-Type: application/xml" \
    -H "$crumb_field: $crumb" \
    -u "admin:$jenkins_initial_password" \
    --data-binary "$org_folder_xml" || return 1
}

retry_command 'create_jenkins_org_folder'

# Trigger initial repo scan
scan_jenkins_org_folder() {
  crumb_json=$(curl -sf -u "admin:$jenkins_initial_password" "$jenkins_url/crumbIssuer/api/json") || return 1
  crumb=$(echo "$crumb_json" | jq -r '.crumb')
  crumb_field=$(echo "$crumb_json" | jq -r '.crumbRequestField')

  curl -sf -X POST "$jenkins_url/job/$encoded_folder_name/build" \
    -H "$crumb_field: $crumb" \
    -u "admin:$jenkins_initial_password" || return 1
}

retry_command 'scan_jenkins_org_folder'
