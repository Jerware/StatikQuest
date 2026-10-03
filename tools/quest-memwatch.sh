# Runs on the headset, next to the emulator core (tools/quest-sandbox-test.sh starts it): one
# line every <interval> seconds with the core's resident and swapped memory, what the GPU driver
# holds for it, and what the system has left. All sizes in MB.
#   sh memwatch.sh <interval seconds>
interval=${1:-10}
start=$(date +%s)
while sleep "$interval"; do
  pid=$(pidof libastro_ld.so)
  [ -z "$pid" ] && continue
  status=/proc/$pid/status
  rss=$(grep VmRSS: $status | tr -dc 0-9)
  anon=$(grep RssAnon: $status | tr -dc 0-9)
  file=$(grep RssFile: $status | tr -dc 0-9)
  shmem=$(grep RssShmem: $status | tr -dc 0-9)
  swap=$(grep VmSwap: $status | tr -dc 0-9)
  available=$(grep MemAvailable: /proc/meminfo | tr -dc 0-9)
  swapfree=$(grep SwapFree: /proc/meminfo | tr -dc 0-9)
  gpu=$(cat /sys/class/kgsl/kgsl/proc/$pid/gpumem_mapped 2>/dev/null)
  gpu_unmapped=$(cat /sys/class/kgsl/kgsl/proc/$pid/gpumem_unmapped 2>/dev/null)
  echo "t=$(( $(date +%s) - start )) rss=$((rss / 1024)) anon=$((anon / 1024)) file=$((file / 1024))" \
    "shmem=$((shmem / 1024)) swap=$((swap / 1024)) gpu=$(( ${gpu:-0} / 1048576 ))" \
    "gpu_unmapped=$(( ${gpu_unmapped:-0} / 1048576 )) available=$((available / 1024))" \
    "swapfree=$((swapfree / 1024))"
done
