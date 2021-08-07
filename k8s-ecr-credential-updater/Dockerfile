ARG KUBECTL_IMAGE_TAG=1.20
ARG AWSCLI_IMAGE_TAG=latest

FROM bitnami/kubectl:${KUBECTL_IMAGE_TAG} as kubectl
FROM amazon/aws-cli:${AWSCLI_IMAGE_TAG}

COPY --from=kubectl /opt/bitnami/kubectl/bin/kubectl /usr/local/bin/kubectl
RUN yum install jq
COPY ecr-credential-updater.sh /

ENTRYPOINT [ "/bin/bash", "/ecr-credential-updater.sh" ]
