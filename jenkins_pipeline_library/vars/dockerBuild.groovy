def call(String applicationId) {
    def values = values()

    def sha = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
    def branch = env.BRANCH_NAME ?: sh(script: 'git rev-parse --abbrev-ref HEAD', returnStdout: true).trim()
    branch = branch.replaceAll('[^a-zA-Z0-9_.-]', '-')
    def tag = "${branch}-${sha}"
    def image_name_with_tag = "${values.imageRepositoryProject}/${applicationId}:${tag}"

    container('docker') {
        echo "Building ${image_name_with_tag}"
        // Build local image (without registry prefix), consistent with previous behavior
        docker.build(image_name_with_tag, "-f infrastructure/${applicationId}/Dockerfile .")
    }
}
