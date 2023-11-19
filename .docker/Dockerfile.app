# Sets the base image for subsequent instructions
ARG ARG_BUILD_FROM="nvcr.io/nvidia/cuda:11.8.0-devel-ubuntu22.04"
FROM $ARG_BUILD_FROM as base

# Sets labels for the image
LABEL org.opencontainers.image.source="https://github.com/entelecheia/ollama-container"
LABEL org.opencontainers.image.description="Container images for running Ollama models on the container platforms."
LABEL org.opencontainers.image.licenses="MIT"

ARG TARGETARCH
ARG GOFLAGS="'-ldflags=-w -s'"
# Sets the time zone within the container
ENV TZ="Asia/Seoul"

RUN apt-get update && apt-get install -y git build-essential cmake
ADD https://dl.google.com/go/go1.21.3.linux-$TARGETARCH.tar.gz /tmp/go1.21.3.tar.gz
RUN mkdir -p /usr/local && tar xz -C /usr/local </tmp/go1.21.3.tar.gz

# Clones the repository into the container
RUN git clone https://github.com/jmorganca/ollama.git /go/src/github.com/jmorganca/ollama
# Sets the working directory
WORKDIR /go/src/github.com/jmorganca/ollama
ENV GOARCH=$TARGETARCH
ENV GOFLAGS=$GOFLAGS
RUN /usr/local/go/bin/go generate ./... \
    && /usr/local/go/bin/go build .

FROM nvidia/cuda:11.8.0-runtime-ubuntu22.04 as app

# Setting this argument prevents interactive prompts during the build process
ARG DEBIAN_FRONTEND=noninteractive
# Updates the image and installs necessary packages
RUN apt-get update --fix-missing \
    && apt-get install -y curl wget jq sudo gosu ca-certificates \
    # Cleans up unnecessary packages to reduce image size
    && apt-get autoremove -y \
    && apt-get clean -y
# Copies the binary from the base image into the app image
COPY --from=base /go/src/github.com/jmorganca/ollama/ollama /bin/ollama

# Copies scripts from host into the image
COPY ./.docker/scripts/ ./scripts/

# Setting ARGs and ENVs for user creation and workspace setup
ARG ARG_USERNAME="app"
ARG ARG_USER_UID=9001
ARG ARG_USER_GID=$ARG_USER_UID
ARG ARG_WORKSPACE_ROOT="/workspace"
ENV USERNAME $ARG_USERNAME
ENV USER_UID $ARG_USER_UID
ENV USER_GID $ARG_USER_GID
ENV WORKSPACE_ROOT $ARG_WORKSPACE_ROOT

# Creates a non-root user with sudo privileges
# check if user exists and if not, create user
RUN if id -u $USERNAME >/dev/null 2>&1; then \
    echo "User exists"; \
    else \
    groupadd --gid $USER_GID $USERNAME && \
    adduser --uid $USER_UID --gid $USER_GID --force-badname --disabled-password --gecos "" $USERNAME && \
    echo "$USERNAME:$USERNAME" | chpasswd && \
    adduser $USERNAME sudo && \
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME && \
    chmod 0440 /etc/sudoers.d/$USERNAME; \
    fi


WORKDIR $WORKSPACE_ROOT
# Copies scripts from host into the image
COPY ./.docker/scripts/ ./scripts/

# Changes ownership of the workspace to the non-root user
RUN chown -R $USERNAME:$USERNAME $WORKSPACE_ROOT
RUN chmod +x "$WORKSPACE_ROOT/scripts/entrypoint.sh"

EXPOSE 11434
ENV OLLAMA_HOST 0.0.0.0
ENTRYPOINT ["$APP_INSTALL_ROOT/scripts/entrypoint.sh"]