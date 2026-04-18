def call() {
    [
            credentialsId : 'harbor-robot',
            containers    : [ docker: 'docker:24', helm: 'dtzar/helm-kubectl' ],
            imageRepositoryProject : 'product'
    ]
}