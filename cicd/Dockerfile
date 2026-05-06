# SPDX-License-Identifier: CC-BY-SA-4.0
# this is used for cicd

FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update
RUN apt-get install -y gperf flex bison build-essential clang tcl-dev libboost-dev autoconf wget pkg-config \
    libfl-dev zlibc zlib1g zlib1g-dev perl git ccache libgoogle-perftools-dev numactl \
    perl-doc python3 python3-pip python-is-python3 libreadline-dev cmake xz-utils expect
RUN python3 -V

COPY docker_files docker_files

# bleeding edge llvm, riscv llc
RUN git clone --filter=tree:0 https://github.com/hughperkins/llvm-project.git -b D122918-zfinx-from-sunshaoce && \
    cd llvm-project && \
    mkdir build && \
    cd build && \
    cmake -D EXPERIMENTAL_TARGETS_TO_BUILD:str=RISCV \
    -D LLVM_TARGETS_TO_BUILD:str=RISCV \
    -D CMAKE_BUILD_TYPE:STR=Release \
    -D LLVM_BUILD_RUNTIME:BOOL=OFF \
    -D LLVM_BUILD_RUNTIMES:BOOL=OFF \
    -D LLVM_BUILD_TOOLS:BOOL=OFF \
    -D LLVM_BUILD_UTILS:BOOL=OFF \
    -D LLVM_INCLUDE_BENCHMARKS:BOOL=OFF \
    -D LLVM_INCLUDE_DOCS:BOOL=OFF \
    -D LLVM_INCLUDE_EXAMPLES:BOOL=OFF \
    -D LLVM_INCLUDE_RUNTIMES:BOOL=OFF \
    -D LLVM_INCLUDE_TESTS:BOOL=OFF \
    -D LLVM_INCLUDE_UTILS:BOOL=OFF \
    ../llvm && \
    make -j $(nproc) llc && \
    cp bin/llc /usr/local/bin/llc-zfinx && \
    cd ../.. && \
    rm -Rf llvm-project

# clang and llvm 14, for clang
RUN wget https://apt.llvm.org/llvm-snapshot.gpg.key && \
    apt-key add llvm-snapshot.gpg.key && \
    cp -v docker_files/llvm-sources.list /etc/apt/sources.list.d/ && \
    apt-get update && \
    apt-get install -y clang-14 lldb-14 lld-14 libllvm14 llvm-14 llvm-14-dev llvm-14-runtime && \
    clang++-14 --version

# llvm 14.0.0
# RUN wget -q https://github.com/llvm/llvm-project/releases/download/llvmorg-14.0.0/clang+llvm-14.0.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz && \
#     tar -xf clang+llvm-14.0.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz && \
#     chown -R root:root clang+llvm-14.0.0-x86_64-linux-gnu-ubuntu-18.04 && \
#     mkdir -p /usr/local/opt && \
#     mv clang+llvm-14.0.0-x86_64-linux-gnu-ubuntu-18.04 /usr/local/opt/llvm-14.0.0 && \
#     rm clang+llvm-14.0.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz && \
#     /usr/local/opt/llvm-14.0.0/bin/clang++ --version

# iverilog 11.0
RUN wget ftp://ftp.icarus.com/pub/eda/verilog//v11/verilog-11.0.tar.gz && \
    tar -xzvf verilog-11.0.tar.gz && \
    cd verilog-11.0 && \
    ./configure && \
    make -j $(nproc) && \
    make install && \
    cd .. && \
    rm -Rf verilog-11.0

# from git
# RUN git clone https://github.com/hughperkins/iverilog.git && \
#     cd iverilog && \
#     git checkout hp/v11_0_vvp_so && \
#     sh autoconf.sh && \
#     ./configure && \
#     make -j $(nproc) && \
#     make install && \
#     iverilog -V && \
#     cd .. && \
#     rm -Rf iverilog

# yosys + nextpnr-ecp5 + prjtrellis (via OSS CAD Suite)
#
# Replaces the 2021-vintage `yosys-0.15.tar.gz` source build (closes #36).
# OSS CAD Suite ships yosys + nextpnr + prjtrellis (and verilator, iverilog,
# cocotb-ext) as one date-pinned tarball, which is what every production open-
# FPGA ECP5 reference (OrangeCrab, Trellis Board, ULX3S, Versa-ECP5, ECPIX-5,
# LiteX) actually uses. See docs/upstream-contributions/2026-05-06-yosys-ecp5.md
# (Stays #33) for the day-1 recon that surfaced this upgrade.
#
# Pinned to the 2026-05-06 nightly. Bump the date when refreshing — keep the
# pin so the image is reproducible. yosys version inside this build: v0.64
# (released 2026-04-09).
ARG OSS_CAD_SUITE_DATE=2026-05-06
ARG OSS_CAD_SUITE_DATE_NODASH=20260506
RUN wget -q "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${OSS_CAD_SUITE_DATE}/oss-cad-suite-linux-x64-${OSS_CAD_SUITE_DATE_NODASH}.tgz" -O /tmp/oss-cad-suite.tgz && \
    mkdir -p /opt && \
    tar -xzf /tmp/oss-cad-suite.tgz -C /opt && \
    rm /tmp/oss-cad-suite.tgz && \
    /opt/oss-cad-suite/bin/yosys -V
ENV PATH="/opt/oss-cad-suite/bin:${PATH}"

# verilator
RUN git clone https://github.com/verilator/verilator && \
    cd verilator && \
    git checkout v4.218 && \
    autoconf && \
    ./configure && \
    make -j $(nproc) && \
    make install && \
    cd .. && \
    rm -Rf verilator
