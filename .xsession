#!/usr/bin/env sh

export DISPLAY=:0.0

xrandr -s 800x480
xdotool mousemove 0 0

xset s off
xset -dpms
xset s noblank

nitrogen --set-centered emlogo.png

#check for wifi/network status here; if result is '' network manager did not connect to a network
NETWORK=`echo "$(nmcli device | grep 'wifi ' | awk '{print $3}') $(nmcli device | grep ethernet | awk '{print $3}')" | grep -w connected`
#check for internet access (will equal some text if internet access is available)
wget --spider --timeout=3 --tries=1 rmivfdfzp3.us-west-2.awsapprunner.com -q -o /dev/null
INTERNET=$?
LOOPS=0

#if there is an available network, wait until it establishes an internet connection
if [[ "$NETWORK" != '' ]]; then
    until [[ "$INTERNET" = 0 || $LOOPS > 4 ]]
    do
        sleep 2
        LOOPS=$(( $LOOPS+1 ))
        wget --spider --timeout=3 --tries=1 rmivfdfzp3.us-west-2.awsapprunner.com -q -o /dev/null
        INTERNET=$?
    done
fi

#no internet connection-go to offline option
if [[ "$INTERNET" != 0 ]]; then
    #no internet connection
    #declare local variables in this scope and remove old files
    . /home/savvy/savvy.sh startup
    rm -f wifilist offline offline.png nonet nonet.png

    #sleep so em splash screen stays visible for a few seconds before switching to offline message
    sleep 5s
    touch nobrowser

    if [ "$NETWORK" != '' ]; then
        #savvy has a network connection, but no internet
        echo -e "Connected to network, but unable to access internet. Connection details are listed below:\n" > offline
        #check if LAN is connected
        if [[ $(nmcli device | grep ethernet | grep -w connected) ]]; then
            #get details for LAN connection
            nmcli device show end0 >> offline
        else
            #get details for wifi connection
            iwconfig $DONGLE >> offline 
        fi
        echo -e "\nUnit will automatically reset when internet connection is restored. (may take several minutes)" >> offline 
        echo "Contact local IT department for troubleshooting assistance." >> offline

        pango-view --font="mono" --width=790 --pixels -qo offline.png offline
        #display message to say network is available, but has no internet connection
        nitrogen --set-centered offline.png
    else
        #no network connection established-check if any SSIDs are visible
        nmcli device wifi > wifilist
        #list will be completely empty if dongle is unplugged
        if [[ ! -s /home/savvy/wifilist ]]; then
            #empty file
            echo -e "No USB WiFi devices detected. The following is a list of all USB devices connected to this unit:\n" >> nonet
            #get list of USB devices other than the hubs
            lsusb | grep -v -e Linux -e Genesys >> nonet
            echo -e "\nCheck that WiFi dongle is fully plugged into USB port and reset unit. Contact customer support at xxx-xxx-xxxx for further assistance." >> nonet
        elif [[ $(cat wifilist | sed '2q;d') ]]; then
            #at least one SSID has been detected (line one is the field labels)
            #check for customer SSID in list
            if [[ "$SSID2" && $(grep "$SSID2" wifilist) ]]; then
                #customer wifi is visible
                echo -e "SSID \"$SSID2\" is visible. The password for this profile is stored as \"$PASS2\".\n" > nonet
                if [[ $(nmcli con show | grep "$SSID2") ]]; then
                    echo -e "WiFi dongle ifname is: $DONGLE    Profile ifname is: $(nmcli con show "$SSID2" | grep interface-name: | awk '{print $2}')" >> nonet
                    if [[ "$DONGLE" != "$(nmcli con show "$SSID2" | grep interface-name: | awk '{print $2}')" ]]; then
                        echo -e "Hardware and profile interface names are different. Please allow approximately 3 minutes for WiFi profile to rebuild.\n" >> nonet
                    fi
                else
                    echo -e "\"$SSID2\" is not a stored WiFi profile. Allow 5 minutes for profile to rebuild before taking further action." >> nonet
                fi
                echo -e "\nThe following is a list of all access point MAC addresses and signal strengths for \"$SSID2\"\n" >> nonet
                grep SIGNAL wifilist >> nonet
                grep "$SSID2" wifilist >> nonet
                echo -e "\nDouble check that the password shown at top is correct and that signal is good. (SIGNAL has a range of 0 to 100)" >> nonet
                echo -e "\nTo change or update network information, contact local administrator for assistance." >> nonet
            else
                #customer wifi not visible or not provided, list available networks
                if [[ "$SSID2" ]]; then
                    #if customer wifi has already been entered into json
                    echo -e "SSID \"$SSID2\" not found. The networks with the highest signal strength are:\n" > nonet
                    nmcli device wifi | head -n 11 >> nonet 
                    echo -e "\nCheck the signal strength of your WiFi at this location. Contact xxx-xxx-xxxx for additional support." >> nonet
                else
                    #customer wifi information has not yet been received
                    echo -e "Customer WiFi information not yet provided. Check with your local administrator to add this information." > nonet
                    echo -e "It will be necessary to create a WiFi hotspot with SSID \"EMSETUP\" and password \"ELECTRICMIRROR\" or connect a LAN cable to complete device setup once this information is avaialable." >> nonet
                    echo -e "\nThe strongest networks available at this location are:" >> nonet
                    nmcli device wifi | head -n 11 >> nonet 
                fi
            fi
        else
            #no wifi stations are visible at all, but all hardware is working correctly
            echo "WiFi dongle installed but no WiFi signals detected. Using another device, verify if any WiFi signals are visible from this location." > nonet
            if [[ $SSID2 ]]; then
                echo -e "Unit will automatically reset several minutes after \"$SSID3\", \"$SSID1\", or \"$SSID2\" are found." >> nonet
            else
                echo -e "Unit will automatically reset several minutes after \"$SSID3\" or \"$SSID1\" are found." >> nonet
            fi
            echo "For additional support, contact xxx-xxx-xxxx." >> nonet
        fi

        pango-view --font="mono" --width=790 --align=center --pixels -qo nonet.png nonet 
        #display message to say network is not available
        nitrogen --set-centered nonet.png
    fi
else
    #internet connection established-go to website
    rm -f wifilist offline offline.png nonet nonet.png
    WIFICONNECTED=$(nmcli device | grep 'wifi ' | awk '{print $4}')
    #might need to change the following section depending on how it works with the EMSETUP network
    
    if [[ "$WIFICONNECTED" = "EM_GUEST" ]]; then
        #if we design a testing website for in-house QC, change the url here
        URL="https://rmivfdfzp3.us-west-2.awsapprunner.com/"
        #if network cable is plugged in, override EM_GUEST wifi connection (both can be active simultaneously)
        if [[ $(nmcli device | grep ethernet | awk '{print $3}') = 'connected' ]]; then
            URL="https://rmivfdfzp3.us-west-2.awsapprunner.com/$(sed '1q' /home/savvy/.url 2>/dev/null)"
        fi
    else
        #if connected to any other network, go to customer website
        URL="https://rmivfdfzp3.us-west-2.awsapprunner.com/$(sed '1q' /home/savvy/.url 2>/dev/null)"
    fi
    env MOZ_USE_XINPUT2=1 firefox-esr --kiosk --disable-pinch $URL &
fi

exec matchbox-window-manager -use_titlebar no
