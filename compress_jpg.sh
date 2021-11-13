#!/bin/bash

# A list which will either contain each entity given by the user.
# If the user uses the standard input, this list may contain from one to an infinite number of element. Otherwise
# it may only contain one.
# An entity in this case stands for a path or a directory.
# Making no distinction between inputs from the stdin/input allow to share the exact same process further down the pipeline.
entities_path=()


# The list of path to rename & compress (not definitive until treat_all_files is called)
files_path=()

# An optional file extension. If specified, all JPEG files will be renamed with this new extension. Please note
# that if the file does not contain an extension it will be added and that if there already exists a file with the same
# new name, the renaming of the file will be canceled out.
file_extension=''

# A required argument which will be passed down to the Image Picker CLI.
resolution=''

# Whether to loop through each directory in a recursive manner.
recursive=false

# Whether Image Magic should strip all pointless (for the general audience) metadata from the files.
strip=false

# Whether to activate Image Magic advanced log
debug=false

# Whether to ignore a file if it does not exists
ignore=false

# Number of converted files
converted_files=0

# Whether one of the files wasn't converted by Image Magic
has_convert_error=false

# Used at the end to exit with code 3 if one file was missing, not used if ignore is set to false
some_file_did_not_exist=false

BAD_USAGE=1
CONVERT_ERROR=2
FILE_DOES_NOT_EXIST=3

# Formatted usage messages
SHORT_USAGE="\e[1mUSAGE\e[0m
    \e[1m${0}\e[0m [\e[1m-c\e[0m] [\e[1m-r\e[0m] [\e[1m-e\e[0m \e[4mextension\e[0m] \e[4mresolution\e[0m [\e[4mfilename_or_directory\e[0m]
or
    \e[1m${0} --help\e[0m
for detailed help."

USAGE="$SHORT_USAGE

The order of the options does not matter. However, if \e[4mfilename_or_directory\e[0m is given and is a number, it must appear after \e[4mresolution\e[0m.

  \e[1m-c\e[0m, \e[1m--strip\e[0m
    Compress more by removing metadata from the file.

  \e[1m-d\e[0m, \e[1m--debug\e[0m
    Logs Image Magic's errors to the standard input

  \e[1m-i\e[0m, \e[1m--ignore\e[0m
     Whether to ignore a file if it does not exist

  \e[1m-r\e[0m, \e[1m--recursive\e[0m
    If \e[4mfilename_or_directory\e[0m is a directory, recursively compress JPEG in subdirectories.
    Has no effect if \e[4mfilename_or_directory\e[0m is a regular file.
    This option has the same effect when file and directories are given on stdin.

  \e[1m-e\e[0m \e[4mextension\e[0m, \e[1m--ext\e[0m \e[4mextension\e[0m
    Change the extension of processed files to \e[4mextension\e[0m, even if the compression fails or does not actually happen.
    Renaming does not take place if it gives a filename that already exists, nor if the file being processed is not a JPEG file.

  \e[4mresolution\e[0m
    A number indicating the size in pixels of the smallest side.
    Smaller images will not be enlarged, but they will still be potentially compressed.

  \e[4mfilename_or_directory\e[0m
    If a filename is given, the file is compressed. If a directory is given, all the JPEG files in it are compressed.
    Can't begins with a dash (-).
    If it is not given at all, ${0} process files and directories whose name are given on stdin, one by line.

\e[1mDESCRIPTION\e[0m
    Compress the given picture or the jpeg located in the given directory. If none is given, read filenames from stdin, one by line.

\e[1mCOMPRESSION\e[0m
    The file written is a JPEG with quality of 85% and chroma halved. This is a lossy compression to reduce file size. However, it is calculated with precision (so it is not suitable for creating thumbnail collections of large images). The steps of the compression are:

      1. The entire file is read in.
      2. Its color space is converted to a linear space (RGB). This avoids a color shift usually seen when resizing images.
      3. If the smallest side of the image is larger than the given resolution (in pixels), the image is resized so that this side has this size.
      4. The image is converted (back) to the standard sRGB color space.
      5. The image is converted to the frequency domain according to the JPEG algorithm using an accurate Discrete Cosine Transform (DCT is calculated with the float method) and encoded in JPEG 85% quality, chroma halved. (The JPEG produced is progressive: the loading is done on the whole image by improving the quality gradually)."

display_help() {
  echo -e "$USAGE"
  exit 0
}

echo_error() { echo -e "\033[0;31m$*\e[0m" 1>&2; }
echo_success() { echo -e "\033[0;32m$*\e[0m"; }

# Loop through the argument list and extract all settings one by one. The two only exceptions are
# the resolution and the optional path. The case uses a wildcard to match any path/resolution. If the argument
# is an integer it will first be used as the resolution. If a second integer is met while looping it will be use as a
# file path and added to the entities path list.
extract_arguments() {

  # If -h is present in the argument list then display help & exit. This prevents the program from executing any code if the
  # option is present. It could induce some strange behaviour (for instance -ho would also trigger the display_help function).
  if [[ "$*" == *-h* ]]; then
    display_help
  fi

  # While the number of treated arguments is greater than 0, we continue looping through the remaining one,
  # removing them one by one.
  while [[ $# -gt 0 ]]; do
    local arg="$1"

    case $arg in
    -e | --extension)
      file_extension=$2

      # List of allowed extensions, if the file_extension passed down by the user is not contained in it, exit with an error.
      local allowed_file_extensions=(jpeg jpg jpe jif jfif jfi)

      # A treated version of the file extension padded with one space on the left and right side. This is used to force
      # the regex to only return exact match. It also is transformed to its lowercase version before comparing.
      # Please note that this is a local variable and therefore, does not change at all the file_extension desired by the user.
      local file_extension_treated_for_regex=" ${file_extension,,} "

      # Check using a regex if the file_extension is present in the allowed_file_extensions list. If not returns an error.
      if ! [[ " ${allowed_file_extensions[*]} " =~ $file_extension_treated_for_regex ]]; then
        echo_error "Only JPEG extension can be used with the --extension named argument. You used the '$file_extension' while only the following extensions (lowercase/uppercase/capitalize) are accepted: ${allowed_file_extensions[*]}"
        exit $BAD_USAGE
      fi

      shift
      shift
      ;;
    -r | --recursive)
      recursive=true
      shift
      ;;
    -i | --ignore)
      ignore=true
      shift
      ;;
    -c | --strip)
      strip=true
      shift
      ;;
    -d | --debug)
      debug=true
      shift
      ;;
    *)
      if [[ $arg =~ ^[0-9]+$ ]] && [ -z "$resolution" ]; then
        resolution=$arg
      elif ((${#entities_path[@]} == 0)); then
        if [[ "${arg:0:1}" == "-" ]]; then
          echo_error "Unexpected path: $arg, to use a path starting with -, please consider using the standard input."
          exit $BAD_USAGE
        fi

        entities_path+=("$arg")
      else
        echo_error "Unexpected argument: $arg, run this script with -help to display all information."
        exit $BAD_USAGE
      fi
      shift
      ;;
    esac
  done
}

# Add each line of the standard input to the entities path array.
read_files_path_from_stdin() {
  local line

  if ! [ -t 0 ]; then
    while IFS=$'\n' read -r line; do
      entities_path+=("$line")
    done
  fi
}

# Add an entity to files_path only if it is a file
add_to_files_path_if_is_file() {
  if [[ -f "$1" ]]; then
    files_path+=("$1")
  fi
}

# Add an entity to files_path only if it is a JPEG file
add_to_files_path_if_is_file_and_jpeg() {
  if [[ $(file -b "$1") =~ JPEG ]]; then
    add_to_files_path_if_is_file "$1"
  fi
}

# Add all entities in a folder to files_path using add_to_files_path_if_is_file_and_jpeg
# If $2 is true, does it recursively.
retrieve_files_from_folder() {
  for entity in "$1"/*; do
    add_to_files_path_if_is_file_and_jpeg "$entity"

    if [[ -d "$entity" ]]; then
      if [ "$2" == "true" ]; then
        retrieve_files_from_folder "$entity" "$2"
      fi
    fi
  done
}

# Retrieves all files path from a list, directly calls add_to_files_path_if_is_file for first
# order file (directly given by the user)
retrieve_files_path_from_list() {
  files_path=()

  for entity in "$@"; do
    add_to_files_path_if_is_file "$entity"

    if [[ -d "$entity" ]]; then
      retrieve_files_from_folder "$entity" "$2"
    fi
  done
}

# Check if every file present in files_path does exist. If the ignore option
# is set to false, directly exit.
sanitization_check_of_paths() {
  local existing_entities_path=()

  local should_exit=false

  for entity in "$@"; do

    if ! { [ -d "$entity" ] || [ -f "$entity" ]; }; then
      echo_error "'$entity' path does not appear to exist"
      some_file_did_not_exist=true

      if [ $ignore == "false" ]; then
        echo_error "Use -i or --ignore to ignore such errors"

        should_exit=true
      fi

    else
      existing_entities_path+=("$entity")
    fi

  done

  [ $ignore == "true" ] || [ $should_exit == "false" ] || exit $FILE_DOES_NOT_EXIST

  entities_path=("${existing_entities_path[@]}")
}

# Normalize extension of a jpeg file. If a file with the new name already exist, does nothing.
rename_jpeg_file() {
  local did_rename
  if [[ $(file -b "$1") =~ JPEG ]]; then
    local new_file_path="${1%.*}.$file_extension"

    # Only rename the file if there are not file located at the new_path address.
    if ! [[ -f "$new_file_path" ]]; then
      mv "$1" "$new_file_path"
      did_rename=1
    fi
  fi

  if [ "$did_rename" == "1" ]; then
    echo "$new_file_path"
  else
    echo "$1"
  fi
}

# Convert & compress a file with Image Magic. If the file does not weight less than the old file, nothing is done.
convert_and_compress_file() {
  local temp_output
  temp_output=$(mktemp)

  local extra_arg=''

  if [ "$strip" == 'true' ]; then
    extra_arg='-strip '
  fi

  if [ $debug == 'true' ]; then
    extra_arg="$extra_arg -debug coder"
  fi

  local command="convert -auto-orient -colorspace RGB $1 -resize ${resolution}x${resolution} $extra_arg -quality 85% -colorspace sRGB -interlace Plane -define jpeg:dct-method=float -sampling-factor 4:2:0 $temp_output"

  if ! $command; then
    echo_error "Image Magic wasn't able to convert $1. The file was left untouched."
    has_convert_error=true
  else

    local converted_file_size
    converted_file_size=$(stat -c%s "$temp_output")

    local original_file_size
    original_file_size=$(stat -c%s "$1")

    if [[ "$converted_file_size" -lt "$original_file_size" ]]; then
      rm "$1"
      cp "$temp_output" "$1"
      converted_files=$((converted_files + 1))
    else
      echo "Not compressed. File left untouched. (normal)"
    fi

  fi

  rm "$temp_output"
}

# Rename, convert & compress all files contained in files_path.
treat_all_files() {
  for file_path in "${files_path[@]}"; do
    if [ -n "$file_extension" ]; then
      file_path=$(rename_jpeg_file "$file_path")
    fi

    echo "$file_path"

    convert_and_compress_file "$file_path"
  done

  echo_success "$converted_files/${#files_path[@]} converted files"

  if [ $some_file_did_not_exist == "true" ]; then
    exit $FILE_DOES_NOT_EXIST
  fi

  if [ $has_convert_error == "true" ]; then
    exit $CONVERT_ERROR
  fi
}

# Parse all arguments
extract_arguments "$@"

# If there were no input file, extract files from the stdin.
if ((${#entities_path[@]} == 0)); then
  read_files_path_from_stdin
fi

# If there were no files provided in the stdin/no input file as argument, exit the program
if ((${#entities_path[@]} == 0)); then
  echo_error "Please specify a file or a folder. To specify multiple files and folders use the standard input."
  exit $BAD_USAGE
fi

# Check if there is a resolution specified otherwise
if [ -z "$resolution" ]; then
  echo_error "Please specify a resolution."
  exit $BAD_USAGE
fi

sanitization_check_of_paths "${entities_path[@]}"

retrieve_files_path_from_list "${entities_path[@]}" $recursive


treat_all_files
