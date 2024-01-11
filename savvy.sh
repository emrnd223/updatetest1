#!/bin/bash

#command line arguments:
#startup
#network_status
#update 
#   -usb
#   -git
#   -customer
#   -provision
#   -timezone
#room_number
#sleep
#   -start
#   -end

cd /home/savvy/

#run anything here once at startup
if [[ -f /home/savvy/runonce ]]; then
    rm /home/savvy/runonce
    /home/savvy/savvy.sh update customer
fi

#STARTUP FUNCTIONS AND VARIABLES DEFINED
if [[ $1 == 'startup' ]]; then
    #define SSID variables
    SSID1="EM_GUEST" #test wifi ssid
    PASS1="ElectricMirror.com" #test wifi password
    SSID3="EMSETUP" #customer setup wifi
    PASS3="ELECTRICMIRROR" #customer setup password
    if [[ -s /home/savvy/customer_info ]]; then
        SSID2="$(jq .ssid /home/savvy/customer_info | sed 's/^\"//; s/\"$//')" #customer wifi ssid
        PASS2="$(jq .wifiPassword /home/savvy/customer_info | sed 's/^\"//; s/\"$//')" #customer wifi password
        if [[ "$SSID2" = 'fake' ]]; then
            SSID2=''
            PASS2=''
        fi
    fi

    #define variable for wifi dongle ifname
    DONGLE=`nmcli device | grep 'wifi ' | awk '{print $1}'`

    wificleanup () {
        #removes all nmcli wifi connections
        CURWIFI=$(nmcli con show | grep wifi | awk -F "  " '{print $1}' | sed 1q)
        until [[ "$CURWIFI" = '' ]]
        do
            nmcli con delete "$CURWIFI"
            CURWIFI=$(nmcli con show | grep wifi | awk -F "  " '{print $1}' | sed 1q)
        done
    }

    setupwifi () {
        #add SSID and password information to network manager
        nmcli con add con-name "$1" ifname $DONGLE type wifi ssid "$1" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$2"

        sleep 2

        #if third argument exists, connect to this wifi immediately (may not work reliably with dongle)
        if [ $3 ]; then
            nmcli con up "$1"
        fi
    }

    logcleanup () {
        #trim file ($1) to last n ($2) lines 
        if [[ -s $1 ]]; then
            tail -n $2 $1 > $1-tmp
            mv -f $1-tmp $1
        fi
    }

    nohangfirefox () {
        #check if firefox directory exists
        FFPATH=$(find /home/savvy/.mozilla/firefox* -type d -name *default-esr* 2>/dev/null)
        if [[ -d $FFPATH ]]; then
            if [[ -f $FFPATH/prefs.js ]]; then
                #delete line from prefs.js that causes firefox to show an error message
                sed -i '/last_success/d' $FFPATH/prefs.js
            fi
        fi
    }
fi
#STARTUP FUNCTIONS END


#NETWORK CHECK START
if [[ $1 == 'network_status' ]]; then

    NETWORK=`echo "$(nmcli device | grep 'wifi ' | awk '{print $3}') $(nmcli device | grep ethernet | awk '{print $3}')" | grep -w connected`

    if [ "$NETWORK" = '' ]; then
        #no network or wrong ifname
        echo "not connected to network"
        #define necessary variables and functions to configure wireless network in this script's scope
        . /home/savvy/savvy.sh startup

        #cycle through all stored wifi networks and check for correct dongle
        nmcli con show | grep wifi | awk -F "  " '{print $1}' | while read profile; do
            IFNAMEPROFILE="$(nmcli con show "$profile" | grep interface-name | awk '{print $2}')"
            if [[ $DONGLE != $IFNAMEPROFILE ]]; then
                #get password from profile
                PASSWORD=`nmcli con show "$profile" --show-secrets | grep wireless-security.psk: | awk -F "  " '{print $NF}' | sed 's/^ *//'`
                echo "dongle wrongle $profile"
                #remove existing wifi profile
                nmcli con delete "$profile"

                #add new wifi profile with new dongle
                setupwifi "$profile" "$PASSWORD"
                sleep 1
                #connect to profile if SSID is broadcasting
                if [[ "$(nmcli device wifi list | grep '$profile')" ]]; then
                    nmcli con up "$profile"
                    sleep 1
                fi
            fi
        done

        #check that all primary SSIDs are listed by network manager and set them up if not
        if [[ $(nmcli con show | grep "$SSID1") ]]; then
            #check that password is correct
            if [[ $(nmcli con show "$SSID1" --show-secrets | grep wireless-security.psk: | awk -F : '{print $2}' | sed 's/^ *//') != "$PASS1" ]]; then
                setupwifi "$SSID1" "$PASS1"
            fi
        else
            setupwifi "$SSID1" "$PASS1"
        fi

        if [[ $(nmcli con show | grep "$SSID3") ]]; then
            if [[ $(nmcli con show "$SSID3" --show-secrets | grep wireless-security.psk: | awk -F : '{print $2}' | sed 's/^ *//') != "$PASS3" ]]; then
                setupwifi "$SSID3" "$PASS3"
            fi
        else
            setupwifi "$SSID3" "$PASS3"
        fi

        if [[ "$SSID2" ]]; then
            if [[ $(nmcli con show | grep "$SSID2") ]]; then
                if [[ $(nmcli con show "$SSID2" --show-secrets | grep wireless-security.psk: | awk -F : '{print $2}' | sed 's/^ *//') != "$PASS2" ]]; then
                    setupwifi "$SSID2" "$PASS2"
                fi
            else
                setupwifi "$SSID2" "$PASS2"
            fi
        fi

        #check if startx didn't launch firefox due to no available network
        if [[ -f /home/savvy/nobrowser ]]; then
            if [[ "$SSID2" ]]; then
                #check if SSID2 is broadcasting and visible
                WIFIVAR=$(nmcli device wifi list | grep "$SSID2")

                if [ "$WIFIVAR" ]; then
                    nmcli con up "$SSID2"
                    sleep 3
                else
                    echo "wifi SSID $SSID2 not visible"
                fi

            NETWORK=`echo "$(nmcli device | grep 'wifi ' | awk '{print $3}') $(nmcli device | grep ethernet | awk '{print $3}')" | grep -w connected`
                #if network is now available restart device
                if [[ "$NETWORK" ]]; then
                    reboot
                fi
            fi
        fi
    elif [ -f /home/savvy/nobrowser ]; then
        #network is connected, but there wasn't internet when startx launched
        #this should mean the offlinenet.png image is being displayed and the device needs to be reset if internet is restored
        INTERNET=$(ping -c 2 8.8.8.8 | grep time=)
        if [[ "$INTERNET" != '' ]]; then
            reboot
        fi
    fi
fi
#NETWORK CHECK END


#UPDATE SCRIPT START
if [[ $1 == 'update' ]]; then
    #updatefile $1=filename $2=permissions $3=path to replacement file $4=path to file to be replaced
    updatefile () {

    if [ -f $3$1 ]; then
        if [ -f $4$1 ]; then
            #if both files exist, compare them
            FILECMP=$(cmp $3$1 $4$1 2>&1)
        else
            FILECMP="no file on system"
        fi
        if [ "$FILECMP" ]; then
            echo "$1 is different"
            FILESDIFFERENT=TRUE
            if [ -f $4$1 ]; then
                echo "backing up $1"
                mkdir -p /home/savvy/backup/ && mv $4$1 /home/savvy/backup/$1_bak
            fi
            echo "copying $1 from $3"
            cp $3$1 $4$1
            chown savvy:savvy $4$1
            chmod $2 $4$1
        fi
    fi
    }
    #updatefile() end

    #USB UPDATE SCRIPT
    if [[ $2 == 'usb' ]]; then
        USBSTICK=$(fdisk -l | grep /dev/sd)
        echo $USBSTICK
        if [ "$USBSTICK" ]; then
            echo "yes USB stick"
            DRIVEID=$(echo $USBSTICK | awk '{print $9}')
            if [ -d /media/savvyUSB ]; then
                echo "path exists - mounting USB"
            else
                mkdir -p /media/savvyUSB
            fi
            mount $DRIVEID /media/savvyUSB

            #update the main script before any other files
            if [ -f /media/savvyUSB/savvy.sh ]; then
                updatefile savvy.sh 755 /media/savvyUSB/ /home/savvy/
            fi

            if [ "$FILESDIFFERENT" ]; then
                #skip until next cycle
                echo "savvy.sh updated"
                touch /home/savvy/rebootflag
            else
                updatefile .bashrc 644 /media/savvyUSB/ /home/savvy/
                updatefile .xsession 644 /media/savvyUSB/ /home/savvy/
                updatefile emlogo.png 644 /media/savvyUSB/ /home/savvy/
                updatefile offline.png 644 /media/savvyUSB/ /home/savvy/
                updatefile offlinenet.png 644 /media/savvyUSB/ /home/savvy/
                updatefile .url 644 /media/savvyUSB/ /home/savvy/

                USERJSPATH=$(find /home/savvy/.mozilla/firefox* -type d -name *default-esr*)
                echo "userjspath=$USERJSPATH"
                if [[ -d $USERJSPATH ]]; then
                    updatefile user.js 644 /media/savvyUSB/ $USERJSPATH/
                fi

                if [[ "$FILESDIFFERENT" || -f /home/savvy/rebootflag ]]; then
                    echo "files were updated - rebooting in 3s"
                    rm /home/savvy/rebootflag
                    umount $DRIVEID
                    sleep 3
                    reboot
                fi
            fi
        fi
    fi
    #USB UPDATE END


    #GIT UPDATE
    if [[ $2 == 'git' ]]; then
        #update main files via git
        #the /updatetest1 path needs to be updated if production repo is named something else
        cd /home/savvy/updatetest1
        mkdir -p /home/savvy/backup/
        git pull >> /home/savvy/backup/update_record
        truncate -s-1 /home/savvy/backup/update_record
        echo " $(date)" >> /home/savvy/backup/update_record
    TAG=$(git tag | tail -n 1)
    if [[ $(grep Release /home/savvy/device_info | awk '{print $2}' FS=': ') != $TAG ]]; then
        sed -i "/Release/cRelease tag: $TAG" /home/savvy/device_info
    fi

        updatefile savvy.sh 755 /home/savvy/updatetest1/ /home/savvy/
        updatefile .bashrc 644 /home/savvy/updatetest1/ /home/savvy/
        updatefile .xsession 644 /home/savvy/updatetest1/ /home/savvy/
        updatefile emlogo.png 644 /home/savvy/updatetest1/ /home/savvy/
        updatefile offline.png 644 /home/savvy/updatetest1/ /home/savvy/
        updatefile offlinenet.png 644 /home/savvy/updatetest1/ /home/savvy/

        USERJSPATH=$(find /home/savvy/.mozilla/firefox* -type d -name *default-esr* 2>/dev/null)
        if [[ -d $USERJSPATH ]]; then
            updatefile user.js 644 /home/savvy/updatetest1/ $USERJSPATH/
        fi

        if [[ "$FILESDIFFERENT" ]]; then
            #update log file
            echo "Git update at $(date)" >> /home/savvy/backup/update_record
        fi
    fi
    #END OF GIT UPDATE


    #CUSTOMER INFO UPDATE 
    if [[ $2 == 'customer' ]]; then
        if [[ -s /home/savvy/.url ]]; then
            #define customer path from .url file works for full url or just the slug
            CUSTWEB=$(cat /home/savvy/.url | awk '{ print $NF }' FS='\/')

            #download customer data
            cd /home/savvy/
            wget -N --wait=180 --random-wait https://savvy-configs.s3.us-west-2.amazonaws.com/$CUSTWEB.json
            #if last command exited with code 0 (no errors), decode json file, write to customer_info
            if [[ $? == 0 ]]; then
                base64 -d /home/savvy/$CUSTWEB.json | jq > /home/savvy/customer_info
            fi

            #remove customer_info file if it's empty
            if [[ ! -s /home/savvy/customer_info ]]; then
                rm /home/savvy/customer_info
            #if not empty, update screen sleep schedule
            else
                #define variables
                SLEEPENABLED=$(jq .sleepEnabled /home/savvy/customer_info | sed 's/^\"//; s/\"$//')
                SLEEPSTART=$(jq .sleepStart /home/savvy/customer_info | sed 's/^\"//; s/\"$//')
                SLEEPEND=$(jq .sleepEnd /home/savvy/customer_info | sed 's/^\"//; s/\"$//')
                SLEEPENDMIN=$(echo $SLEEPEND | cut -c 3-4)
                SLEEPENDHOUR=$(echo $SLEEPEND | cut -c 1-2)

                if [[ $SLEEPEND && $SLEEPENABLED = 'true' ]]; then
                    #update reboot time
                    sed -i "/root reboot/c`echo $SLEEPENDMIN` `echo $SLEEPENDHOUR` * * * root reboot" /etc/crontab
                    sed -i "/savvy echo/c`echo $SLEEPENDMIN` `echo $SLEEPENDHOUR` * * * savvy echo \"System reset at \$(date)\" >> cron_last_reset" /etc/crontab
                    #redefine variables for a git update 10 minutes before reset
                    if [[ $SLEEPENDMIN -lt 10 ]]; then
                        if [[ $SLEEPENDHOUR -gt 0 ]]; then
                            SLEEPENDHOUR=$(($SLEEPENDHOUR-1))
                        else #hour is zero
                            SLEEPENDHOUR=23
                        fi
                        SLEEPENDMIN=$(($SLEEPENDMIN+50))
                    else
                        SLEEPENDMIN=$(($SLEEPENDMIN-10))
                    fi
                    sed -i "/update git/c$SLEEPENDMIN $SLEEPENDHOUR * * * root /home/savvy/savvy.sh update git" /etc/crontab
                fi

                if [[ $SLEEPSTART ]]; then
                    #if sleep start hasn't been set up in crontab, set it up
                    if [[ ! $(sed -n '/sleep start/p' /etc/crontab) ]]; then
                        sed -i "/provision/a`echo $SLEEPSTART | cut -c 3-4` `echo $SLEEPSTART | cut -c 1-2` * * * savvy /home/savvy/savvy.sh sleep start" /etc/crontab
                    #if sleep start already exists in crontab, update it
                    else
                        sed -i "/sleep start/c`echo $SLEEPSTART | cut -c 3-4` `echo $SLEEPSTART | cut -c 1-2` * * * savvy /home/savvy/savvy.sh sleep start" /etc/crontab
                    fi
                fi

                if [[ $SLEEPENABLED = 'true' ]]; then
                    #sleep schedule enabled-uncomment line in crontab
                    sed -i '/sleep/s/#//g' /etc/crontab
                else
                    #sleep disabled-comment it out in crontab
                    sed -i '/sleep/s/^/#/' /etc/crontab

                    #if sleep is off, set reboot to the default of 1pm local 
                    sed -i "/root reboot/c0 13 * * * root reboot" /etc/crontab
                    sed -i "/savvy echo/c0 13 * * * savvy echo \"System reset at \$(date)\" >> cron_last_reset" /etc/crontab
                    #update git 10 minutes before reboot
                    sed -i "/update git/c50 12 * * * root /home/savvy/savvy.sh update git" /etc/crontab
                fi
            fi
        fi
        #update room number
        /home/savvy/savvy.sh room_number

        #update serial number
        if [[ $(cat /sys/devices/platform/firmware\:secure-monitor/serial) != $(cat /home/savvy/device_info | grep Serial | awk -F : '{print $2}' | sed 's/^ *//') ]]; then
            sed -i "/Serial/cSerial number: $(cat /sys/devices/platform/firmware\:secure-monitor/serial)" /home/savvy/device_info
        fi
    fi
    #CUSTOMER INFO END


    #PROVISIONING START
    if [[ $2 == 'provision' ]]; then
        . /home/savvy/savvy.sh startup
        CURWIFI=$(nmcli con show | sed '2q;d' | awk -F "  " '{print $1}')
        #don't update json if SSID2 is already connected (it will be done automatically at midnight)
        if [[ "$CURWIFI" != "$SSID2" ]]; then
            #if current network is EMSETUP
            if [[ "$CURWIFI" = "$SSID3" ]]; then
                if [[ -s /home/savvy/.url ]]; then
                    #define customer path from .url file
                    CUSTWEB=$(cat /home/savvy/.url | awk '{ print $NF }' FS='\/')

                    #download customer data
                    cd /home/savvy/
                    #overwrite any existing file of the same name
                    wget -O --wait=180 --random-wait ./$CUSTWEB.json https://savvy-configs.s3.us-west-2.amazonaws.com/$CUSTWEB.json
                    #if last command exited with code 0 (no errors), decode json file, write to customer_info
                    if [[ $? == 0 ]]; then
                        base64 -d /home/savvy/$CUSTWEB.json | jq > /home/savvy/customer_info
                    fi

                    #remove customer_info file if it's empty
                    if [[ ! -s /home/savvy/customer_info ]]; then
                        rm /home/savvy/customer_info
                    #otherwise proceed to wificleanup and reboot
                    else
                        #if there are more than 25 stored networks listed, delete all wifi profiles and start over
                        if [[ `echo $(nmcli -f NAME con show) | awk '{print NF}'` -gt 25 ]]; then
                            #clean up wifi if total fields exceed 25
                            wificleanup
                        fi
                        #reboot to show that customer_info was updated 
                        reboot
                    fi
                fi
            fi
        fi
    fi
    #PROVISIONING END


    #TIMEZONE
    if [[ $2 == 'timezone' ]]; then
        #if customer_info is a non-empty file
        if [[ -s /home/savvy/customer_info ]]; then
            #if current timezone not the same as what is on timezone line of customer_info
            if [[ $(timedatectl | grep Time | awk '{print $3}') != $(jq .timezone /home/savvy/customer_info | sed 's/^\"//; s/\"$//') ]]; then
            timedatectl set-timezone $(jq .timezone /home/savvy/customer_info | sed 's/^\"//; s/\"//' )
            timedatectl set-ntp true
            fi
        fi
    fi
    #TIMEZONE END
fi
#END OF UPDATE SCRIPT


#START OF ROOM NUMBER
if [[ $1 == 'room_number' ]]; then
    ROOMPATH=$(find /home/savvy/.mozilla/ -type d -name *awsapprunner.com 2>/dev/null)
    if [[ "$ROOMPATH" ]]; then
        cd $ROOMPATH/ls

        if [[ -s data.sqlite ]]; then
            #create a temporary file containing the sqlite plain text
            cat data.sqlite | sed "s/[^[:print:]]//g" | sed -n '/Number/p' > tempfile
            #remove non-ASCII characters
            iconv -t ASCII -c -o tempfile tempfile

            #if tempfile is not empty, extract room number and write to device_info
            if [[ -s tempfile ]]; then
                #extract room number from tempfile
                ROOMNUMBER=$(cat tempfile | awk -F 'Number":"' '{print $2}' | awk -F '","show' '{print $1}'

                #write room number to device_info
                sed -i "/Room/cRoom number: $ROOMNUMBER" /home/savvy/device_info
                #note: when extracting room number from device_info, use a command like the following
                #  ROOMNUMBER=$(cat device_info | grep Room | sed 's/Room number: //')
                #to ignore any colons followed by spaces that could appear in a room name
            fi
        fi
    fi
fi
#END OF ROOM NUMBER

#START OF SLEEP
#$2='start' to turn screen off, 'end' to turn screen on
if [[ $1 = 'sleep' ]]; then
    export DISPLAY=:0.0
    if [[ $2 = 'start' ]]; then
        xrandr --output HDMI-1 --off
    else #turn screen on
        xrandr --output HDMI-1 --auto
        xrandr -s 800x480
    fi
fi
#END OF SLEEP
