#!/bin/bash

# Transmission BitTorrent blocklist downloader
# Copyright (C) 2018  Pekka Helenius
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

###########################################################################

# TODO Remove duplicate IP's from list files (does Transmission do this automatically?)

# TODO Support more archive/text formats
# Only zip & gz archives are currently supported

# TODO "Older than XX days" check not always working?

###########################################################################

# Usage:

# bash transmission_blocklists.sh
# bash transmission_blocklists.sh -y

# where -y parameter passes all Yes/No questions with auto-yes answer
# Exception: internet connection test

# Requirements:

# Unix-based OS
# Bash shell 4.0 or above
# Internet connection
# Transmission client installed
# gzip

###########################################################################

# BLOCKLISTS
typeset -A BLOCKLISTS

#####################################
# Blocklist syntax:

# [list_1-friendly-name]="list_1_URL"
# [list_2-friendly-name]="list_2_URL"
# ...

# where list_URL must point to some of the following archive types: zip, gz

# For example:

# [Yoyo-adservers]="http://list.iblocklist.com/?list=zhogegszwduurnvsyhdf&fileformat=p2p&archiveformat=gz"

#####################################

BLOCKLISTS=(
[Yoyo-adservers]="http://list.iblocklist.com/?list=zhogegszwduurnvsyhdf&fileformat=p2p&archiveformat=gz"
)

###########################################################################

# Basic configuration

# Older blocklist files than this should be updated. Value in days.
UPDATELIMIT_DAYS=15

# Timeout for wget in getfile function, seconds
WGET_TIMEOUT=30

# Transmission client blocklist directory for the current user
TRANSMISSION_BLOCKLISTDIR=$HOME/.config/transmission/blocklists/

# We need to make internet connection test. The following URL is used for
# testing.
TEST_PROVIDER="www.github.com"

###########################################################################

if [[ $1 == "-y" ]]; then
    autoyes=''
fi

###########################################################################

# Commands required by this script

COMMANDS=(bash transmission-cli wget gzip date find kill awk sed grep ping unzip mv wc)

for command in "${COMMANDS[@]}"; do
    
    if [[ $(echo $(which "${command}" &>/dev/null)$?) -ne 0 ]]; then
        echo "Command ${command} not found. Can't run the script."
        exit 1
    fi

done

###########################################################################

for transmission_bin in transmission-qt transmission-gtk; do

    if [[ $(pidof $transmission_bin | wc -l) -ne 0 ]]; then
        echo -e "\nClose all running Transmission client instances and run this script again.\n"
        exit 1
    fi

done

DAYS_AGO=$(date -d "now - $UPDATELIMIT_DAYS days" +%s)

###########################################################################

# Check bash version

BASH_CHECK=$(ps | grep `echo $$` | awk '{ print $4 }')
if [ ${BASH_CHECK} != "bash" ]; then
    echo  "
Please run this script using bash (/usr/bin/bash).
    "
    exit 1
else
    if [[ $(bash --version | sed -n '1p' | awk '{print $4}' | sed 's/\..*$//g') -lt 4 ]]; then
        echo "Use bash version 4 or newer."
        exit
    fi
fi

###########################################################################

# Internet connection test

CONNECTION=false

while [[ $CONNECTION == "false" ]]; do

    INTERNET_TEST=$(ping -c 1 ${TEST_PROVIDER} 2>&1 | grep -c "Name or service not known")
    if [[ ! $INTERNET_TEST -eq 0 ]]; then
        echo -e "\nCan't connect to ${TEST_PROVIDER}. Please check your internet connection and try again.\n"
        read -r -p "Retry connection? [y/N] " connect_answer
        if [[ ! $(echo $connect_answer | sed 's/ //g') =~ ^([yY][eE][sS]|[yY])$ ]]; then
            exit
        fi
    else
        CONNECTION="true"
    fi
done

###########################################################################

# Delete all old bin files which are not in the list above

if [[ $(find "${TRANSMISSION_BLOCKLISTDIR}" -type f -iname "*.bin") ]]; then

    p=0
    for oldfile in $(find "${TRANSMISSION_BLOCKLISTDIR}" -type f -iname "*.bin"); do
        COMPLISTS[$p]=$(echo ${oldfile} | sed 's/.*\///; s/\.[^.]*$//')
        let p++
    done

    typeset -A DIFFARRAY
    a=0
    for olditem in "${COMPLISTS[@]}"; do
        skip=
        for item in "${!BLOCKLISTS[@]}"; do
            if [[ ${olditem} == ${item} ]]; then
                skip=1
                break
            fi
        done
        [[ -n $skip ]] || DIFFARRAY[$a]=${olditem}
        let a++
    done

    if [[ "${#DIFFARRAY[@]}" -ne 0 ]]; then
        for delfile in "${DIFFARRAY[@]}"; do
            rm "${TRANSMISSION_BLOCKLISTDIR}/${delfile}.bin"
            echo -e "Deleted old blocklist '${delfile}'."
        done
    fi

fi
############################################################

i=1
itemcount="${#BLOCKLISTS[@]}"

for listfile in "${!BLOCKLISTS[@]}"; do

    listfile_bin=$(printf '%s%s.bin' "${TRANSMISSION_BLOCKLISTDIR}" "${listfile}")
    listfile_url=$(printf '%s' "${BLOCKLISTS[$listfile]}")

    function getfile() {

        # TODO check existence of '&' symbol?
        if [[ $(wget -S --timeout=${WGET_TIMEOUT} --spider $(echo "${listfile_url}" | awk -F "&" '{print $1}') 2>&1 | grep 'Remote file exists' | wc -l) -ge 1 ]]; then
            echo "$i/$itemcount - Downloading blocklist '${listfile}'"
            wget -q --show-progress -O - "$listfile_url" > "${TRANSMISSION_BLOCKLISTDIR}/${listfile}"
            
            MIMETYPE=$(mimetype "${TRANSMISSION_BLOCKLISTDIR}/$listfile" | awk '{print $2}')
            if [[ $MIMETYPE == "application/gzip" ]]; then
                #This is only for gzip...
                mv "${TRANSMISSION_BLOCKLISTDIR}"/$listfile "${TRANSMISSION_BLOCKLISTDIR}/$listfile.gz"
                gzip -d "${TRANSMISSION_BLOCKLISTDIR}/$listfile.gz"

            elif [[ $MIMETYPE == "application/zip" ]]; then
                unzip -o -qq "${TRANSMISSION_BLOCKLISTDIR}/$listfile" -d "${TRANSMISSION_BLOCKLISTDIR}"
            fi
            
        else
            echo "$i/$itemcount - Couldn't find blocklist '$listfile'. Please check and either update or delete URL of this file."
            
            if [[ ! -v autoyes ]]; then
                read -r -p "Continue? [y/N] " response
            else
                response="y"
            fi
                
            if [[ ! $(echo $response | sed 's/ //g') =~ ^([yY][eE][sS]|[yY])$ ]]; then
                exit
            fi
        fi
    }
    
    # Check existence of old blocklist files.
    if [[ -f "${listfile_bin}" ]]; then
    
        # File creation time
        listfiletime=$(date -r "${listfile_bin}" +%s)

        if [[ $listfiletime -le $DAYS_AGO ]]; then
            echo -e "$i/$itemcount - Blocklist '$listfile' is older than $UPDATELIMIT_DAYS days.\nChecking if newer version exists."
            getfile
        else
            echo -e "$i/$itemcount - Blocklist '$listfile' is already updated."
        fi

    else
        getfile
    fi
    let i++
    
done

# Generates blocklist.bin
# Transmission doesn't have any internal switch to generate only blocklists so
# we launch the client with invalid torrent parameter 'dummy'
# Blocklist gets generated automatically after which the torrent file gets loaded
# into the program. Because there is no an actual torrent file, we get
# "Unrecognized torrent" error, in which case we kill the program
# Before this error is reached, Transmission has generated a correct blocklist file.
# This is just a dirty workaround.
#
transmission-cli -b dummytorrent |& while read -r line; do 
    if [[ $(echo ${line} | grep "Unrecognized torrent" | wc -l) -eq 1 ]]; then
        kill $(pidof transmission-cli) 2> /dev/null
    fi
done

#for listfile in "${!BLOCKLISTS[@]}"; do
#    if [[ -f $TRANSMISSION_BLOCKLISTDIR/$listfile ]]; then
#        rm $TRANSMISSION_BLOCKLISTDIR/$listfile
#    fi
#done

# If not a bin file...
find $TRANSMISSION_BLOCKLISTDIR -type f ! -iname '*.bin' -delete

for file in $(ls $TRANSMISSION_BLOCKLISTDIR/*.bin); do 
    # If bin files are empty...
    if [[ ! -s ${file} ]]; then 
        rm ${file}
    fi
    
    # Delete the following patterns in the names of existing .bin files. This is just because the names must match with the array LISTS keys
    # For example ipfilter_AAA.p2p.bin -> ipfilter_AAA.bin -> ipfilter_AAA -> matches BLOCKLISTS array key
    #
    pattern=".p2p"
    if [[ ${file} =~ $pattern ]]; then
        mv ${file} $(echo ${file} | sed 's/\.p2p//g')
    fi
done

unset autoyes
unset response
unset connect_answer
unset BLOCKLISTS
