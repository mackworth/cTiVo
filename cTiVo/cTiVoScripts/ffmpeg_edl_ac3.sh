#!/bin/bash

# arbitrarily choose a completion point of the segments
# rather than printing 0 - 100 % twice, which runs the risk (albeit small) of getting
# killed by cTiVo if the progress monitor sees the same % twice in a row
merge_start_percent=95

# Due to the transition to Transport Stream, there’s a good chance you’ll get a file
# with no video stream.  It needs to report this to ctivo which will switch to TS and
# start all over again
no_video_stream_message="no video streams"

usage() {
  cat << EOF 1>&2
Usage: $0 -edl <edl file> <ffmpeg options>
       $0 -h
EOF
exit 1
}

# use dirname $0 to get path to ourselves
ffmpeg_path=$(dirname "$0")/ffmpeg

# kill any encode that's going on in the background before 
# exiting ourselves
trap terminate SIGTERM
terminate() {
  if [ -n $pid ]; then
    kill -TERM "$pid" 2> /dev/null
  fi
  echo "Terminating"
  exit 15
}

# http://stackoverflow.com/questions/3572030/bash-script-absolute-path-with-osx
realpath() {
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

# convert timestamp (i.e. 00:10:30,123) to seconds (i.e. 40.123)
# for the purpose of calculating a % progress indicator
timestamp_to_seconds() {
  local timestamp="$1"
  hours=$(echo $timestamp | cut -d: -f1)
  minutes=$(echo $timestamp | cut -d: -f2)
  seconds=$(echo $timestamp | cut -d: -f3)
  seconds_fraction=$(echo "$seconds" | cut -d, -f2 | awk '{printf("%03d",$1)}')
  seconds=$(echo "$seconds" | cut -d, -f1)
  echo $(echo "3600*$hours + 60*$minutes + $seconds + $seconds_fraction/1000" | bc -l)
}

# launch and monitor the ffmpeg proc as it runs in the background, grepping the time out
# of the end of the ffmpeg log for the progress indicator
# Arguments:
#  min_percent:
#  max_percent: the range into which we map ffmpeg progress for reporting (0-100)
#  duration: expected length of current segment of video in seconds
#  output: ffmpeg output file
#  logfile: ffmpeg log file
#
# cTiVo will kill this script if it continuously outputs the same progress % for a
# MaxProgressDelay (default 2 min) window.
launch_and_monitor_ffmpeg() {
  local min_percent="$1"; shift
  local max_percent="$1"; shift
  local duration="$1"; shift
  local output="$1"; shift
  local logfile="$1"; shift
  local progress percent last_percent

  # make sure ffmpeg doesn't prompt us to remove the output file
  # if for some reason it pre-exists
  rm -rf "$output"

  set -x
  "$ffmpeg_path" "$@" "$output" &> "$logfile" &
  pid=$!
  set +x
  last_percent="$min_percent"
  echo "$last_percent" | awk '{printf("%.2f %%\n",$1)}'
  while kill -0 $pid &> /dev/null; do
    progress=$(tail -c 1000 "$logfile"  | egrep -o 'time=\S+' | cut -d= -f2 | tail -n1)
    if [ -n "$progress" ]; then
      progress=$(timestamp_to_seconds "$progress")
      percent=$(echo "$min_percent $max_percent $progress $duration " | awk '{printf("%.2f", $1 + ($2 - $1) * $3 / $4)}')
      if [ "$last_percent" != "$percent" ]; then
        echo "$percent %"
      fi
      last_percent="$percent"
    fi
    #hack: "read zero char from keyboard, fail after 1 second", better than "sleep 1" as no process created
    read -t 1.0 -N 0
  done 
  last_percent="$max_percent"
  echo "$last_percent" | awk '{printf("%.2f %%\n",$1)}'
  pid=

  if [ ! -f "$output" ]; then
    echo "error: problem generating $output, see $logfile for details"
    exit 1
  fi
}

# attempt to keep the wrapper script interface transparent, 
# just adding an -edl option
declare -a ffmpeg_opts_pre_input ffmpeg_opts_post_input
while (( $# > 0 )); do
  if [ "$1" == "-h" ]; then
    usage
  elif [ "$1" == "-i" ]; then
    input="$2"
    shift 2
    continue
  elif [ "$1" == "-edl" ]; then
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
    ffmpeg_opts_pre_input+=("$1")
  else
    ffmpeg_opts_post_input+=("$1")
  fi
  shift
done

# sanity check the arguments
if [ ! -x "$ffmpeg_path" ]; then
  echo "internal error: unable to find executable ffmpeg at $ffmpeg_path"
  exit 1
fi
if [ -z "$output" ]; then
  echo "missing output file"
  usage
elif [ -z "$input" ]; then
  echo "missing -i"
  usage
elif [ ! -f "$input" ]; then
  echo "no such file: $input"
  usage
fi
ext="${output##*.}"

# work dir prep
output_base=$(basename "$output")
input_dir=$(dirname "$input")
tmpdir="${input_dir}/${output_base%.*}_ffmpeg"
rm -rf "$tmpdir"
mkdir -p "$tmpdir/logs"

# figure out the duration after cutting, for the progress indicator
file_info=$("$ffmpeg_path" -i "$input" 2>&1 >/dev/null)
original_duration=$(echo "$file_info" | grep Duration: | awk '{print $2}')
original_duration=$(timestamp_to_seconds $original_duration)
cut_duration=$(awk "BEGIN {total=0} {total += ($original_duration < \$2 ? $original_duration : \$2)-\$1} END {print total}" "$edl_file")
duration=$(echo "$original_duration-$cut_duration" | bc -l)

# check if the audio stream is ac3 and 5.1
# if it is, create two audio streams in the output file: 2-channel aac and ac3 5.1
# otherwise, just convert to aac
audio_line=$(echo "$file_info" | /usr/bin/perl -ne 'if (/^\s*Stream #(\d:\d).*Audio:.*/) {print "$1,$_"; exit}')
audio_stream=$(echo "$audio_line" | cut -d, -f1)
video_stream=$(echo "$file_info" | /usr/bin/perl -ne 'if (/^\s*Stream #(\d:\d).*Video:.*/) {print "$1"; exit}')
declare -a map_opts ac3_opts
if [[ -n "$video_stream" ]]; then
  map_opts+=(-map "$video_stream")
else
  echo "$no_video_stream_message" >&2
  exit 1
fi
if [[ -n "$audio_stream" ]]; then
  map_opts+=(-map "$audio_stream")
fi
if echo "$audio_line" | cut -d, -f2- | grep ac3 | grep --quiet '5\.1'; then
  map_opts+=(-map "$audio_stream")
  ac3_opts+=("-c:a:1" "ac3")
fi

if [ -z "$edl_file" ]; then
  # no edl file, don't need to encode segments and merge, simply encode with the modified audio streams
  # TODO: remove -strict -2 once the bundled ffmpeg binary is updated to 3.1.1 or later
  launch_and_monitor_ffmpeg 0 100 $duration "$output" "$tmpdir/logs/ffmpeg.log" "${ffmpeg_opts_pre_input[@]}" -i "$input" "${map_opts[@]}" "${ffmpeg_opts_post_input[@]}" -strict -2 -c:a:0 aac "${ac3_opts[@]}"

else
  # encode segments separately and merge together
  merge_filename="$tmpdir/ffmpeg_merge.txt"
  progress=0
  for startstop in $(/usr/bin/awk '
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
' "$edl_file"); do
    ss=$(echo $startstop | cut -d: -f1)
    to=$(echo $startstop | cut -d: -f2)
    segment_name=${ss}_${to}

    # "input seeking" (-ss before the input file) in ffmpeg is very fast but
    # the timestamps are reset so -to is now really a duration rather than a timestamp to stop at
    if [[ -n "$to" && -n "$ss" ]]; then
      this_duration=$(echo "$to - $ss" | bc -l | /usr/bin/awk '{printf("%.3f",$1)}')
    elif [[ -n "$ss" ]]; then
      if (($(echo "$ss > $original_duration" | bc -l))); then
        continue
      fi
      this_duration=$(echo "$original_duration - $ss" | bc -l)
    else
      this_duration="$to"
    fi
    if [[ -n "$ss" ]]; then
      ss="-ss $ss"
    fi
    if [[ -n "$to" ]]; then
      to="-to $this_duration"
    fi

    segment_filename="$tmpdir/segment_${segment_name}.$ext"
    echo file \'$(realpath "$segment_filename")\' >> "$merge_filename"

    # TODO: remove -strict -2 once the bundled ffmpeg binary is updated to 3.1.1 or later
    launch_and_monitor_ffmpeg $(echo "$merge_start_percent * ($progress / $duration)" | bc -l) \
                              $(echo "$merge_start_percent * (($progress + $this_duration) / $duration)" | bc -l) \
                              $this_duration \
                              "$segment_filename" \
                              "$tmpdir/logs/ffmpeg_segment$i.log" \
                              $ss "${ffmpeg_opts_pre_input[@]}" -i "$input" "${map_opts[@]}" "${ffmpeg_opts_post_input[@]}" -strict -2 -c:a:0 aac "${ac3_opts[@]}" $to

    progress=$(echo "$this_duration + $progress" | bc -l)
  done

  # merge the segments together
  # though this usually happens in under 2 minutes, it could 
  # take longer for larger videos, so track progress for the merge
  launch_and_monitor_ffmpeg $merge_start_percent \
                            100 \
                            $duration \
                            "$output" \
                            "$tmpdir/logs/ffmpeg_concat.log" \
                            -f concat -safe 0 -i "$merge_filename" "${map_opts[@]}" -c copy "${ac3_opts[@]}"
fi
