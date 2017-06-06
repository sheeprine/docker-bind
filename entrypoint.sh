#!/usr/bin/env sh

CONFIG_DIR="/etc/bind"
CONFIG_FILE="${CONFIG_DIR}/named.conf"
ZONE_MASTER_TEMPLATE="/templates/zone.master.conf.template"
ZONE_SLAVE_TEMPLATE="/templates/zone.slave.conf.template"

XFER_IP=${XFER_IP:-none}
TRUSTED_IP=${TRUSTED_IP:-127.0.0.0/8 ::1/128}
MASTERS_IP=${MASTERS_IP:-}
FORWARDERS=${FORWARDERS:-8.8.4.4 8.8.8.8 2001:4860:4860::8888 2001:4860:4860::8844}

# Zones definition
MASTER_ZONES=${MASTER_ZONES:-}
SLAVE_ZONES=${SLAVE_ZONES:-}

# Security
RNDC_KEY_LINK="/etc/bind/rndc.key"
RNDC_KEY_FILE=${RNDC_KEY_FILE:-$RNDC_KEY_LINK}
RNDC_KEY_NAME=${RNDC_KEY_NAME:-rndc-key}

check_or_create_rndc() {
    if [ ! -f $RNDC_KEY_FILE ]; then
        rndc-confgen -a
        RNDC_KEY_FILE=$RNDC_KEY_LINK
    else
        ln -s $RNDC_KEY_FILE $RNDC_KEY_LINK
    fi
}

format_ips() {
    for ip in $@; do
        echo -n "$ip;\n"
    done
}

create_list() {
    local list_type=$1
    shift
    local list_name=$1
    shift
    local list_ips=$@
    echo "$list_type \"$list_name\" {"
    echo -e "$(format_ips $list_ips)};"
}

create_zone() {
    local zone_type=${2:-"master"}
    if [ $zone_type = "slave" ]; then
        local zone_folder="sec"
        local zone_template=$ZONE_SLAVE_TEMPLATE
    else
        local zone_folder="pri"
        local zone_template=$ZONE_MASTER_TEMPLATE
    fi
    sed "s~@ZONE@~$1~g" $zone_template | \
    sed "s~@TYPE@~$zone_type~g" | \
    sed "s~@FOLDER@~$zone_folder~g" >>${CONFIG_FILE}
}

create_main_config() {
    sed "s~@FORWARDERS@~$(format_ips $FORWARDERS)~g" \
        /templates/named.conf.template | \
    sed "s~@RNDC_KEY_NAME@~$RNDC_KEY_NAME~g" | \
    sed "s~@RNDC_KEY_FILE@~$RNDC_KEY_FILE~g" >>${CONFIG_FILE}
}

rm $CONFIG_FILE
check_or_create_rndc

create_list "acl" "xfer" $XFER_IP >>${CONFIG_FILE}
create_list "acl" "trusted" $TRUSTED_IP >>${CONFIG_FILE}
create_list "acl" "masters" $MASTERS_IP >>${CONFIG_FILE}
create_list "masters" "masters" $MASTERS_IP >>${CONFIG_FILE}

create_main_config

for zone in $MASTER_ZONES; do
    create_zone $zone master
done

for zone in $SLAVE_ZONES; do
    create_zone $zone slave
done

VERSION=$(named -v | cut -d' ' -f2)
echo "Starting bind $VERSION..."
exec named -g -u named $@
