#!/bin/bash

#command line arguments:
#startup
#network_status
#provision
#s3_upload
#   -nodelay
#update 
#   -usb
#   -git
#       -nodelay
#   -customer
#       -nodelay
#   -room_number
#   -timezone
#sleep
#   -start
#   -end

cd /home/savvy/

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
        #$1=ssid/profile name $2=password $3=autoconnect priority (-999 to 999, higher number is higher priority)
        nmcli con add con-name "$1" ifname $DONGLE type wifi ssid "$1" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$2" connection.autoconnect-priority "$3"

        sleep 2

        #if fourth argument exists, connect to this wifi immediately (may not work reliably with dongle)
        if [ $4 ]; then
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

    if [[ "$NETWORK" = '' ]]; then
        #no network or wrong ifname
        echo "not connected to network"
        #define necessary variables and functions to configure wireless network in this script's scope
        . /home/savvy/savvy.sh startup

        #cycle through all stored wifi networks and check for correct dongle
        nmcli con show | grep wifi | awk -F "  " '{print $1}' | while read profile; do
            IFNAMEPROFILE="$(nmcli con show "$profile" | grep interface-name | awk '{print $2}')"
            if [[ $DONGLE != $IFNAMEPROFILE ]]; then
                #get priority from current profile or manually define priority if profile is one of the three primary ssids
                if [[ "$profile" = "$SSID2" ]]; then
                    PRIORITY=200
                elif [[ "$profile" = "$SSID3" ]]; then
                    PRIORITY=100
                elif [[ "$profile" = "$SSID1" ]]; then
                    PRIORITY=0
                else
                    PRIORITY=`nmcli con show "$profile" | grep autoconnect-priority | awk '{print $2}'`
                    #for older wifi profiles, set priority lower than current SSID2
                    if [[ $PRIORITY -ge 200 ]]; then
                        PRIORITY=150
                    fi
                fi

                #get password from profile
                PASSWORD=`nmcli con show "$profile" --show-secrets | grep wireless-security.psk: | awk -F "  " '{print $NF}' | sed 's/^ *//'`
                echo "dongle wrongle $profile"
                #remove existing wifi profile
                nmcli con delete "$profile"

                #add new wifi profile with new dongle ifname
                if [[ $PRIORITY -gt 199 ]]; then
                    setupwifi "$profile" "$PASSWORD" $PRIORITY connect
                else
                    setupwifi "$profile" "$PASSWORD" $PRIORITY
                fi
                sleep 1
            fi
        done

        #check that all primary SSIDs are listed by network manager and set them up if not
        if [[ "$SSID2" ]]; then
            if [[ $(nmcli con show | grep "$SSID2") ]]; then
                #check that password is correct
                if [[ $(nmcli con show "$SSID2" --show-secrets | grep wireless-security.psk: | awk -F 'psk: *' '{print $2}') != "$PASS2" ]]; then
                    setupwifi "$SSID2" "$PASS2" 200
                fi
            else
                setupwifi "$SSID2" "$PASS2" 200
            fi
        fi

        if [[ $(nmcli con show | grep "$SSID3") ]]; then
            if [[ $(nmcli con show "$SSID3" --show-secrets | grep wireless-security.psk: | awk -F 'psk: *' '{print $2}') != "$PASS3" ]]; then
                nmcli con delete "$SSID3"
                sleep 1
                setupwifi "$SSID3" "$PASS3" 100
            fi
        else
            setupwifi "$SSID3" "$PASS3" 100
        fi

        if [[ $(nmcli con show | grep "$SSID1") ]]; then
            if [[ $(nmcli con show "$SSID1" --show-secrets | grep wireless-security.psk: | awk -F 'psk: *' '{print $2}') != "$PASS1" ]]; then
                nmcli con delete "$SSID1"
                sleep 1
                setupwifi "$SSID1" "$PASS1" 0
            fi
        else
            setupwifi "$SSID1" "$PASS1" 0
        fi

        #check if startx didn't launch firefox because no network was available 
        if [[ -f /home/savvy/nobrowser ]]; then
            if [[ "$SSID2" ]]; then
                #check if SSID2 is broadcasting and visible
                WIFIVAR=$(nmcli device wifi list | grep "$SSID2")

                if [ "$WIFIVAR" ]; then
                    nmcli con up "$SSID2"
                    sleep 3
                else
                    echo "wifi SSID \"$SSID2\" not visible"
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
#    else
#        #network connected-check for highest priority SSID
#        ACTIVEWIFI=$(nmcli con | sed '2q;d' | grep ' wifi ' | awk -F "   *" '{print $2}')
#        if [[ $ACTIVEWIFI ]]; then
#            ACTIVEWIFIPRIORITY=$(nmcli con show $ACTIVEWIFI | grep autoconnect-priority | awk '{print $2}')
#            SSID2="$(jq .ssid /home/savvy/customer_info | sed 's/^\"//; s/\"$//')" #customer wifi ssid
#
#            if [[ $ACTIVEWIFIPRIORITY != 200 && $(nmcli device wifi list | grep "$SSID2") ]]; then
#                nmcli con up "$SSID2"
#            fi
#        fi
    fi
fi
#NETWORK CHECK END


#PROVISIONING START
if [[ $1 == 'provision' ]]; then
    SSID2="$(jq .ssid /home/savvy/customer_info | sed 's/^\"//; s/\"$//')" #customer wifi ssid
    CURWIFI=$(nmcli con show | sed '2q;d' | awk -F "  " '{print $1}')
    #don't update json if SSID2 is already connected (it will be done automatically at next reboot)
    if [[ "$CURWIFI" != "$SSID2" ]]; then
        SSID3="EMSETUP" #customer setup wifi
        #if current network is EMSETUP
        if [[ "$CURWIFI" = "$SSID3" ]]; then
            if [[ -s /home/savvy/.url ]]; then
                #define customer path from .url file
                CUSTWEB=$(cat /home/savvy/.url | awk '{ print $NF }' FS='\/')

                #update git while on provisioning network
                /home/savvy/savvy.sh update git nodelay

                #download customer data
                cd /home/savvy/
                #overwrite any existing file of the same name
                wget -O ./$CUSTWEB.json https://savvy-configs.s3.us-west-2.amazonaws.com/$CUSTWEB.json
                #if last command exited with code 0 (no errors), decode json file, write to customer_info
                if [[ $? == 0 ]]; then
                    base64 -d /home/savvy/$CUSTWEB.json | jq > /home/savvy/customer_info
                fi

                #remove customer_info file if it's empty
                if [[ ! -s /home/savvy/customer_info ]]; then
                    rm /home/savvy/customer_info
                #otherwise proceed to wificleanup, git update, and reboot
                else
                    #if there are more than 25 items in list (wifi SSIDs with spaces will be counted as multiple items), delete all wifi profiles and start over
                    if [[ `echo $(nmcli -f NAME con show) | awk '{print NF}'` -gt 25 ]]; then
                        . /home/savvy/savvy.sh startup
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


#S3 UPLOAD START
if [[ $1 == 's3_upload' ]]; then
    #wait a random time less than 7 minutes to upload daily data to s3 bucket
    if [[ $2 != 'nodelay' ]]; then
        sleep $((RANDOM%420))
    fi

    #create filename to upload
    SLUG=$(cat /home/savvy/.url)
    ROOM_NUMBER="$(cat /home/savvy/device_info | grep Room | awk -F 'number: ' '{print $2}' | sed 's/\//_/')" #replaces any '/' in room number with '_'
    SERIAL=$(cat /sys/devices/platform/firmware\:secure-monitor/serial)    #$(cat /home/savvy/device_info | grep Serial | awk -F 'number: ' '{print $2}')
    DATE=$(date +%y%m%d)
    FILENAME="$SLUG-$ROOM_NUMBER-$SERIAL-$DATE"

    #add info to file
    echo "slug: $SLUG" > "/home/savvy/$FILENAME"
    echo "room: $ROOM_NUMBER" >> "/home/savvy/$FILENAME"
    echo "serial: $SERIAL" >> "/home/savvy/$FILENAME"
    echo "date: $(timedatectl | grep Local | awk -F 'time: ' '{print $2}')" >> "/home/savvy/$FILENAME"
    echo "tag: $(cat /home/savvy/device_info | grep Release | awk -F 'tag: ' '{print $2}')" >> "/home/savvy/$FILENAME"
    echo "os_ver: $(cat /home/savvy/device_info | grep OS | awk -F 'version: ' '{print $2}')" >> "/home/savvy/$FILENAME"
    echo "timezone: $(timedatectl show | grep Timezone | awk -F = '{print $2}')" >> "/home/savvy/$FILENAME"
    echo "sleep_enabled: $(jq .sleepEnabled /home/savvy/customer_info)" >> "/home/savvy/$FILENAME"
    echo "sleep_start_json: $(jq .sleepStart /home/savvy/customer_info)" >> "/home/savvy/$FILENAME"
    echo "sleep_start_cron: $(grep 'sleep start' /etc/crontab | cut -c 1-6)" >> "/home/savvy/$FILENAME"
    echo "sleep_end_json: $(jq .sleepEnd /home/savvy/customer_info)" >> "/home/savvy/$FILENAME"
    echo "sleep_end_cron: $(grep 'root reboot' /etc/crontab | cut -c 1-5)" >> "/home/savvy/$FILENAME"
    echo "ssid: $(jq .ssid /home/savvy/customer_info)" >> "/home/savvy/$FILENAME"
    echo "ssid_pass: $(jq .wifiPassword /home/savvy/customer_info)" >> "/home/savvy/$FILENAME"
    echo "cpu_temp: $(cat /sys/class/thermal/thermal_zone0/temp | sed 's/000$/C/')" >> "/home/savvy/$FILENAME"
    echo "cpu_us_sy_id: $(vmstat | sed '3q;d' | awk '{print $13,$14,$15}')" >> "/home/savvy/$FILENAME"
    echo "ram_free: $(free -h | sed '2q;d' | awk '{print $4}')" >> "/home/savvy/$FILENAME"
    echo "disk_free: $(df -h | grep mmcblk0p1 | awk '{print $4}')" >> "/home/savvy/$FILENAME"
    echo "lsusb_1: $(lsusb | sed '1q;d')" >> "/home/savvy/$FILENAME"
    echo "lsusb_2: $(lsusb | sed '2q;d')" >> "/home/savvy/$FILENAME"
    echo "lsusb_3: $(lsusb | sed '3q;d')" >> "/home/savvy/$FILENAME"
    echo "lsusb_4: $(lsusb | sed '4q;d')" >> "/home/savvy/$FILENAME"
    echo "last_reboot: $(cat /home/savvy/cron_last_reset | tail -n 1)" >> "/home/savvy/$FILENAME"
    echo "lan_rx_tx_tot_avg: $(vnstat -d 1 `vnstat --dbiflist | awk -F ' ' '{print $4}'` | sed '6q;d')" >> "/home/savvy/$FILENAME"
    echo "wifi_rx_tx_tot_avg: $(vnstat -d 1 `vnstat --dbiflist | awk -F ' ' '{print $5}'` | sed '6q;d')" >> "/home/savvy/$FILENAME"
    echo "network_health: $(ping 8.8.8.8 -c 1 | grep time=)" >> "/home/savvy/$FILENAME"
    echo "active_network_interface: $(nmcli device | sed '2q;d')" >> "/home/savvy/$FILENAME"
    echo "syslog_size: $(du -h /var/log/syslog)" >> "/home/savvy/$FILENAME"
    echo "24h_crit_errors: $(journalctl --since "24 hours ago" | grep -i -E '(error|critical|alert)' | wc -l)" >> "/home/savvy/$FILENAME"

    #upload file to s3
    aws s3 cp "/home/savvy/$FILENAME" s3://savvysimple-devicedata
    #remove file
    rm /home/savvy/$FILENAME
fi
#S3 UPLOAD END


#UPDATE SCRIPT START
if [[ $1 == 'update' ]]; then
    #updatefile $1=filename $2=permissions $3=path to replacement file $4=path to file to be replaced $5=owner $6=move file instead of copy (use for files that will be updated after downloading)
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
            if [[ $6 = 'move' ]]; then
                mv $3$1 $4$1
            else
                cp $3$1 $4$1
            fi
            
            chown $5:$5 $4$1
            chmod $2 $4$1
        #files are the same, move file to remove it from the repo directory
        elif [[ $6 = 'move' ]]; then
            mv $3$1 $4$1
            chown $5:$5 $4$1
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
                updatefile savvy.sh 755 /media/savvyUSB/ /home/savvy/ savvy
            fi

            if [ "$FILESDIFFERENT" ]; then
                #skip until next cycle
                echo "savvy.sh updated"
                touch /home/savvy/rebootflag
#                touch /home/savvy/updates
            else
                updatefile .bashrc 644 /media/savvyUSB/ /home/savvy/ savvy
                updatefile .xsession 644 /media/savvyUSB/ /home/savvy/ savvy
                updatefile emlogo.png 644 /media/savvyUSB/ /home/savvy/ savvy
                updatefile offline.png 644 /media/savvyUSB/ /home/savvy/ savvy
                updatefile offlinenet.png 644 /media/savvyUSB/ /home/savvy/ savvy
                updatefile crontab 644 /media/savvyUSB/ /etc/ root
                updatefile .url 644 /media/savvyUSB/ /home/savvy/ savvy

                USERJSPATH=$(find /home/savvy/.mozilla/firefox* -type d -name *default-esr*)
                echo "userjspath=$USERJSPATH"
                if [[ -d $USERJSPATH ]]; then
                    updatefile user.js 644 /media/savvyUSB/ $USERJSPATH/ savvy
                fi

                if [[ "$FILESDIFFERENT" || -f /home/savvy/rebootflag ]]; then
                    echo "files were updated - rebooting in 3s"
                    rm /home/savvy/rebootflag
#                    touch /home/savvy/updates
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

        #wait a random time less than 7 minutes to check git
        if [[ $3 != 'nodelay' ]]; then
            sleep $((RANDOM%420))
        fi

        git pull >> /home/savvy/backup/update_record
        #remove carriage return on last update_record line and append date and time
        truncate -s-1 /home/savvy/backup/update_record
        echo " $(date)" >> /home/savvy/backup/update_record
        TAG=$(git tag | tail -n 1)

        if [[ $(grep Release /home/savvy/device_info | awk '{print $2}' FS=': ') != $TAG ]]; then
            sed -i "/Release/cRelease tag: $TAG" /home/savvy/device_info
        fi

        updatefile savvy.sh 755 /home/savvy/updatetest1/ /home/savvy/ savvy
        updatefile .bashrc 644 /home/savvy/updatetest1/ /home/savvy/ savvy
        updatefile .xsession 644 /home/savvy/updatetest1/ /home/savvy/ savvy
        updatefile emlogo.png 644 /home/savvy/updatetest1/ /home/savvy/ savvy
        updatefile offline.png 644 /home/savvy/updatetest1/ /home/savvy/ savvy
        updatefile offlinenet.png 644 /home/savvy/updatetest1/ /home/savvy/ savvy
        updatefile crontab 644 /home/savvy/updatetest1/ /etc/ root move

        USERJSPATH=$(find /home/savvy/.mozilla/firefox* -type d -name *default-esr* 2>/dev/null)
        if [[ -d $USERJSPATH ]]; then
            updatefile user.js 644 /home/savvy/updatetest1/ $USERJSPATH/ savvy
        fi

        if [[ "$FILESDIFFERENT" ]]; then
            #update log file
            echo "Git update at $(date)" >> /home/savvy/backup/update_record
            #set flag that files have changed
#            touch /home/savvy/updates
        fi
    fi
    #END OF GIT UPDATE


    #CUSTOMER INFO UPDATE 
    if [[ $2 == 'customer' ]]; then
        if [[ -s /home/savvy/.url ]]; then
            #define customer path from .url file (works for full url or just the slug)
            CUSTWEB=$(cat /home/savvy/.url | awk '{ print $NF }' FS='\/')

            #wait a random time less than 3 minutes before downloading json unless 'nodelay' is added
            if [[ $3 != 'nodelay' ]]; then
                sleep $(($RANDOM%180))
            fi

            #download customer data
            cd /home/savvy/
            wget -N https://savvy-configs.s3.us-west-2.amazonaws.com/$CUSTWEB.json
            #if last command exited with code 0 (no errors), decode json file, write to customer_info
            if [[ $? == 0 ]]; then
                base64 -d /home/savvy/$CUSTWEB.json | jq > /home/savvy/customer_info
            fi

            #remove customer_info file if it's empty
            if [[ ! -s /home/savvy/customer_info ]]; then
                rm /home/savvy/customer_info

            #if not empty, update screen sleep schedule
            else
                #define local variables for sleep schedule
                SLEEPENABLED=$(jq .sleepEnabled /home/savvy/customer_info | sed 's/^\"//; s/\"$//')
                if [[ $SLEEPENABLED = 'true' ]]; then

                    SLEEPSTART=$(jq .sleepStart /home/savvy/customer_info | sed 's/^\"//; s/\"$//')
                    #check length of SLEEPSTART and select correct digits
                    if [[ ${#SLEEPSTART} = 4 ]]; then
                        SLEEPSTARTMIN=$(echo $SLEEPSTART | cut -c 3-4)
                        SLEEPSTARTHOUR=$(echo $SLEEPSTART | cut -c 1-2)
                    elif [[ ${#SLEEPSTART} = 3 ]]; then
                        SLEEPSTARTMIN=$(echo $SLEEPSTART | cut -c 2-3)
                        SLEEPSTARTHOUR=$(echo $SLEEPSTART | cut -c 1)
                    fi
                    #check that extracted digits are an integer 
                    if [[ $SLEEPSTARTMIN =~ ^[0-9]+$ ]]; then
                        INVALIDSLEEP=''
                        #check that integer is less than 60
                        if [[ $SLEEPSTARTMIN -gt 59 ]]; then
                            INVALIDSLEEP=true
                        fi
                    #time in json is not an integer
                    else
                        INVALIDSLEEP=true
                    fi
                    if [[ $SLEEPSTARTHOUR =~ ^[0-9]+$ ]]; then
                        #check that integer is less than 24
                        if [[ $SLEEPSTARTHOUR -gt 23 ]]; then
                            INVALIDSLEEP=true
                        fi
                    else
                        INVALIDSLEEP=true
                    fi

                    SLEEPEND=$(jq .sleepEnd /home/savvy/customer_info | sed 's/^\"//; s/\"$//')
                    #check length of SLEEPEND and select correct digits
                    if [[ ${#SLEEPEND} = 4 ]]; then
                        SLEEPENDMIN=$(echo $SLEEPEND | cut -c 3-4)
                        SLEEPENDHOUR=$(echo $SLEEPEND | cut -c 1-2)
                    elif [[ ${#SLEEPEND} = 3 ]]; then
                        SLEEPENDMIN=$(echo $SLEEPEND | cut -c 2-3)
                        SLEEPENDHOUR=$(echo $SLEEPEND | cut -c 1)
                    fi
                    #check that extracted digits are an integer 
                    if [[ $SLEEPENDMIN =~ ^[0-9]+$ ]]; then
                        if [[ $SLEEPENDMIN -gt 59 ]]; then
                            INVALIDSLEEP=true
                        fi
                    #time in json is not an integer
                    else
                        INVALIDSLEEP=true
                    fi
                    if [[ $SLEEPENDHOUR =~ ^[0-9]+$ ]]; then
                        if [[ $SLEEPENDHOUR -gt 23 ]]; then
                            INVALIDSLEEP=true
                        fi
                    else
                        INVALIDSLEEP=true
                    fi

                    #sleep times are valid, update crontab
                    if [[ $INVALIDSLEEP != 'true' ]]; then
                        #update reboot time in crontab
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

                        #if sleep start hasn't been set up in crontab, set it up
                        if [[ ! $(sed -n '/sleep start/p' /etc/crontab) ]]; then
                            sed -i "/provision/a`echo $SLEEPSTARTMIN` `echo $SLEEPSTARTHOUR` * * * savvy /home/savvy/savvy.sh sleep start" /etc/crontab
                        #if sleep start already exists in crontab, update it
                        else
                            sed -i "/sleep start/c`echo $SLEEPSTARTMIN` `echo $SLEEPSTARTHOUR` * * * savvy /home/savvy/savvy.sh sleep start" /etc/crontab
                        fi
                    fi
                fi

                #if sleep is not enabled, or there is an error in the sleep start/end values, disable sleep
                if [[ $SLEEPENABLED != 'true' || $INVALIDSLEEP = 'true' ]]; then 
                    #sleep disabled-comment it out in crontab unless it already is
                    if [[ $(sed -n '/sleep start/p' /etc/crontab | cut -c 1) != \# ]]; then
                        sed -i '/sleep/s/^/#/' /etc/crontab
                    fi

                    #if sleep is off, set reboot to the default of 1pm local 
                    sed -i "/root reboot/c0 13 * * * root reboot" /etc/crontab
                    sed -i "/savvy echo/c0 13 * * * savvy echo \"System reset at \$(date)\" >> cron_last_reset" /etc/crontab
                    #update git 10 minutes before reboot
                    sed -i "/update git/c50 12 * * * root /home/savvy/savvy.sh update git" /etc/crontab
                fi
            fi
        fi
        #update room number
        /home/savvy/savvy.sh update room_number

        #update time zone
        /home/savvy/savvy.sh update timezone

        #update serial number
        if [[ $(cat /sys/devices/platform/firmware\:secure-monitor/serial) != $(cat /home/savvy/device_info | grep Serial | awk -F : '{print $2}' | sed 's/^ *//') ]]; then
            sed -i "/Serial/cSerial number: $(cat /sys/devices/platform/firmware\:secure-monitor/serial)" /home/savvy/device_info
        fi
    fi
    #CUSTOMER INFO END


    #START OF ROOM NUMBER
    if [[ $2 == 'room_number' ]]; then
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
                    ROOMNUMBER=$(cat tempfile | awk -F 'Number":"' '{print $2}' | awk -F '","show' '{print $1}')

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


#START OF SLEEP
#$2='start' to turn screen off, 'end' or anything else to turn screen on
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
