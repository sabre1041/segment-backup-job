FROM registry.redhat.io/openshift4/ose-cli-artifacts@sha256:9ac35a99e98e86fe942450c84c3fa78058401e74b5d5f3b61550ccd7492cefcd AS build-env

WORKDIR /tmp

RUN curl -sL https://github.com/jqlang/jq/releases/download/jq-1.6/jq-linux64 -o /tmp/jq && chmod 755 /tmp/jq

FROM registry.redhat.io/ubi9/python-311@sha256:944fe5d61deb208b58dbb222bbd9013231511f15ad67b193f2717ed7da8ef97b

LABEL description="This image provides a data collection service for segment"
LABEL io.k8s.description="This image provides a data collection service for segment"
LABEL io.k8s.display-name="segment collection"
LABEL io.openshift.tags="segment,segment-collection"
LABEL summary="Provides the segment data collection service"
LABEL com.redhat.component="segment-collection"

USER 0

WORKDIR /opt/app-root/src/

COPY . .
COPY --from=build-env /usr/bin/oc /usr/local/bin/oc
COPY --from=build-env /tmp/jq /usr/local/bin/jq

RUN pip install -U pip && pip install -r /opt/app-root/src/requirements.txt --force-reinstall

USER 1001