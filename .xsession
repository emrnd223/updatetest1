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
INTERNET=$(ping -c 2 8.8.8.8 | grep time=)
LOOPS=0

#if there is an available network, wait until it establishes an internet connection
if [[ "$NETWORK" != '' ]]; then
    until [[ "$INTERNET" != '' || $LOOPS > 4 ]]
    do
        sleep 2
        LOOPS=$(( $LOOPS+1 ))
        INTERNET=$(ping -c 2 8.8.8.8 | grep time=)
    done
fi

#no internet connection-go to offline option
if [[ "$INTERNET" = '' ]]; then
    #sleep so em splash screen stays visible for a few seconds before switching to offline message
    sleep 5s
    touch nobrowser
    if [ "$NETWORK" != '' ]; then
        echo "Network connection established, but unable to access internet." > offline
        echo "Connection details:" >> offline
        echo $(iwconfig) >> offline 
        echo "Unit will automatically reset when internet connection is restored (may take up to 5 minutes)." >> offline && pango-view --font="mono" -qo offline.png offline 
        #display message to say network is available, but no internet connection
        nitrogen --set-centered offline.png
    else
        #no network connection established
        echo -e "No network connection established.\nVisible SSIDs with highest signal strength:" > nonet
        nmcli device wifi | head -n 11 >> nonet 
        echo "If no SSIDs are visible, check that the WiFi dongle is fully seated in USB port." >> nonet 
        echo "Note: Unit will reset when network connection is established (may take up to 5 minutes)." && pango-view --font="mono" --pixels=800x480 -qo nonet.png nonet

        #display message to say network is not available
        nitrogen --set-centered nonet.png
    fi
#internet connection established-go to website
else
    rm -f offline offline.png nonet nonet.png
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
