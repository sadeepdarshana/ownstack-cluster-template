def call() {
    def cfg = values()
    def containers = cfg.containers as Map<String,String>
    return """\
apiVersion: v1
kind: Pod
spec:
  volumes:
  - name: dockersock
    hostPath:
      path: /var/run/docker.sock
      type: Socket
  containers:
${containers.collect { name, image -> """\
  - name: ${name}
    image: ${image}
    command:
      - cat
    tty: true
    volumeMounts:
    - name: dockersock
      mountPath: /var/run/docker.sock"""}.join('\n')}
"""
}