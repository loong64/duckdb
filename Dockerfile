FROM ghcr.io/loong64/manylinux_2_38_loongarch64

RUN set -ex && \
    yum install -y perl-IPC-Cmd gcc-c++ && \
    yum clean all

ARG RUNNER_ARCH
RUN set -ex && \
    curl -sSL https://github.com/loong64/static-clang-build/raw/refs/heads/main/manylinux-install-static-clang.sh | bash

ARG WORKDIR=/opt/duckdb
ARG VERSION
RUN set -ex && \
    git clone --depth=1 -b ${VERSION} https://github.com/duckdb/duckdb ${WORKDIR}

ENV PATH=/opt/clang/bin:$PATH
WORKDIR ${WORKDIR}
RUN set -ex && \
    make -j$(nproc) && \
    ./build/release/duckdb -c "PRAGMA platform;"

RUN set -ex && \
    python3 scripts/amalgamation.py && \
    zip -j duckdb_cli-linux-loong64.zip build/release/duckdb && \
    gzip -9 -k -n -c build/release/duckdb > duckdb_cli-linux-loong64.gz && \
    zip -j libduckdb-linux-loong64.zip build/release/src/libduckdb*.* src/amalgamation/duckdb.hpp src/include/duckdb.h && \
    ./scripts/upload-assets-to-staging.sh github_release libduckdb-linux-loong64.zip duckdb_cli-linux-loong64.zip duckdb_cli-linux-loong64.gz

RUN set -ex && \
    python3 scripts/run_tests_one_by_one.py build/release/test/unittest "*" --time_execution && \
    ./build/release/test/unittest --select-tag release && \
    python3 -m pytest tools/shell/tests --shell-binary build/release/duckdb && \
    build/release/benchmark/benchmark_runner benchmark/micro/update/update_with_join.benchmark && \
    build/release/duckdb -c "COPY (SELECT 42) TO '/dev/stdout' (FORMAT PARQUET)" | cat