FROM bitnami/kubectl: as kubectl
FROM amazon/aws-cli

RUN yum install jq

ENTRYPOINT [ "/bin/bash", "-x", "/ecr-credential-updater.sh" ]
