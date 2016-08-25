#!/bin/bash

# use dirname $0 to get path to ourselves
ffmpeg_path=$(dirname "$0")/ffmpeg

# kill ffmpeg if our script is killed
trap terminate SIGTERM

usage() {
  cat << EOF 1>&2
Usage: $0 -edl <edl file> <ffmpeg options>
       $0 -h
EOF
exit 1
}

timestamp_to_seconds() {
  hours=$(echo $1 | cut -d: -f1)
  minutes=$(echo $1 | cut -d: -f2)
  seconds=$(echo $1 | cut -d: -f3)
  seconds_fraction=$(echo "$seconds" | cut -d, -f2 | awk '{printf("%03d",$1)}')
  seconds=$(echo "$seconds" | cut -d, -f1)
  echo $(echo "3600*$hours + 60*$minutes + $seconds + $seconds_fraction/1000" | bc -l)
}

# monitor the ffmpeg proc as it runs in the background, grepping the time out
# of the end of the ffmpeg log for the progress indicator
monitor() {
# Globals:
#  $duration: length of video in seconds (after cutting)
#  $progress: starting point in seconds for current section (if first_pass)
#  $pid: process for ffmpeg
#  $first_pass: empty if doing ffmpeg encoding; set if doing ffmpeg concat
#  $last_pct: previous % status (empty if none)
#  $ffmpeg_logfile: path to log file

# cTiVo will kill this script if it continuously outputs the same progress % for a
# MaxProgressDelay (default 2 min) window.

  while kill -0 $pid &> /dev/null; do
    this_progress=$(tail -c 1000 "$ffmpeg_logfile"  | egrep -o 'time=\S+' | cut -d= -f2 | tail -n1)
    if [ ! -z "$this_progress" ]; then
      this_progress=$(timestamp_to_seconds "$this_progress")
      if [ "$this_progress" != "0" ]; then
        if [ "$first_pass" == "true" ]; then
          pct=$(echo "$progress $this_progress $duration" | awk '{printf("%.2f", 90 * ($1 + $2) / $3)}')
          if (($(echo "$pct >= 90" | bc -l))); then pct="89.99"; fi
        else
          pct=$(echo "$this_progress $duration" | awk '{printf("%.2f", 90 + (10 * $1 / $2))}')
          if (($(echo "$pct < 90" | bc -l))); then pct="90.00"; fi
          if (($(echo "$pct >= 100" | bc -l))); then pct="99.99"; fi
        fi
      fi
    fi
    if [ "$last_pct" != "$pct" ]; then
      echo "$pct %"
    fi
    last_pct="$pct"
    sleep 1
  done 
}

# kill any encode that's going on in the background before 
# exiting ourselves
terminate() {
  kill -TERM "$pid" 2> /dev/null
  echo "Terminating"
  exit 15
}

while (( $# > 0 )); do
  if [ "$1" == "-h" ]; then usage; fi
  if [ "$1" == "-i" ]; then
    input="$2"
    shift 2
    continue
  fi
  if [ "$1" == "-edl" ]; then
    edl_file="$2"
    shift 2
    continue
  fi
# last positional argument should be the output file
  if (( $# == 1 )); then
    output="$1"
    shift 1
    continue
  fi
  if [ -z "$input" ]; then
    ffmpeg_opts_pre_input="$ffmpeg_opts_pre_input $1"
  else
    ffmpeg_opts_post_input="$ffmpeg_opts_post_input $1"
  fi
  shift
done

if [ -z "$output" ]; then
  echo "missing output"
  usage
fi
if [ -z "$input" ]; then
  echo "missing -i"
  usage
fi

if [ ! -f "$input" ]; then
  echo "no such file: $input"
  usage
fi

awkcmd='
BEGIN {OFS=":"}
{
  if (NR == 1 && $1 > 0) {
    print "",$1
  } else {
    if (NR > 1) {
      print ss,$1
    }
  }
  ss = $2
}
END {print ss,""}
'

tmpdir="${input%.*}_ffmpeg"
rm -rf "$tmpdir"
mkdir -p "$tmpdir/comskip"
mkdir -p "$tmpdir/logs"

if [ -z "$edl_file" ]; then
  edl_file="$tmpdir/dummy.edl"
  touch "$edl_file"
fi

ext="${output##*.}"

# figure out the duration after cutting, for the progress indicator
file_info=$($ffmpeg_path -i "$input" 2>&1 >/dev/null)
original_duration=$(echo "$file_info" | grep Duration: | awk '{print $2}')
original_duration=$(timestamp_to_seconds $original_duration)
cut_duration=$(awk "BEGIN {total=0} {total += ($original_duration < \$2 ? $original_duration : \$2)-\$1} END {print total}" "$edl_file")
duration=$(echo "$original_duration-$cut_duration" | bc -l)

# check if the audio stream is ac3 and 5.1
# if it is, create two audio streams in the output file: 2-channel aac and ac3 5.1
# otherwise, just convert to aac
audio_stream=$(echo "$file_info" | grep -m1 Audio: | perl -pe 's/\s*Stream #(\d:\d).*/$1/')
video_stream=$(echo "$file_info" | grep -m1 Video: | perl -pe 's/\s*Stream #(\d:\d).*/$1/')
map_opts="-map $video_stream -map $audio_stream"
ac3_opts=
if echo "$file_info" | grep -m1 Audio: | grep ac3 | grep --quiet '5\.1'; then
  map_opts="$map_opts -map $audio_stream"
  ac3_opts="-c:a:1 ac3"
fi

ffmpeg_concat_filename="$tmpdir/ffmpeg_concat.txt"
i=1
progress=0
first_pass="true"
for startstop in $(/usr/bin/awk "$awkcmd" "$edl_file"); do
  ss=$(echo $startstop | cut -d: -f1)
  to=$(echo $startstop | cut -d: -f2)

  # "input seeking" (-ss before the input file) in ffmpeg is very fast but
  # the timestamps are reset so -to is now really a duration rather than a timestamp to stop at
  if [ ! -z "$to" ]; then
    if [ ! -z "$ss" ]; then to=$(echo "$to - $ss" | bc -l | awk '{printf("%.3f",$1)}'); fi
    this_duration="$to"
    to="-to $to"
  else
    if [ -z "$ss" ]; then ss="0"; fi
    this_duration=$(echo "$original_duration - $ss" | bc -l)
  fi
  if [ ! -z "$ss" ]; then
    # skip if the beginning of the cut is longer than the duration of the video
    if (($(echo "$ss > $original_duration" | bc -l))); then continue; fi
    ss="-ss $ss";
  fi

  segment_filename="segment${i}.$ext"
  ffmpeg_logfile="$tmpdir/logs/ffmpeg_segment$i.log"
  set -x
  $ffmpeg_path $ss $ffmpeg_opts_pre_input -i "$input" $map_opts $ffmpeg_opts_post_input -strict -2 -c:a:0 aac $ac3_opts $to "$tmpdir/$segment_filename" >& "$ffmpeg_logfile" &
  pid=$!
  set +x

  # monitor ffmpeg and update progress
  monitor

  if [ -f "$tmpdir/$segment_filename" ]; then
    echo "file $segment_filename" >> "$ffmpeg_concat_filename"
  else
    echo "error: problem generating $segment_filename, see $ffmpeg_logfile for details"
    exit 1
  fi
  let i++
  progress=$(echo "$this_duration + $progress" | bc -l)
done

# merge the segments together
# though this usually happens in under 2 minutes, it could 
# take longer for larger videos, so restart progress at 0 
# and track progress for the merge
rm -f "$output"
ffmpeg_logfile="$tmpdir/logs/ffmpeg_concat.log"
set -x
$ffmpeg_path -f concat -safe 0 -i "$ffmpeg_concat_filename" $map_opts -c copy $ac3_opts "$output" >& "$ffmpeg_logfile" &
pid=$!
set +x

first_pass="false"
monitor

echo "100.00 %"
