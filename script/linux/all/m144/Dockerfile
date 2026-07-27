FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        file \
        findutils \
        git \
        lsb-release \
        ninja-build \
        pkg-config \
        python-is-python3 \
        python3 \
        sudo \
        xz-utils \
        zip \
    && rm -rf /var/lib/apt/lists/*
