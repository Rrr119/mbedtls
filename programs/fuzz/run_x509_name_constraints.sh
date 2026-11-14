#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd "${script_dir}/../.." && pwd)
duration=${1:-60}
build_dir=${BUILD_DIR:-"${root_dir}/build-fuzz-x509-name-constraints"}
user_home=$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 || true)
user_home=${user_home:-${HOME}}

if ! [[ "${duration}" =~ ^[0-9]+$ ]] || [[ "${duration}" -eq 0 ]]; then
    echo "usage: $0 [DURATION_SECONDS]" >&2
    exit 2
fi

find_clang() {
    if [[ -n "${CLANG:-}" ]]; then
        command -v "${CLANG}"
        return
    fi
    if [[ -n "${CC:-}" ]] && "${CC}" --version 2>&1 | grep -q clang; then
        command -v "${CC}"
        return
    fi
    local candidate
    for candidate in clang clang-21 clang-20 clang-19 clang-18 clang-17 \
                     "${user_home}"/local/llvm*/usr/bin/clang-[0-9]* \
                     /usr/lib/llvm-*/bin/clang; do
        if command -v "${candidate}" >/dev/null 2>&1; then
            command -v "${candidate}"
            return
        fi
    done
    return 1
}

clang_bin=$(find_clang) || {
    echo "error: clang with libFuzzer support was not found" >&2
    echo "set CLANG=/path/to/clang or install clang locally" >&2
    exit 2
}

if [[ -n "${CLANGXX:-}" ]]; then
    clangxx_bin=$(command -v "${CLANGXX}")
else
    clangxx_bin="${clang_bin}"
    if [[ "${clang_bin}" =~ clang-([0-9]+)$ ]]; then
        clangxx_bin="${clang_bin%clang-*}clang++-${BASH_REMATCH[1]}"
    elif [[ -x "${clang_bin%clang}clang++" ]]; then
        clangxx_bin="${clang_bin%clang}clang++"
    fi
fi

if [[ ! -x "${clangxx_bin}" ]]; then
    echo "error: matching clang++ compiler was not found" >&2
    exit 2
fi

corpus_dir="${root_dir}/programs/fuzz/corpuses/x509_name_constraints"
dictionary="${root_dir}/programs/fuzz/x509_name_constraints.dict"
artifact_dir="${build_dir}/artifacts"
work_corpus_dir="${build_dir}/corpus"
binary="${build_dir}/programs/fuzz/fuzz_x509_name_constraints"

mkdir -p "${artifact_dir}" "${work_corpus_dir}"
for seed in "${corpus_dir}"/*; do
    destination="${work_corpus_dir}/$(basename "${seed}")"
    if [[ ! -e "${destination}" ]]; then
        cp "${seed}" "${destination}"
    fi
done

cmake -S "${root_dir}" -B "${build_dir}" \
    -DCMAKE_C_COMPILER="${clang_bin}" \
    -DCMAKE_CXX_COMPILER="${clangxx_bin}" \
    -DCMAKE_BUILD_TYPE=ASan \
    -DCMAKE_C_FLAGS="-fsanitize=fuzzer-no-link" \
    -DCMAKE_CXX_FLAGS="-fsanitize=fuzzer-no-link" \
    -DMBEDTLS_FUZZ_LIBFUZZER=ON \
    -DENABLE_TESTING=OFF \
    -DENABLE_PROGRAMS=ON

cmake --build "${build_dir}" \
    --target fuzz_x509_name_constraints \
    --parallel "${BUILD_JOBS:-$(nproc)}"

exec "${binary}" \
    -dict="${dictionary}" \
    -artifact_prefix="${artifact_dir}/" \
    -max_len=65535 \
    -timeout=10 \
    -max_total_time="${duration}" \
    -print_final_stats=1 \
    "${work_corpus_dir}"
