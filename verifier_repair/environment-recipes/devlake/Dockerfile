# Environment repair; user approved the /data build on 2026-10-03.
# Versions come from backend/Makefile and backend/Dockerfile in this instance.
FROM key4127/refactor-dockerhub:apache__devlake-8877
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV TMPDIR=/opt/swepm-prereqs/tmp \
    GOCACHE=/opt/swepm-prereqs/cache/go-build \
    GOBIN=/opt/swepm-prereqs/bin \
    GOMAXPROCS=2 \
    GOFLAGS=-p=2
RUN mkdir -p /opt/swepm-prereqs/{tmp,cache/go-build,bin,src,build}
RUN mkdir -p /opt/swepm-prereqs/cache/apt/{archives/partial,lists/partial} \
 && printf '%s\n' \
      'deb https://deb.debian.org/debian bookworm main' \
      'deb https://deb.debian.org/debian bookworm-updates main' \
      'deb https://deb.debian.org/debian-security bookworm-security main' \
      > /opt/swepm-prereqs/cache/apt/sources.list \
 && apt-get -o Dir::Etc::sourcelist=/opt/swepm-prereqs/cache/apt/sources.list \
      -o Dir::Etc::sourceparts=- -o APT::Update::Error-Mode=any \
      -o Dir::State::lists=/opt/swepm-prereqs/cache/apt/lists update \
 && DEBIAN_FRONTEND=noninteractive apt-get \
      -o Dir::Etc::sourcelist=/opt/swepm-prereqs/cache/apt/sources.list \
      -o Dir::Etc::sourceparts=- \
      -o Dir::State::lists=/opt/swepm-prereqs/cache/apt/lists \
      -o Dir::Cache=/opt/swepm-prereqs/cache/apt \
      install -y --no-install-recommends cmake
RUN curl -fL --retry 3 https://codeload.github.com/libgit2/libgit2/tar.gz/refs/tags/v1.3.0 \
      -o /opt/swepm-prereqs/src/libgit2-1.3.0.tar.gz \
 && sha256sum /opt/swepm-prereqs/src/libgit2-1.3.0.tar.gz \
 && tar -xzf /opt/swepm-prereqs/src/libgit2-1.3.0.tar.gz -C /opt/swepm-prereqs/src \
 && cmake -S /opt/swepm-prereqs/src/libgit2-1.3.0 -B /opt/swepm-prereqs/build/libgit2 \
      -DCMAKE_INSTALL_PREFIX=/opt/swepm-prereqs -DCMAKE_INSTALL_LIBDIR=lib \
      -DBUILD_TESTING=OFF -DBUILD_CLAR=OFF -DCMAKE_BUILD_TYPE=Release \
 && cmake --build /opt/swepm-prereqs/build/libgit2 -j2 \
 && cmake --install /opt/swepm-prereqs/build/libgit2
ENV PATH=/opt/swepm-prereqs/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    PKG_CONFIG_PATH=/opt/swepm-prereqs/lib/pkgconfig \
    LD_LIBRARY_PATH=/opt/swepm-prereqs/lib
RUN cd /testbed/backend && go install github.com/vektra/mockery/v2@v2.43.0
RUN cd /testbed/backend \
 && mockery --recursive --keeptree --dir=./core --output=./mocks/core --unroll-variadic=false --name='.*' \
 && mockery --recursive --keeptree --dir=./helpers --output=./mocks/helpers --unroll-variadic=false --name='.*'
RUN test "$(pkg-config --modversion libgit2)" = 1.3.0 && mockery --version
# Server startup loads the checked-in Azure Python plugin as well as Go plugins.
# Prebuild its small environment instead of downloading dependencies during tests.
ENV DEVLAKE_UV_INSTALL_DIR=/opt/swepm-prereqs/bin \
    UV_CACHE_DIR=/opt/swepm-prereqs/cache/uv \
    UV_PYTHON_INSTALL_DIR=/opt/swepm-prereqs/python \
    PIP_CACHE_DIR=/opt/swepm-prereqs/cache/pip
RUN DEBIAN_FRONTEND=noninteractive apt-get \
      -o Dir::Etc::sourcelist=/opt/swepm-prereqs/cache/apt/sources.list \
      -o Dir::Etc::sourceparts=- \
      -o Dir::State::lists=/opt/swepm-prereqs/cache/apt/lists \
      -o Dir::Cache=/opt/swepm-prereqs/cache/apt \
      install -y --no-install-recommends libmariadb-dev libpq-dev \
 && cd /testbed/backend \
 && sh python/uv.sh sync python/plugins/azuredevops \
 && uv --version \
 && python/plugins/azuredevops/.venv/bin/python -c 'import MySQLdb, psycopg2, pydevlake'
