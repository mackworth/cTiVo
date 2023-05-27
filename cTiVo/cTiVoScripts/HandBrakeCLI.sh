#!/bin/bash
# Modified version of ffmpeg_edl_ac3 calling Handbrake for main video transcoding (still ffmpeg for info and concatenation)

# arbitrarily choose a completion point of the segments
# rather than printing 0 - 100 % twice, which runs the risk (albeit small) of getting
# killed by cTiVo if the progress monitor sees the same % twice in a row
merge_start_percent=98

# Due to the transition to Transport Stream, there’s a good chance you’ll get a file
# with no video stream.  It needs to report this to ctivo which will switch to TS and
# start all over again
no_video_stream_message="no video streams"

# cTiVo needs us to print a progress indicator, so every $sleep_duration seconds, 
# check the tail of the Handbrake log to see where we're at
sleep_duration=3

# Do we want to pass through AC3?
ac3="YES"
stereo="YES"

usage() {
  cat << EOF 1>&2
Usage: $0 [-edl <edl file>] [-noAC3] [-noStereo] <Handbrake options>
Script to drive Handbrake, adding Edit Decision List capability (e.g. comskip) and dual stereo/5.1 audio tracks capabilities
Calls ffmpeg to get duration and audio stream information about the input file
If a 5.1 audio stream exists, both it and a derived AAC stereo stream will be copied through
To avoid AC3 passthrough, just add "-noAC3" to calling line
To avoid stereo creation, just add "-noStereo" to calling line
For EDL, use the "-edl filename.edl" option
For this text, use the "-h" option
Other parameters will be passed through from calling program, with a few limitations:
* If -edl is provided, the video will be encoded in several chunks, so don't assume anything about duration. 
* In particular, don't use -start-at, -stop-at or any filters that select or cut segments as these are likely to conflict with the script's own ffmpeg options used to implement the -edl option
* By default, the stereo track is encoded with the aac codec and the 5.1 track is encoded with the ac3 codec, with no additional options.
EOF
exit 1
}

# as this requires both ffmpeg and handbrake, we don't recognize FFMPEG_PATH
# use dirname $0 to get path to ourselves 
# is set, in which case use that
ffmpeg_path=$(dirname "$0")/../MacOS/ffmpeg
encoder_path=$(dirname "$0")/../MacOS/HandbrakeCLI

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

# launch and monitor the encoder proc as it runs in the background, grepping the time out
# of the end of the encoder log for the progress indicator
# Arguments:
#  min_percent:
#  max_percent: the range into which we map encoder progress for reporting (0-100)
#  duration: expected length of current segment of video in seconds
#  output: encoder output file
#  logfile: encoder log file
#
# cTiVo will kill this script if it continuously outputs the same progress % for a
# MaxProgressDelay (default 2 min) window.
launch_and_monitor_encoder() {
  local min_percent="$1"; shift
  local max_percent="$1"; shift
  local duration="$1"; shift
  local output="$1"; shift
  local logfile="$1"; shift
  local encoder="$1"; shift
  local progress percent last_percent status err_msg

#  echo "Min: $min_percent"
#  echo "Max: $max_percent"
#  echo "Dur: $duration"
#  echo "Out: $output"
#  echo "Log: $logfile"
#  echo "Encoder: $encoder"

  # make sure encoder doesn't prompt us to remove the output file
  # if for some reason it pre-exists
#  echo "Rest: $@"
  rm -rf "$output"

  set -x
  echo "Sublaunching $encoder $@ $output"  >&2
  if [[ "$encoder" == "$ffmpeg_path" ]]; then
    "$encoder" "$@" "$output" &> "$logfile" &
  else 
    "$encoder" "$@" -o "$output" &> "$logfile" &
  fi
  pid=$!
  set +x
  last_percent="$min_percent"
  echo "$last_percent" | awk '{printf(" %.2f %%\n",$1)}'
#handbrakeCLI puts out % complete, not time complete (duration) as ffmpeg does
  while kill -0 $pid &> /dev/null; do
    progPerc=$(tail -c 1000 "$logfile"  | egrep -o '[0-9\.]+ %' | cut -d" " -f1 | tail -n1)
    if [ -n "$progPerc" ]; then
      # echo "$min_percent $max_percent $progPerc $duration "
      percent=$(echo "$min_percent $max_percent $progPerc $duration " | awk '
{
min=$1; max=$2; progress=$3; duration=100
pct=max
if (progress < duration) {
  pct = min + (max - min) * progress / duration
}
printf(" %.2f",pct)
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
  [[ "$status" = "0" ]] || err_msg="$encoder exited with a status of $status"
  if [[ -n "$err_msg" ]]; then
    echo "error: $err_msg, dumping contents of logfile ($logfile)" >&2
    cat "$logfile" >&2
    exit 1
  fi

  last_percent="$max_percent"
  echo "$last_percent" | awk '{printf(" %.2f %%\n",$1)}'
}

# attempt to keep the wrapper script interface transparent, 
# just adding an -edl option
declare -a encoder_opts_pre_input encoder_opts_post_input
while (( $# > 0 )); do
  if [ "$1" == "-h" ]; then
    usage
  elif [ "$1" == "-i" ]; then
    input="$2"
    shift 2
    continue
  elif [ "$1" == "-o" ]; then
    output="$2"
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
  if [ -z "$input" ]; then
    encoder_opts_pre_input+=("$1")
  else
    encoder_opts_post_input+=("$1")
  fi
  shift
done

# sanity check the arguments
if [ ! -x "$ffmpeg_path" ]; then
  echo "internal error: unable to find executable ffmpeg at $ffmpeg_path"
  exit 1
fi
if [ ! -x "$encoder_path" ]; then
  echo "internal error: unable to find executable at $encoder_path"
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
tmpdir="${input_dir}/${output_base%.*}_ffmpeg"  #leave filenames for compatibility wiht ffmpeg_edl_ac3
rm -rf "$tmpdir"
mkdir -p "$tmpdir/logs"

# first use ffmpeg to get info about duration, stream IDs
file_info=$("$ffmpeg_path" -i "$input" 2>&1 >/dev/null)
#echo "$file_info" #delete

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
#echo "Audio: $audio_line; stream: $audio_stream"
declare -a  audio_opts encode_opts
if [[ ! -n "$video_stream" ]]; then
  echo "$file_info" >&2
  echo "$no_video_stream_message" >&2
  exit 1
fi
if [[ -n "$audio_stream" ]] ; then
  checkAC3=$(echo "$audio_line" | cut -d, -f2- | grep ac3)
  if [[ -n "$checkAC3" ]]; then
    # we have an AC3
    check51=$(echo "$checkAC3" | grep '5\.1')
    if [[ -n "$check51" ]]; then
      #AC3; 5.1
      if [[ -n "$ac3" ]]; then
        if [[ -n "$stereo" ]]; then
          # Both requested
            audio_opts="-E ca_aac,copy"
        else
          #AC3 but no stereo
        audio_opts="-E copy"
        fi
      elif [[ -n "$stereo" ]]; then
          audio_opts="-E ca_aac"
      else 
        #no audio requested?
        audio_opts="-E none"
      fi
    elif [[ -n "$ac3" ]]; then
      # AC3, but not 5.1; AC3 requested
      audio_opts="-E copy"
    elif [[ -n "$stereo" ]]; then
      audio_opts="-E ca_aac"
    else
      #AC3,not 5.1, but no audio requested?
      audio_opts="-E none"
    fi
  elif [[ -n "$stereo" ]] || [[ -n "$ac3" ]]; then
    # Not AC3, but want audio
    audio_opts="-E copy"
  else 
    #no audio requested?
    audio_opts="-E none"
  fi
fi
echo "Audio: ${audio_opts[@]}" >&2

# attempt to munge users's encoder args with our auto-generated -map and audio encoder opts.
encode_opts=("${encoder_opts_pre_input[@]}"  ${audio_opts[@]} -i "$input" "${encoder_opts_post_input[@]}")
#echo "encode_opts: >>$encode_opts<<" #delete

if [ ! -s "$edl_file" ]; then
  # no edl file or empty, don't need to encode segments and merge, simply encode
  launch_and_monitor_encoder 0 100 $duration "$output" "$tmpdir/logs/handbrake.log" "$encoder_path" "${encode_opts[@]}"
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

    if [[ -n "$to" && -n "$ss" ]]; then
		# "-start-at" resets timestamps so "-stop-at" is really a duration rather than a timestamp
      this_duration=$(echo "$to - $ss" | bc -l)
    elif [[ -n "$ss" ]]; then
      if (($(echo "$ss > $original_duration - 3"  | bc -l))); then #ignore "commercials" of less than 3 seconds at very end. HB seems to have a problem with that
        continue
      fi
      this_duration=$(echo "$original_duration - $ss" | bc -l)
    elif [[ -n "$to" ]]; then
      this_duration="$to"
    else
      this_duration="$duration"
    fi
    if [[ -n "$ss" ]]; then
      ss="--start-at seconds:$ss"
    fi
    if [[ -n "$to" ]]; then
      to="--stop-at seconds:$this_duration"
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

    launch_and_monitor_encoder $(echo "$merge_start_percent * ($progress / $duration)" | bc -l) \
                              $(echo "$merge_start_percent * (($progress + $this_duration) / $duration)" | bc -l) \
                              $this_duration \
                              "$segment_filename" \
                              "$segment_log" \
                              "$encoder_path" \
                              $ss "${encode_opts[@]}" $to

    progress=$(echo "$this_duration + $progress" | bc -l)
  done

  # merge the segments together
  # though this usually happens in under 2 minutes, it could 
  # take longer for larger videos, so track progress for the merge
  launch_and_monitor_encoder $merge_start_percent \
                            100 \
                            $duration \
                            "$output" \
                            "$tmpdir/logs/ffmpeg_concat.log" \
                            "$ffmpeg_path" \
                            -fflags +genpts -f concat -safe 0 -i "$merge_filename" -map 0 -c copy
fi
