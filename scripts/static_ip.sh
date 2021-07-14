#!/bin/sh
# This is a debconf-compatible script
# shellcheck disable=SC1091
. /usr/share/debconf/confmodule

valid_ip () {
    local ip=$1

    if [[ -z $ip ]]; then
        return 0
    fi

    if expr "$ip" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null; then
        for i in 1 2 3 4; do
            if [ "$(echo "$ip" | cut -d. -f$i)" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Create the template file
cat > /tmp/ip.template <<'!EOF!'
Template: ip-question/ask
Type: string
Description: If your public IP is dynamic, or you don't know, leave this field blank and continue.
 DAppNode needs to know the public IP of your node.

Template: ip-question/title
Type: text
Description: Your public IP.

Template: ip-question/finished
Type: text
Description: Finished.
!EOF!

cat > /tmp/ip_fail.template <<'!EOF!'
Template: ip-fail/ask
Type: note
Description: This is not a valid IP.

Template: ip-fail/title
Type: text
Description: Wrong IP
!EOF!

db_dialog () {
    debconf-loadtemplate ip-question /tmp/ip.template
    db_settitle ip-question/title
    db_input critical ip-question/ask
    db_go
    db_get ip-question/ask

    valid_ip "$RET"
    if [[ $? -eq 0 ]]; then
        mkdir -p /target/usr/src/dappnode/config
        echo "$RET" > /target/usr/src/dappnode/config/static_ip
    else
        debconf-loadtemplate ip-fail /tmp/ip_fail.template
        db_settitle ip-fail/title
        db_input critical ip-fail/ask
        db_go
        db_get ip-fail/ask
        # Ask again until done
        db_dialog
    fi
    db_settitle ip-question/title
}

db_restore () {
    debconf-loadtemplate ip-question /tmp/ip.template
    db_settitle ip-question/restore
}

db_dialog
db_restore