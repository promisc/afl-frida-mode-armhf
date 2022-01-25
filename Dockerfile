FROM ghcr.io/promisc/frida-toolchain-linux-armhf:5b9d256f-glibc_2_17 as frida-builder

# Deps from https://github.com/frida/frida-ci/blob/master/images/worker-ubuntu-20.04-x86_64/Dockerfile
USER root
WORKDIR /root
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential \
        coreutils \
        curl \
        file \
        git \
        lib32stdc++-9-dev \
        libc6-dev-i386 \
        libgl1-mesa-dev \
        locales \
        nodejs \
        npm \
        p7zip \
        python3-dev \
        python3-pip \
        python3-requests \
        python3-setuptools \
    && rm -rf /var/lib/apt/lists/*

# Build Frida gum
USER builder
WORKDIR /home/builder
RUN git clone --recurse-submodules https://github.com/frida/frida
WORKDIR /home/builder/frida
# This commit is roughly  15.1.14++ as head isn't working, neither is 15.1.13
RUN git checkout 5b9d256f645a2c76ccc2941ba7d1e67370143da0 \
    && git submodule update \
    && sed -i 's,FRIDA_V8 ?= auto,FRIDA_V8 ?= disabled,' config.mk \
    && sed -i 's,host_arch_flags="-march=armv7-a",host_arch_flags="-march=armv7-a -mfloat-abi=hard -mfpu=vfpv3-d16",g' releng/setup-env.sh \
    && mkdir -p build \
    && mv /home/builder/toolchain-linux-armhf.tar.bz2 /home/builder/frida/build/ \
    && mv /home/builder/sdk-linux-armhf.tar.bz2 /home/builder/frida/build/
ENV FRIDA_HOST=linux-armhf
RUN make gum-linux-armhf

# Get dev branch of AFL++
WORKDIR /home/builder
RUN git clone https://github.com/AFLplusplus/AFLplusplus.git
WORKDIR /home/builder/AFLplusplus
RUN git checkout dev

# Not sure if libunwind-*.a is built in 15.1.14++
# arm-linux-gnueabihf-g++: error: /home/builder/AFLplusplus/frida_mode/build/frida-source/build/sdk-linux-armhf/lib/libunwind-*.a: No such file or directory
RUN sed -i '/libunwind-/d' frida_mode/GNUmakefile

# By providing a pre built frida-source this is used instead of the GitHub release
RUN mkdir frida_mode/build && ln -s /home/builder/frida /home/builder/AFLplusplus/frida_mode/build/frida-source

# Don't want to build qemu-mode etc, just frida-mode
COPY --chown=builder:builder make-patch /home/builder/AFLplusplus/make-patch
RUN cat make-patch >> /home/builder/AFLplusplus/GNUmakefile

# Build afl-fuzz and afl-frida-trace.so
RUN CC=arm-linux-gnueabihf-gcc CXX=arm-linux-gnueabihf-g++ \
    make frida-only AFL_NO_X86=1 ARCH=armhf HOST_CC=/usr/bin/gcc HOST_CXX=/usr/bin/g++ FRIDA_SOURCE=1
