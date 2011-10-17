#!/bin/bash
# ----------------------------------------------------------------------------#
# Copyright (c) 2011 Jason Kit                                                #
#                                                                             #																	
# Permission is hereby granted, free of charge, to any person obtaining       #
# a copy of this software and associated documentation files (the "Software"),#
# to deal in the Software without restriction, including without limitation   #
# the rights to use, copy, modify, merge, publish, distribute, sublicense,    #
# and/or sell copies of the Software, and to permit persons to whom the       #
# Software is furnished to do so, subject to the following conditions:        #
#                                                                             #
# The above copyright notice and this permission notice shall be included in  #
# all copies or substantial portions of the Software.                         #
#                                                                             #
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR  #
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,    #
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE #
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER      #
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING     #
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER         #
# DEALINGS IN THE SOFTWARE.                                                   #
# ----------------------------------------------------------------------------#

# -----------------------------------------------------------------------------
# Pring Usage and exit
# -----------------------------------------------------------------------------
function print_usage {
	echo "Usgae: splitdl <url> <number of conntection> [output file path]"
	exit
}

# -----------------------------------------------------------------------------
# Update console to print the progress bar
# Use following global variable:
# row, part_prefix, chunk_size, last_chunk_size, length, m
# -----------------------------------------------------------------------------
function print_progress {
	totalsize=0
	
	# length of progress bar
	div=50
	
	i=1
	while [ "$i" -le "$m" ]
	do
		part_size=`stat -f %z $part_prefix$i`	
		totalsize=`expr $totalsize + $part_size`
		trow=`echo "$row - $m - 2 + $i" | bc`
		tput cup $trow 0

		if [ "$i" -lt "$m" ]; then
			progress=`echo "$part_size*100/$chunk_size" | bc`
		else
			progress=`echo "$part_size*100/$last_chunk_size" | bc`
		fi

		nbar=`echo "$div*$progress/100" | bc`

		if [ "$nbar" -eq "0" ]; then
			nbar=1
		fi

		cnbar=`expr $div - $nbar`

		progress_bar=`printf "%${nbar}s" "#" | sed "s/ /#/g"`
		progress_bar=`printf "$progress_bar%${cnbar}s" ""`

		printf "[%04d] %s [ %3d%% ]\n" $i "$progress_bar" $progress

		i=`expr $i + 1`
	done

	echo "Total: $totalsize/$length [ `echo "$totalsize*100/$length" | bc`%]"
}

#Target URL
url=$1
#Number of Split
m=$2
#Output file path
o=$3

prefix_file=`mktemp /tmp/splitdl.XXXXXX`
part_prefix="$header_file.part."
# Actually we don't need the prefix_file, we just use mktemp to generate unique file name
rm $prefix_file

if [ "$#" -lt 2 ]; then
	print_usage
fi

if `echo $m | grep -q [^[:digit:]]`; then
	print_usage
fi

if [ "$o" == "" ]; then
	o=`basename $url`
fi

# Obtain Remove file size
length=`curl -Is $url | 
		grep "Content-Length:" | 
		sed "s/Content-Length: //g" | tr -d "\n\r"`

if [ "$length" == "" ]; then
	echo "Cannot resolve remte file size."
	exit
fi

# Calculate chunk size
chunk_size=`expr $length / $m`

# Last chunk size may be larger
last_chunk_size=`echo "$length - ($chunk_size*($m-1))" | bc`

# Print the download information
echo "From: $url"
echo "Download To: $o"
echo "Connection: $m"
echo "Chunk Size: $chunk_size"

# Confirm Download
while [ "1" == "1" ]
do
	echo "Confirm download? (Y/N)"
	read confirm
	if [ "$confirm" == "Y" ]; then
		break
	elif [ "$confirm" == "N" ]; then
		exit
	fi
done

# For merging part files
part_file_list=""

# spwan curl progress for each part
i=1
while [ "$i" -le "$m" ]
do
	touch "$part_prefix$i"
	printf "[%04d]\n" $i

	head=`echo "($i-1)*$chunk_size" | bc`

	if [ "$i" -lt "$m" ]; then
		part_file_list="$part_file_list$part_prefix$i "
		end=`echo "$i*$chunk_size-1" | bc`
		curl --range $head-$end -s -o $part_prefix$i $url & 
	else
		# handle the last chunk
		part_file_list="$part_file_list$part_prefix$i"
		curl --range $head- -s -o $part_prefix$i $url & 
	fi

	i=`expr $i + 1`
done

# Record the current cursor postion for displaying progress bar
echo -en "\033[6n"
read -sdR CURPOS
row=`echo ${CURPOS#*[} | sed "s/;.*//g"`

# Here if jobslist is clear, all the background curl process is done
# Not using wait is because we need to update progress bar
jobslist=`jobs`
while [ "$jobslist" != "" ]
do
	sleep 1
	# seems we need to call jobs to flush the jobs list so that jobslist 
	# can obtain empty string
	jobs > /dev/null
	jobslist=`jobs`
	print_progress
done
# Print progress bar once more to make sure everything show 100%
print_progress

# Merge each part to the result output file
cat $part_file_list > $o

# Clean up
rm $part_prefix*
echo "Finish Download"
