#!/bin/bash

set -x

set -euo pipefail

readonly BUILD_TARGET=wasm32-wasi
readonly FIXTURE_PATH=spec/fixtures/proxy_wasm_filters
readonly INSTALL_ROOT=${INSTALL_ROOT:-bazel-bin/build/kong-dev}

install-toolchain() {
    export RUSTUP_INIT_SKIP_PATH_CHECK=yes

    # in CI we just install to the homedir
    if [[ -n ${CI:-} ]]; then
        export RUSTUP_HOME=$HOME/.rustup
        export CARGO_HOME=$HOME/.cargo

    # locally, we install to bazel-bin so that everything can be
    # cleaned up easily
    else
        export RUSTUP_HOME=$INSTALL_ROOT/rustup
        export CARGO_HOME=$INSTALL_ROOT/cargo
        mkdir -p "$RUSTUP_HOME" "$CARGO_HOME"
    fi

    curl \
        --proto '=https' \
        --tlsv1.2 \
        -sSf \
        https://sh.rustup.rs \
    | sh -s -- \
        -y \
        --no-modify-path \
        --profile minimal \
        --component cargo \
        --target "$BUILD_TARGET"

    export PATH=${CARGO_HOME}/bin:${PATH}
}


main() {
    if command -v cargo &> /dev/null; then
        echo "Using pre-installed rust toolchain"

    else
        echo "Installing rust toolchain..."

        install-toolchain

        command -v cargo || {
            echo "Failed to find/install cargo"
            exit 1
        }
    fi


    cargo build \
        --manifest-path "$FIXTURE_PATH/Cargo.toml" \
        --workspace \
        --lib \
        --target "$BUILD_TARGET"
}

main
