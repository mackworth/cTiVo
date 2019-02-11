#!/bin/bash


# arbitrarily choose a completion point of the segments
# rather than printing 0 - 100 % twice, which runs the risk (albeit small) of getting
# killed by cTiVo if the progress monitor sees the same % twice in a row
merge_start_percent=98

# Due to the transition to Transport Stream, there’s a good chance you’ll get a file
# with no video stream.  It needs to report this to ctivo which will switch to TS and
# start all over again
no_video_stream_message="no video streams"

# cTiVo needs us to print a progress indicator, so every $sleep_duration seconds, 
# check the tail of the ffmpeg log to see where we're at
sleep_duration=3

# Do we want to pass through AC3?
ac3="YES"
stereo="YES"

usage() {
  cat << EOF 1>&2
Usage: $0 -edl <edl file> [-noAC3] <ffmpeg options>
       $0 -h
Script to drive ffmpeg, adding Edit Decision List capability (e.g. comskip) and dual stereo/5.1 audio tracks capabilities
Calls ffmpeg to get duration and audio stream information about the input file
If a 5.1 audio stream exists, both it and a derived AAC stereo stream will be copied through
To avoid AC3 passthrough, just add "-noAC3" to calling line
To avoid stereo creation, just add "--noStereo" to calling line
For EDL, use the "-edl filename.edl" option
For this text, use the "-h" option
Other parameters will be passed through from calling program, with a few Limitations:
* If -edl is provided, the video will be encoded in several chunks, so don't assume anything about duration. 
* In particular, don't use -ss, -to or any filters that select or cut segments as these are likely to conflict with the script's own ffmpeg options used to implement the -edl option
* By default, the stereo track is encoded with the aac ffmpeg codec and the 5.1 track is encoded with the ac3 ffmpeg codec, with no additional options.
* Any audio encoder options will apply to both the 5.1 and stereo streams. If a video is known to include an ac3 5.1 track, it can be assumed that the stereo stream in the output will be audio 0 and the 5.1 stream will be audio 1. For example -b:a 128k will set a bitrate of 128k on both streams, which is probably not desirable, instead if a custom bitrate is desired it should be set on both streams separately (5.1 requires a higher bitrate than stereo) i.e. -b:a:0 128k -b:a:1 396k
EOF
exit 1
}

# use dirname $0 to get path to ourselves unless $FFMPEG_PATH 
# is set, in which case use that
ffmpeg_path=$(dirname "$0")/../MacOS/ffmpeg
if [ -n "$FFMPEG_PATH" ]; then
  ffmpeg_path="$FFMPEG_PATH"
fi

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
  local progress percent last_percent status err_msg

  # make sure ffmpeg doesn't prompt us to remove the output file
  # if for some reason it pre-exists
#  echo "Min: $min_percent"
#  echo "Max: $max_percent"
#  echo "Dur: $duration"
#  echo "Out: $output"
#  echo "Log: $logfile"
#  echo "Rst: $@"
  rm -rf "$output"

  set -x
  echo "launching ffmpeg $@ $output"  >&2
  "$ffmpeg_path" "$@" "$output" &> "$logfile" &
  pid=$!
  set +x
  last_percent="$min_percent"
  echo "$last_percent" | awk '{printf("%.2f %%\n",$1)}'
  while kill -0 $pid &> /dev/null; do
    progress=$(tail -c 1000 "$logfile"  | egrep -o 'time=[0-9:\.]+' | cut -d= -f2 | tail -n1)
    if [ -n "$progress" ]; then
      progress=$(timestamp_to_seconds "$progress")
      percent=$(echo "$min_percent $max_percent $progress $duration " | awk '
{
min=$1; max=$2; progress=$3; duration=$4
pct=max
if (progress < duration) {
  pct = min + (max - min) * progress / duration
}
printf("%.2f",pct)
}')
      if [ "$last_percent" != "$percent" ]; then
        echo "$percent %"
      fi
      last_percent="$percent"
    fi
    sleep $sleep_duration
  done 
  wait $pid
  status=$?
  pid=

  [[ -s "$output" ]] || err_msg="problem generating $output"
  [[ "$status" = "0" ]] || err_msg="$ffmpeg_path exited with a status of $status"
  if [[ -n "$err_msg" ]]; then
    echo "error: $err_msg, dumping contents of ffmpeg logfile ($logfile)" >&2
    cat "$logfile" >&2
    exit 1
  fi

  last_percent="$max_percent"
  echo "$last_percent" | awk '{printf("%.2f %%\n",$1)}'
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
  elif [ "$1" == "-noAC3" ]; then
    ac3=''
    shift 1
    continue
  elif [ "$1" == "-noStereo" ]; then
    stereo=''
    shift 1
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

# first use ffmpeg to get info about duration, stream IDs
file_info=$("$ffmpeg_path" -i "$input" 2>&1 >/dev/null)

original_duration=$(echo "$file_info" | grep 'Duration: [0-9]' | awk '{print $2}')
if [ -z "$original_duration" ]; then
  echo "WARNING: Unable to determine duration from input file $input:; Guessing 2 hours"
  echo "$file_info"
  original_duration="2:00:00"
fi

# figure out the duration after cutting, for the progress indicator
original_duration=$(timestamp_to_seconds $original_duration)

if [ -s "$edl_file" ]; then
  cut_duration=$(awk "BEGIN {total=0} {total += ($original_duration < \$2 ? $original_duration : \$2)-\$1} END {print total}" "$edl_file")
  duration=$(echo "$original_duration-$cut_duration" | bc -l)
else
  duration=$original_duration
fi

# look for first video and audio stream in input file
audio_line=$(echo "$file_info" | /usr/bin/perl -ne 'if (/^\s*Stream #(\d:\d).*Audio:.*/) {print "$1,$_"; exit}')
audio_stream=$(echo "$audio_line" | cut -d, -f1)
video_stream=$(echo "$file_info" | /usr/bin/perl -ne 'if (/^\s*Stream #(\d:\d).*Video:.*/) {print "$1"; exit}')
declare -a map_opts audio_opts encode_opts
if [[ -n "$video_stream" ]]; then
  map_opts+=(-map "$video_stream")
else
  echo "$file_info" >&2
  echo "$no_video_stream_message" >&2
  exit 1
fi
if [[ -n "$audio_stream" ]] ; then
  ac3Stream="0"
  if [[ ! -z "$stereo" ]]; then
    # if user didn't specify No Stereo
    map_opts+=(-map "$audio_stream")
    audio_opts+=(-c:a:0 aac -ac:a:0 2)
    ac3Stream="1"
  fi
  if [[ ! -z "$ac3" ]]; then
    checkAC3=$(echo "$audio_line" | cut -d, -f2- | grep ac3)
    if [[ ! -z "$checkAC3" ]]; then
      # if we have an AC3, then we may have 5.1
      check51=$(echo "$checkAC3" | grep '5\.1')
      if [[ -z "$stereo" ]] || [[ ! -z "$check51" ]] ; then
        # if audio is ac3 5.1 (Dolby Digital), create an additional ac3 stream for surround sound
        map_opts+=(-map "$audio_stream")
        audio_opts+=(-c:a:"$ac3Stream" copy)
      fi
    elif [[ -z "$stereo" ]] ; then
      # if user said no stereo, but yes AC3, then try to create AC3
      map_opts+=(-map "$audio_stream")
      audio_opts+=(-c:a:"$ac3Stream" ac3)
    fi
  fi
fi

# attempt to munge users's ffmpeg args with our auto-generated -map and audio encoder opts.
encode_opts=("${ffmpeg_opts_pre_input[@]}" -i "$input" -max_muxing_queue_size 4000 "${map_opts[@]}" "${ffmpeg_opts_post_input[@]}" "${audio_opts[@]}")

if [ ! -s "$edl_file" ]; then
  # no edl file or empty, don't need to encode segments and merge, simply encode
  launch_and_monitor_ffmpeg 0 100 $duration "$output" "$tmpdir/logs/ffmpeg.log" "${encode_opts[@]}"

else
  # encode segments separately and merge together
  merge_filename="$tmpdir/segment_list.txt"
  mkdir -p "$tmpdir/segments"
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
   segment_name=$(echo "$ss,$to" | /usr/bin/awk -F, '{printf("%06d_%06d", $1, $2)}')

    # "input seeking" (-ss before the input file) in ffmpeg is very fast but
    # the timestamps are reset so -to is now really a duration rather than a timestamp to stop at
    if [[ -n "$to" && -n "$ss" ]]; then
      this_duration=$(echo "$to - $ss" | bc -l)
    elif [[ -n "$ss" ]]; then
      if (($(echo "$ss > $original_duration - 1"  | bc -l))); then //ignore fraction of second at end.
        continue
      fi
      this_duration=$(echo "$original_duration - $ss" | bc -l)
    elif [[ -n "$to" ]]; then
      this_duration="$to"
    else
      this_duration="$duration"
    fi
    if [[ -n "$ss" ]]; then
      ss="-ss $ss"
    fi
    if [[ -n "$to" ]]; then
      to="-to $this_duration"
    fi

#    echo "StartStop: >>$startstop<<"
#    echo "To/SS: >>$ss/$to<<"
#    echo "duration: >>$duration<<"
#    echo "Merge%: >>$merge_start_percent<<"

    segment_log="$tmpdir/logs/ffmpeg_segment_${segment_name}.log"
    segment_filename="$tmpdir/segments/segment_${segment_name}.$ext"
    segment_absolute_path=$(realpath "$segment_filename")
    segment_absolute_path_escaped=$(echo "$segment_absolute_path" | sed "s/'/'\\\''/g")
    echo file "'$segment_absolute_path_escaped'" >> "$merge_filename"
    echo duration "$this_duration" >> "$merge_filename"

    launch_and_monitor_ffmpeg $(echo "$merge_start_percent * ($progress / $duration)" | bc -l) \
                              $(echo "$merge_start_percent * (($progress + $this_duration) / $duration)" | bc -l) \
                              $this_duration \
                              "$segment_filename" \
                              "$segment_log" \
                              $ss "${encode_opts[@]}" $to

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
                            -fflags +genpts -f concat -safe 0 -i "$merge_filename" -map 0 -c copy
fi
