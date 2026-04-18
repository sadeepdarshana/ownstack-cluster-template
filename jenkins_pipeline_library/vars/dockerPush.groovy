def call(String applicationId) {
    def values = values()

    def sha = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
    def branch = env.BRANCH_NAME ?: sh(script: 'git rev-parse --abbrev-ref HEAD', returnStdout: true).trim()
    branch = branch.replaceAll('[^a-zA-Z0-9_.-]', '-')
    def tag = "${branch}-${sha}"

    def localImage = "${values.imageRepositoryProject}/${applicationId}:${tag}"
    def remoteImage = "${env.IMAGE_REGISTRY}/${localImage}"

    container('docker') {
        docker.withRegistry("https://${env.IMAGE_REGISTRY}", values.credentialsId as String) {
            echo "Tagging ${localImage} -> ${remoteImage}"
            sh "docker tag ${localImage} ${remoteImage}"
            echo "Pushing ${remoteImage}"
            sh "docker push ${remoteImage}"
        }
    }
}
