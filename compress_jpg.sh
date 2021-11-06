#!/bin/bash

files_path=()

declare file_extension
declare resolution

recursive=false
strip=false

display_help() {
  echo 'Help'
}

read_arguments() {
  # While the number of treated arguments is greater than 0, we continue looping through the remaining one,
  # removing them one by one.
  while [[ $# -gt 0 ]]; do
    local arg="$1"

    case $arg in
    -h | --help | help)
      display_help
      exit
      ;;
    -e | --extension)
      file_extension=$2
      shift
      shift
      ;;
    -r | --recursive)
      recursive=true
      shift
      ;;
    -s | --strip)
      strip=true
      shift
      ;;
    *)
      if [[ $arg =~ ^[0-9]+$ ]] && [ -z "$resolution" ]; then
        resolution=$arg
      elif ((${#files_path[@]} == 0)); then
        files_path+=("$arg")
      else
        echo "Unexpected argument: $arg, run this script with the help argument to display all information."
        exit
      fi
      shift
      ;;
    esac
  done
}

read_files_path_from_stdin() {
  local line

  if ! [ -t 0 ]; then
    while IFS='$\n' read -r line; do
      files_path+=("$line")
    done
  fi
}

read_arguments "$@"

if ((${#files_path[@]} == 0)); then
  read_files_path_from_stdin
fi

if ((${#files_path[@]} == 0)); then
  echo "Please specify a file or a folder. To specify multiple files and folders use the standard input."
  exit
fi

if [ -z "$resolution" ]; then
  echo "Please specify a resolution."
  exit
fi

echo "
  Arguments:
      - files_path: ${files_path[@]}
      - extension: $file_extension
      - resolution: $resolution
      - strip: $strip
      - recursive: $recursive
"
