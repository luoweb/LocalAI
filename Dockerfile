ARG IMAGE_TYPE=extras
ARG BASE_IMAGE=ubuntu:22.04
ARG GRPC_BASE_IMAGE=${BASE_IMAGE}

# The requirements-core target is common to all images.  It should not be placed in requirements-core unless every single build will use it.
FROM ${BASE_IMAGE} AS requirements-core

USER root

ARG GO_VERSION=1.21.7
ARG TARGETARCH
ARG TARGETVARIANT

ENV DEBIAN_FRONTEND=noninteractive
ENV EXTERNAL_GRPC_BACKENDS="coqui:/build/backend/python/coqui/run.sh,huggingface-embeddings:/build/backend/python/sentencetransformers/run.sh,petals:/build/backend/python/petals/run.sh,transformers:/build/backend/python/transformers/run.sh,sentencetransformers:/build/backend/python/sentencetransformers/run.sh,rerankers:/build/backend/python/rerankers/run.sh,autogptq:/build/backend/python/autogptq/run.sh,bark:/build/backend/python/bark/run.sh,diffusers:/build/backend/python/diffusers/run.sh,exllama:/build/backend/python/exllama/run.sh,vall-e-x:/build/backend/python/vall-e-x/run.sh,vllm:/build/backend/python/vllm/run.sh,mamba:/build/backend/python/mamba/run.sh,exllama2:/build/backend/python/exllama2/run.sh,transformers-musicgen:/build/backend/python/transformers-musicgen/run.sh,parler-tts:/build/backend/python/parler-tts/run.sh"

# ARG GO_TAGS="stablediffusion tinydream tts"
ARG GO_TAGS="tts"

RUN sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list  && \
    sed -i 's/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list  &&  \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        ccache \
        ca-certificates \
        cmake \
        curl \
        git \
        python3-pip \
        # python-is-python3 \
        unzip && \
    apt-get clean && \
    which python3 pip3 && \
    # ln -s /usr/bin/pip3 /usr/bin/pip && \
    # ln -s /usr/bin/python3 /usr/bin/python && \
    rm -rf /var/lib/apt/lists/* && \
    pip3 install --no-cache-dir pip --upgrade && \
    exit 0

# Install Go
RUN curl -L -s https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz | tar -C /usr/local -xz
ENV PATH $PATH:/root/go/bin:/usr/local/go/bin

# Install grpc compilers
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@latest && \
    go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

# Install grpcio-tools (the version in 22.04 is too old)
RUN pip3 install --user grpcio-tools

COPY --chmod=644 custom-ca-certs/* /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Use the variables in subsequent instructions
RUN echo "Target Architecture: $TARGETARCH"
RUN echo "Target Variant: $TARGETVARIANT"

# Cuda
ENV PATH /usr/local/cuda/bin:${PATH}

# HipBLAS requirements
ENV PATH /opt/rocm/bin:${PATH}

# OpenBLAS requirements and stable diffusion
RUN sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        libopenblas-dev \
        libopencv-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set up OpenCV
RUN ln -s /usr/include/opencv4/opencv2 /usr/include/opencv2

WORKDIR /build

RUN test -n "$TARGETARCH" \
    || (echo 'warn: missing $TARGETARCH, either set this `ARG` manually, or run using `docker buildkit`')

###################################
###################################

# The requirements-extras target is for any builds with IMAGE_TYPE=extras. It should not be placed in this target unless every IMAGE_TYPE=extras build will use it
FROM requirements-core AS requirements-extras

RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.cargo/bin:${PATH}"

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

RUN if [ "${BUILD_TYPE}" = "cublas" ] && [ "${CUDA_MAJOR_VERSION}" = "11" ] || [ "${CUDA_MAJOR_VERSION}" = "12" ]; then \
    sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        espeak-ng \
        espeak \
        python3-dev \
        python3-venv && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN if [ "${BUILD_TYPE}" = "cublas" ] && [ "${CUDA_MAJOR_VERSION}" = "10" ] && [ "${CUDA_MINOR_VERSION}" = "1" ]; then \
    sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    espeak-ng \
    espeak \
    python3-dev \
    python3-venv && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
###################################
###################################

# The requirements-drivers target is for BUILD_TYPE specific items.  If you need to install something specific to CUDA, or specific to ROCM, it goes here.
# This target will be built on top of requirements-core or requirements-extras as retermined by the IMAGE_TYPE build-arg
FROM requirements-${IMAGE_TYPE} AS requirements-drivers

ARG BUILD_TYPE
ARG CUDA_MAJOR_VERSION=11
ARG CUDA_MINOR_VERSION=7

ENV BUILD_TYPE=${BUILD_TYPE}

# CuBLAS requirements
RUN if [ "${BUILD_TYPE}" = "cublas" ] && [ "${CUDA_MAJOR_VERSION}" = "11" ] || [ "${CUDA_MAJOR_VERSION}" = "12" ]; then \
        sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list && \
        sed -i 's/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list && \
        apt-get update && \
        apt-get install -y  --no-install-recommends \
            software-properties-common && \
        curl -O https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-keyring_1.1-1_all.deb && \
        dpkg -i cuda-keyring_1.1-1_all.deb && \
        rm -f cuda-keyring_1.1-1_all.deb && \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            cuda-nvcc-${CUDA_MAJOR_VERSION}-${CUDA_MINOR_VERSION} \
            libcurand-dev-${CUDA_MAJOR_VERSION}-${CUDA_MINOR_VERSION} \
            libcublas-dev-${CUDA_MAJOR_VERSION}-${CUDA_MINOR_VERSION} \
            libcusparse-dev-${CUDA_MAJOR_VERSION}-${CUDA_MINOR_VERSION} \
            libcusolver-dev-${CUDA_MAJOR_VERSION}-${CUDA_MINOR_VERSION} && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/* \
    ; fi

RUN if [ "${BUILD_TYPE}" = "cublas" ] && [ "${CUDA_MAJOR_VERSION}" = "10" ] && [ "${CUDA_MINOR_VERSION}" = "1" ]; then \
    sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y  --no-install-recommends \
    software-properties-common dirmngr gpg-agent && \
    curl -O https://developer.download.nvidia.cn/compute/cuda/repos/ubuntu1810/x86_64/cuda-repo-ubuntu1810_10.1.168-1_amd64.deb && \
    dpkg -i cuda-repo-ubuntu1810_10.1.168-1_amd64.deb && \
    rm -f cuda-repo-ubuntu1810_10.1.168-1_amd64.deb && \
    # cp /var/cuda-repo-ubuntu1810/cuda-*-keyring.gpg /usr/share/keyrings/ && \
    # apt-key adv --fetch-keys http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1810/x86_64/7fa2af80.pub
    apt-key adv --fetch-keys http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1810/x86_64/7fa2af80.pub && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    cuda-nvcc-${CUDA_MAJOR_VERSION}-${CUDA_MINOR_VERSION} \
    libcublas-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* \
    ; fi
    
# If we are building with clblas support, we need the libraries for the builds
RUN if [ "${BUILD_TYPE}" = "clblas" ]; then \
        sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list && \
        sed -i 's/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list && \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            libclblast-dev && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/* \
    ; fi

RUN if [ "${BUILD_TYPE}" = "hipblas" ]; then \
        sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list && \
        sed -i 's/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list && \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            hipblas-dev \
            rocblas-dev && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/* && \
        # I have no idea why, but the ROCM lib packages don't trigger ldconfig after they install, which results in local-ai and others not being able
        # to locate the libraries. We run ldconfig ourselves to work around this packaging deficiency
        ldconfig \
    ; fi

###################################
###################################

# The grpc target does one thing, it builds and installs GRPC.  This is in it's own layer so that it can be effectively cached by CI.
# You probably don't need to change anything here, and if you do, make sure that CI is adjusted so that the cache continues to work.
FROM ${GRPC_BASE_IMAGE} AS grpc

# This is a bit of a hack, but it's required in order to be able to effectively cache this layer in CI
ARG GRPC_MAKEFLAGS="-j4 -Otarget"
ARG GRPC_VERSION=v1.58.0

ENV MAKEFLAGS=${GRPC_MAKEFLAGS}

WORKDIR /build

RUN sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        build-essential \
        wget \
        # cmake \
        git && \
    wget https://cmake.org/files/v3.16/cmake-3.16.9-Linux-x86_64.sh && chmod +x *.sh && \
    ./cmake-3.16.9-Linux-x86_64.sh --skip-license --prefix=/usr/local/ && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# We install GRPC to a different prefix here so that we can copy in only the build artifacts later
# saves several hundred MB on the final docker image size vs copying in the entire GRPC source tree
# and running make install in the target container
RUN git clone --recurse-submodules --jobs 4 -b ${GRPC_VERSION} --depth 1 --shallow-submodules https://github.com/grpc/grpc && \
    mkdir -p /build/grpc/cmake/build && \
    cd /build/grpc/cmake/build && \
    cmake -DgRPC_INSTALL=ON -DgRPC_BUILD_TESTS=OFF -DCMAKE_INSTALL_PREFIX:PATH=/opt/grpc ../.. && \
    make && \
    make install && \
    rm -rf /build

###################################
###################################

# The builder target compiles LocalAI. This target is not the target that will be uploaded to the registry.
# Adjustments to the build process should likely be made here.
FROM requirements-drivers AS builder

# ARG GO_TAGS="stablediffusion tts"
ARG GO_TAGS="tts"
ARG GRPC_BACKENDS
ARG MAKEFLAGS

ENV GRPC_BACKENDS=${GRPC_BACKENDS}
ENV GO_TAGS=${GO_TAGS}
ENV MAKEFLAGS=${MAKEFLAGS}
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV NVIDIA_REQUIRE_CUDA="cuda>=${CUDA_MAJOR_VERSION}.0"
ENV NVIDIA_VISIBLE_DEVICES=all

WORKDIR /build

COPY . .
COPY .git .
RUN echo "GO_TAGS: $GO_TAGS"

RUN make prepare

# We need protoc installed, and the version in 22.04 is too old.  We will create one as part installing the GRPC build below
# but that will also being in a newer version of absl which stablediffusion cannot compile with.  This version of protoc is only
# here so that we can generate the grpc code for the stablediffusion build
RUN curl -L -s https://github.com/protocolbuffers/protobuf/releases/download/v26.1/protoc-26.1-linux-x86_64.zip -o protoc.zip && \
    unzip -j -d /usr/local/bin protoc.zip bin/protoc && \
    rm protoc.zip && \
    ls -l /usr/local && \
    find /usr/local/ -name libcu*.so

# stablediffusion does not tolerate a newer version of abseil, build it first
# RUN GRPC_BACKENDS=backend-assets/grpc/stablediffusion make build

# Install the pre-built GRPC
COPY --from=grpc /opt/grpc /usr/local

# Rebuild with defaults backends
WORKDIR /build
RUN make build

RUN if [ ! -d "/build/sources/go-piper/piper-phonemize/pi/lib/" ]; then \
        mkdir -p /build/sources/go-piper/piper-phonemize/pi/lib/ \
        touch /build/sources/go-piper/piper-phonemize/pi/lib/keep \
    ; fi

###################################
###################################

# This is the final target. The result of this target will be the image uploaded to the registry.
# If you cannot find a more suitable place for an addition, this layer is a suitable place for it.
FROM requirements-drivers

ARG FFMPEG
ARG BUILD_TYPE
ARG TARGETARCH
ARG IMAGE_TYPE=extras
ARG EXTRA_BACKENDS
ARG MAKEFLAGS

ENV BUILD_TYPE=${BUILD_TYPE}
ENV REBUILD=false
ENV HEALTHCHECK_ENDPOINT=http://localhost:8080/readyz
ENV MAKEFLAGS=${MAKEFLAGS}

ARG CUDA_MAJOR_VERSION=11
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV NVIDIA_REQUIRE_CUDA="cuda>=${CUDA_MAJOR_VERSION}.0"
ENV NVIDIA_VISIBLE_DEVICES=all

# Add FFmpeg
RUN if [ "${FFMPEG}" = "true" ]; then \
        sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list && \
        sed -i 's/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list && \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            ffmpeg && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/* \
    ; fi

WORKDIR /build

# we start fresh & re-copy all assets because `make build` does not clean up nicely after itself
# so when `entrypoint.sh` runs `make build` again (which it does by default), the build would fail
# see https://github.com/go-skynet/LocalAI/pull/658#discussion_r1241971626 and
# https://github.com/go-skynet/LocalAI/pull/434
COPY . .

COPY --from=builder /build/sources ./sources/
COPY --from=grpc /opt/grpc /usr/local

RUN make prepare-sources

# Copy the binary
COPY --from=builder /build/local-ai ./

# Copy shared libraries for piper
COPY --from=builder /build/sources/go-piper/piper-phonemize/pi/lib/* /usr/lib/

# do not let stablediffusion rebuild (requires an older version of absl)
COPY --from=builder /build/backend-assets/grpc/stablediffusion ./backend-assets/grpc/stablediffusion

# Change the shell to bash so we can use [[ tests below
SHELL ["/bin/bash", "-c"]
# We try to strike a balance between individual layer size (as that affects total push time) and total image size
# Splitting the backends into more groups with fewer items results in a larger image, but a smaller size for the largest layer
# Splitting the backends into fewer groups with more items results in a smaller image, but a larger size for the largest layer

RUN if [[ ( "${EXTRA_BACKENDS}" =~ "coqui" || -z "${EXTRA_BACKENDS}" ) && "$IMAGE_TYPE" == "extras" ]]; then \
        make -C backend/python/coqui \
    ; fi && \
    if [[ ( "${EXTRA_BACKENDS}" =~ "parler-tts" || -z "${EXTRA_BACKENDS}" ) && "$IMAGE_TYPE" == "extras" ]]; then \
        make -C backend/python/parler-tts \
    ; fi && \
    if [[ ( "${EXTRA_BACKENDS}" =~ "diffusers" || -z "${EXTRA_BACKENDS}" ) && "$IMAGE_TYPE" == "extras" ]]; then \
        make -C backend/python/diffusers \
    ; fi && \
    if [[ ( "${EXTRA_BACKENDS}" =~ "transformers-musicgen" || -z "${EXTRA_BACKENDS}" ) && "$IMAGE_TYPE" == "extras" ]]; then \
        make -C backend/python/transformers-musicgen \
    ; fi && \
    if [[ ( "${EXTRA_BACKENDS}" =~ "exllama1" || -z "${EXTRA_BACKENDS}" ) && "$IMAGE_TYPE" == "extras" ]]; then \
        make -C backend/python/exllama \
    ; fi

RUN if [[ ( "${EXTRA_BACKENDS}" =~ "vall-e-x" || -z "${EXTRA_BACKENDS}" ) && "$IMAGE_TYPE" == "extras" ]]; then \
        make -C backend/python/vall-e-x \
    ; fi && \
    if [[ ( "${EXTRA_BACKENDS}" =~ "petals" || -z "${EXTRA_BACKENDS}" ) && "$IMAGE_TYPE" == "extras" ]]; then \
        make -C backend/python/petals \
    ; fi && \
    if [[ ( "${EXTRA_BACKENDS}" =~ "sentencetransformers" || -z "${EXTRA_BACKENDS}" ) && "$IMAGE_TYPE" == "extras" ]]; then \
        make -C backend/python/sentencetransformers \
    ; fi && \
    if [[ ( "${EXTRA_BACKENDS}" =~ "exllama2" || -z "${EXTRA_BACKENDS}" ) && "$IMAGE_TYPE" == "extras" ]]; then \
        make -C backend/python/exllama2 \
    ; fi && \
    if [[ ( "${EXTRA_BACKENDS}" =~ "transformers" || -z "${EXTRA_BACKENDS}" ) && "$IMAGE_TYPE" == "extras" ]]; then \
        make -C backend/python/transformers \
    ; fi

RUN if [[ ( "${EXTRA_BACKENDS}" =~ "vllm" || -z "${EXTRA_BACKENDS}" ) && "$IMAGE_TYPE" == "extras" ]]; then \
        make -C backend/python/vllm \
    ; fi && \
    if [[ ( "${EXTRA_BACKENDS}" =~ "autogptq" || -z "${EXTRA_BACKENDS}" ) && "$IMAGE_TYPE" == "extras" ]]; then \
        make -C backend/python/autogptq \
    ; fi && \
    if [[ ( "${EXTRA_BACKENDS}" =~ "bark" || -z "${EXTRA_BACKENDS}" ) && "$IMAGE_TYPE" == "extras" ]]; then \
        make -C backend/python/bark \
    ; fi && \
    if [[ ( "${EXTRA_BACKENDS}" =~ "rerankers" || -z "${EXTRA_BACKENDS}" ) && "$IMAGE_TYPE" == "extras" ]]; then \
        make -C backend/python/rerankers \
    ; fi && \
    if [[ ( "${EXTRA_BACKENDS}" =~ "mamba" || -z "${EXTRA_BACKENDS}" ) && "$IMAGE_TYPE" == "extras" ]]; then \
        make -C backend/python/mamba \
    ; fi

# Make sure the models directory exists
RUN mkdir -p /build/models

# Define the health check command
HEALTHCHECK --interval=1m --timeout=10m --retries=10 \
  CMD curl -f ${HEALTHCHECK_ENDPOINT} || exit 1
  
VOLUME /build/models
EXPOSE 8080
ENTRYPOINT [ "/build/entrypoint.sh" ]
