#!/system/bin/sh
# Runs on the headset itself (tools/quest-recorder.sh puts it there and starts it) and stays
# until the headset restarts. Whenever the emulator runs, with or without a USB cable, it keeps
# what only a shell on the headset may see, in /data/local/tmp/astro/sessions/<start time>/:
#
#   gpu.txt      every 2 s: seconds, GPU load %, GPU clock MHz, GPU temperature, the clock of
#                every processor core in MHz
#   system.txt   the VR runtime's own lines as it writes them: once a second the frame rate it
#                sees, stale frames, processor and GPU level and clock, GPU time of the app and
#                of the compositor ("VrApi"), and every change of clock level with its reason
#                ("crcs")
#   threads.txt  every 30 s: the emulator's busiest threads and the cores they ran on
#
# The ten newest sessions are kept.
root=/data/local/tmp/astro
sessions=$root/sessions
mkdir -p $sessions
echo $$ > $root/recorder.pid
# Makes the system say why it picks the clock levels it picks (until the headset restarts).
setprop debug.oculus.clockStateLogLevel 1 2>/dev/null

while true; do
  until [ -n "$(pidof libastro_ld.so)" ]; do
    sleep 3
  done
  core=$(pidof libastro_ld.so)
  out=$sessions/$(date +%Y%m%d-%H%M%S)
  mkdir -p $out
  logcat -T 1 -v time VrApi:V crcs:V '*:S' > $out/system.txt 2>&1 &
  logcat_pid=$!
  start=$(date +%s)
  samples=0
  while [ -d /proc/$core ]; do
    echo "$(( $(date +%s) - start )) $(cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage | tr -d ' %') $(( $(cat /sys/class/kgsl/kgsl-3d0/gpuclk) / 1000000 )) $(( $(cat /sys/class/kgsl/kgsl-3d0/temp) / 1000 )) $(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq | while read f; do printf '%s ' $(( f / 1000 )); done)" >> $out/gpu.txt
    if [ $(( samples % 15 )) = 0 ]; then
      {
        echo "== $(( $(date +%s) - start )) s"
        top -H -b -n 1 -m 24 -o PID,TID,%CPU,S,PR,NI,CMD,PCY,CPU -p $core 2>&1 | tail -n +6
        echo "cpus allowed: $(grep Cpus_allowed_list /proc/$core/status | cut -f2), cpuset $(cat /proc/$core/cpuset)"
      } >> $out/threads.txt
    fi
    samples=$(( samples + 1 ))
    sleep 2
  done
  kill $logcat_pid 2>/dev/null
  # Oldest first; all but the ten newest go.
  count=$(ls $sessions | wc -l)
  for old in $(ls $sessions | head -n $(( count > 10 ? count - 10 : 0 ))); do
    rm -rf $sessions/$old
  done
done
