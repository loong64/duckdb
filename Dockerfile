FROM ghcr.io/loong64/manylinux_2_38_loongarch64 AS builder

RUN set -ex && \
    yum install -y ccache perl-IPC-Cmd gcc-c++ && \
    yum clean all

ARG RUNNER_ARCH
RUN set -ex && \
    curl -sSL https://github.com/loong64/static-clang-build/raw/refs/heads/main/manylinux-install-static-clang.sh | bash

WORKDIR /opt/duckdb

ARG VERSION
RUN set -ex && \
    git clone --depth=1 -b ${VERSION} https://github.com/duckdb/duckdb /opt/duckdb && \
    curl -sSL https://github.com/loong64/duckdb/raw/refs/heads/main/patch_loong64.patch | git apply

ENV CC="/opt/clang/bin/clang"
ENV CXX="/opt/clang/bin/clang++"
ENV LDFLAGS="-fuse-ld=lld"

FROM builder AS build-linux-release
ARG TARGETARCH

ARG CMAKE_BUILD_PARALLEL_LEVEL=2
ARG EXTENSION_CONFIGS="/opt/duckdb/.github/config/bundled_extensions.cmake"
ARG ENABLE_EXTENSION_AUTOLOADING=1
ARG ENABLE_EXTENSION_AUTOINSTALL=1
ARG BUILD_BENCHMARK=1
ARG FORCE_WARN_UNUSED=1
ARG EXPORT_DYNAMIC_SYMBOLS=1

RUN --mount=type=cache,target=/root/.cache \
    set -ex && \
    export DUCKDB_PLATFORM=linux_${TARGETARCH} && \
    make && \
    ./build/release/duckdb -c "PRAGMA platform;"

RUN set -ex && \
    python3 scripts/amalgamation.py && \
    zip -j duckdb_cli-linux-${TARGETARCH}.zip build/release/duckdb && \
    gzip -9 -k -n -c build/release/duckdb > duckdb_cli-linux-${TARGETARCH}.gz && \
    zip -j libduckdb-linux-${TARGETARCH}.zip build/release/src/libduckdb*.* src/amalgamation/duckdb.hpp src/include/duckdb.h && \
    ./scripts/upload-assets-to-staging.sh github_release libduckdb-linux-${TARGETARCH}.zip duckdb_cli-linux-${TARGETARCH}.zip duckdb_cli-linux-${TARGETARCH}.gz && \
    mkdir -p /dist && \
    cp *.{zip,gz} /dist

# RUN set -ex && \
#     python3 scripts/run_tests_one_by_one.py build/release/test/unittest "*" --time_execution && \
#     ./build/release/test/unittest --select-tag release && \
#     python3 -m pytest tools/shell/tests --shell-binary build/release/duckdb && \
#     build/release/benchmark/benchmark_runner benchmark/micro/update/update_with_join.benchmark && \
#     build/release/duckdb -c "COPY (SELECT 42) TO '/dev/stdout' (FORMAT PARQUET)" | cat

FROM builder AS build-linux-libs
ARG TARGETARCH

ARG CMAKE_BUILD_PARALLEL_LEVEL=2
ARG EXTENSION_CONFIGS="/opt/duckdb/.github/config/bundled_extensions.cmake"
ARG ENABLE_EXTENSION_AUTOLOADING=1
ARG ENABLE_EXTENSION_AUTOINSTALL=1
ARG BUILD_BENCHMARK=1
ARG FORCE_WARN_UNUSED=1
ARG EXPORT_DYNAMIC_SYMBOLS=1

RUN --mount=type=cache,target=/root/.cache \
    set -ex && \
    export DUCKDB_PLATFORM=linux_${TARGETARCH} && \
    make gather-libs && \
    ./build/release/duckdb -c "PRAGMA platform;"

RUN set -ex && \
    python3 scripts/amalgamation.py && \
    zip -r -j static-libs-linux-${TARGETARCH}.zip src/include/duckdb.h build/release/libs/ && \
    mkdir -p /dist && \
    cp *.zip /dist

FROM scratch
COPY --from=build-linux-release /dist /dist
COPY --from=build-linux-libs /dist /dist
