# staging: for building go app (PreferencesMS)
FROM golang:1.13.7 as builder

ARG MSNAME="preferences_ms"
ENV MS_NAME=${MSNAME}

# Create required directories for MS
RUN mkdir -p /${MS_NAME}/internal_interfaces/ /${MS_NAME}/bin/ /${MS_NAME}/pkg/ /${MS_NAME}/src/user_preferences

# set environment variable for GO project
ENV GOPATH="/${MS_NAME}"
ENV GOBIN="/${MS_NAME}/bin"
ENV JAVA_BIN="/usr/local/jre1.8.0_171/bin"
ENV JAVA_HOME="/usr/local/jre1.8.0_171"
ENV PATH=$PATH:$GOBIN:$JAVA_BIN:$JAVA_HOME

# /tmp directory for downloading dependencies 
RUN mkdir -p /tmp

# install required tools for building go application (PreferencesMS)
RUN apt-get update
RUN apt-get -y install unzip wget python-pip python-dev build-essential
RUN apt-get clean

# install java for running ccm for go test
RUN mkdir -p /tmp/java && \
    wget -O jre-8u171-linux-x64.tar.gz http://javadl.oracle.com/webapps/download/AutoDL?BundleId=233162_512cd62ec5174c3487ac17c61aaa89e8 && \
    tar -C /usr/local -xzf jre-8u171-linux-x64.tar.gz    

#Install ccm and its dependencies (required for unit testing)
RUN pip install --upgrade pip
RUN pip install --user cql PyYAML six
RUN mkdir /Cassandra/
RUN cd /Cassandra && git clone https://github.com/pcmanus/ccm.git && cd ccm && ./setup.py install --user

# Create ccm test cluster
RUN ls /Cassandra
RUN cd /Cassandra/ccm && ./ccm create test -v 3.11.2

# Download protoc compiler
ENV PROTOC_VERSION="3.11.4"
RUN wget https://github.com/google/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-x86_64.zip
RUN unzip protoc-${PROTOC_VERSION}-linux-x86_64.zip -d protoc3
RUN mv protoc3/bin/* /usr/local/bin/
RUN mv protoc3/include/* /usr/local/include/

# Download protoc-gen-go
RUN go get -v github.com/golang/protobuf/protoc-gen-go
RUN go get -v github.com/grpc-ecosystem/grpc-gateway/protoc-gen-openapiv2

# Download golangci-lint
ENV GOLANG_CI_LINT_VERSION="1.21.0"
RUN wget -O - -q https://install.goreleaser.com/github.com/golangci/golangci-lint.sh | sh -s v${GOLANG_CI_LINT_VERSION}

WORKDIR /${MS_NAME}/

# SSH Config for accessing gitlabe2
COPY .ssh /root/.ssh/
RUN chmod 400 /root/.ssh/id_rsa*
RUN ls $HOME/.ssh/

RUN git config --global http.sslVerify false
RUN git config --global url."git@gitlabe2.ext.net.nokia.com:".insteadOf "https://gitlabe2.ext.net.nokia.com/"
RUN git config -l --global

# Copy all source files
COPY ./src ./src

# Cache dependencies
RUN cd ./src/user_preferences && go mod download && cd ../../

## Download Build Tool
# For Default Installation to ./bin with debug logging
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d

# For Installation To /usr/local/bin for userwide access with debug logging
# May require sudo sh
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

# Copy interface depedencies
COPY ./internal_interfaces/ ./src/internal_interfaces/

# Build the go app (preferences_ms)
ARG NOCACHE=2
RUN cd ./src/user_preferences && make all

# Removing pkg folder as it causes permission issue in jenkins
RUN rm -rf ./pkg

# Build preferences_ms image
FROM alpine:3.11.5

ARG MSNAME="preferences_ms"
ENV MS_NAME=${MSNAME}
ENV USER_PREFERENCES_PROP=/etc/user-preferences-properties/user-preferences.properties

# Link required libs
# https://stackoverflow.com/questions/36279253/go-compiled-binary-wont-run-in-an-alpine-docker-container-on-ubuntu-host
RUN mkdir /lib64
RUN ln -s /lib/libc.musl-x86_64.so.1 /lib64/ld-linux-x86-64.so.2

#copy json files
RUN mkdir  -p /etc/myconf/assets/
RUN mkdir  -p /migrations/

# Expose port
EXPOSE 55008 

# Copy preferences_ms binary
COPY --from=builder /${MS_NAME}/bin/user_preferences .
COPY --from=builder /${MS_NAME}/src/user_preferences/features/jsonFileReader/json/ /etc/myconf/assets/
COPY --from=builder /${MS_NAME}/src/user_preferences/migrations/  /migrations/

# Run preferences_ms binary
CMD ./user_preferences
