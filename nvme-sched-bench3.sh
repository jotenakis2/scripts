#!/bin/bash
# shellcheck enable=all
#
# Passe 3 : meme charge que la passe 2, mais avec controle du biais d'ordre.
#   - un run de chauffe jete par scheduler et par scenario
#   - ordre inverse (kyber, mq-deadline, none)
#   - runs comptes en round-robin : un run de chaque scheduler par tour
# A lancer en root (pkexec).

set -euo pipefail

readonly DEV=/sys/block/nvme0n1
readonly WORK=/var/tmp/nvme-sched-bench3
readonly RUNTIME=20
readonly RAMP=4
readonly RUNS=3
readonly ORDER=(kyber mq-deadline none)

if (( EUID != 0 )); then
  printf 'Root requis : pkexec %s\n' "${BASH_SOURCE[0]}" >&2
  exit 1
fi

for cmd in fio jq fallocate chattr; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    printf 'Commande manquante : %s\n' "${cmd}" >&2
    exit 1
  fi
done

read -r current < "${DEV}/queue/scheduler"
current=${current##*\[}
current=${current%%]*}

cleanup() {
  printf '\nRestauration du scheduler : %s\n' "${current}"
  printf '%s\n' "${current}" > "${DEV}/queue/scheduler" || true
  rm -rf "${WORK}"
}
trap cleanup EXIT

rm -rf "${WORK}"
mkdir -p "${WORK}"
chattr +C "${WORK}" 2>/dev/null || true

cat > "${WORK}/scenarioA.fio" <<EOF
[global]
ioengine=libaio
direct=1
time_based=1
runtime=${RUNTIME}
ramp_time=${RAMP}
percentile_list=50:99:99.9:99.99
buffer_compress_percentage=0
randrepeat=1
norandommap=1

[write-flood]
filename=${WORK}/writeA.dat
rw=write
bs=128k
iodepth=64
size=4G

[read-flood]
filename=${WORK}/readA.dat
rw=randread
bs=4k
iodepth=64
size=2G
EOF

cat > "${WORK}/scenarioB.fio" <<EOF
[global]
ioengine=libaio
time_based=1
runtime=${RUNTIME}
ramp_time=${RAMP}
percentile_list=50:99:99.9:99.99
buffer_compress_percentage=0
randrepeat=1
norandommap=1

[write-flood-buf]
filename=${WORK}/writeB.dat
rw=write
bs=128k
iodepth=64
size=4G
direct=0

[read-latency]
filename=${WORK}/readB.dat
rw=randread
bs=4k
iodepth=1
size=1G
direct=1
EOF

printf 'Preparation des fichiers de test...\n'
fallocate -l 4G "${WORK}/writeA.dat"
fallocate -l 4G "${WORK}/writeB.dat"
fallocate -l 2G "${WORK}/readA.dat"
fallocate -l 1G "${WORK}/readB.dat"
fio --name=prepA --filename="${WORK}/readA.dat" --rw=write --bs=1M \
    --size=2G --direct=1 --end_fsync=1 --buffer_compress_percentage=0 \
    --output=/dev/null >/dev/null
fio --name=prepB --filename="${WORK}/readB.dat" --rw=write --bs=1M \
    --size=1G --direct=1 --end_fsync=1 --buffer_compress_percentage=0 \
    --output=/dev/null >/dev/null

set_sched() {
  local sched=$1
  local active

  printf '%s\n' "${sched}" > "${DEV}/queue/scheduler"
  read -r active < "${DEV}/queue/scheduler"
  active=${active##*\[}
  active=${active%%]*}
  if [[ ${active} != "${sched}" ]]; then
    printf 'Echec activation %s (actif: %s)\n' "${sched}" "${active}" >&2
    exit 1
  fi
}

run_fio() {
  local jobfile=$1
  local read_job=$2
  local write_job=$3
  local json="${WORK}/out.json"
  local row
  local runtime_ms
  local dsectors
  local dev_write
  local -a stat_before
  local -a stat_after

  sync
  printf '3\n' > /proc/sys/vm/drop_caches
  read -r -a stat_before < "${DEV}/stat"
  fio "${jobfile}" --output-format=json --output="${json}" >/dev/null
  read -r -a stat_after < "${DEV}/stat"

  dsectors=$(( stat_after[6] - stat_before[6] ))
  runtime_ms=$(jq -r --arg w "${write_job}" \
    '(.jobs[] | select(.jobname == $w) | .job_runtime | floor)' "${json}")
  if (( runtime_ms < 1 )); then
    runtime_ms=1
  fi
  dev_write=$(( dsectors * 512 / (1000 * runtime_ms) ))

  row=$(jq -r --arg r "${read_job}" --arg w "${write_job}" '
    (.jobs[] | select(.jobname == $r)) as $rjob |
    (.jobs[] | select(.jobname == $w)) as $wjob |
    [ ($rjob.read.iops | floor),
      ($rjob.read.clat_ns.percentile["50.000000"] / 1000 | floor),
      ($rjob.read.clat_ns.percentile["99.000000"] / 1000 | floor),
      ($rjob.read.clat_ns.percentile["99.900000"] / 1000 | floor),
      ($rjob.read.clat_ns.percentile["99.990000"] / 1000 | floor),
      ($rjob.read.clat_ns.max / 1000 | floor),
      ($wjob.write.bw_bytes / 1048576 | floor),
      ($wjob.sys_cpu | floor),
      ($wjob.ctx | floor)
    ] | @tsv' "${json}")
  printf '%s\t%s\n' "${row}" "${dev_write}"
}

bench_scenario() {
  local title=$1
  local jobfile=$2
  local read_job=$3
  local write_job=$4
  local sched
  local run
  local row
  local -a vals

  printf '\n=== %s ===\n' "${title}"
  printf '%-12s %3s %10s %7s %7s %8s %8s %7s %10s %10s %7s %7s\n' \
    scheduler run read_iops p50_us p99_us p99.9_us p99.99_us max_us write_MBps w_sysCPU w_ctx dev_MBps

  printf 'Chauffe jetee :'
  for sched in "${ORDER[@]}"; do
    printf ' %s' "${sched}"
    set_sched "${sched}"
    run_fio "${jobfile}" "${read_job}" "${write_job}" >/dev/null
  done
  printf '\n'

  for ((run = 1; run <= RUNS; run++)); do
    for sched in "${ORDER[@]}"; do
      set_sched "${sched}"
      row=$(run_fio "${jobfile}" "${read_job}" "${write_job}")
      IFS=$'\t' read -r -a vals <<< "${row}"
      printf '%-12s %3s %10s %7s %7s %8s %8s %7s %10s %10s %7s %7s\n' \
        "${sched}" "${run}" "${vals[@]}"
    done
  done
}

bench_scenario 'A: lectures 4k d64 + ecriture seq 128k d64 (direct)' \
  "${WORK}/scenarioA.fio" read-flood write-flood

bench_scenario 'B: ecriture seq 128k bufferisee + lecture 4k d1 (direct)' \
  "${WORK}/scenarioB.fio" read-latency write-flood-buf
