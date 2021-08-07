ARG KUBECTL_IMAGE_TAG=1.20
ARG AWSCLI_IMAGE_TAG=latest

FROM bitnami/kubectl:${KUBECTL_IMAGE_TAG} as kubectl
FROM amazon/aws-cli:${AWSCLI_IMAGE_TAG}

RUN yum install -y jq
COPY ecr-credential-updater.sh /

ENTRYPOINT [ "/bin/bash", "/ecr-credential-updater.sh" ]
