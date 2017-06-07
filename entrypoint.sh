#!/usr/bin/env sh

# Config path
CONFIG_DIR="/etc/bind"
CONFIG_FILE="${CONFIG_DIR}/named.conf"
MASTERS_ZONE_DIR="/var/bind/pri"

# Templates
ZONE_MASTER_TEMPLATE="/templates/zone.master.conf.template"
ZONE_SLAVE_TEMPLATE="/templates/zone.slave.conf.template"

# ACLs
XFER_IP=${XFER_IP:-none}
TRUSTED_IP=${TRUSTED_IP:-127.0.0.0/8 ::1/128}
MASTERS_IP=${MASTERS_IP:-}
FORWARDERS=${FORWARDERS:-8.8.4.4 8.8.8.8 2001:4860:4860::8888 2001:4860:4860::8844}

# Zones definition
SLAVE_ZONES=${SLAVE_ZONES:-}

# Security
RNDC_KEY_LINK="/etc/bind/rndc.key"
RNDC_KEY_FILE=${RNDC_KEY_FILE:-$RNDC_KEY_LINK}
RNDC_KEY_NAME=${RNDC_KEY_NAME:-rndc-key}
TSIG_KEY_LINK="/etc/bind/tsig.key"
TSIG_KEY_FILE=${TSIG_KEY_FILE:-$TSIG_KEY_LINK}
TSIG_KEY_NAME=${TSIG_KEY_NAME:-}

check_or_create_key() {
    local type=$1
    local file=$2
    local link=$3
    local name=$4
    if [ ! -s $file -a -n "$name" ]; then
        if [ $type = "tsig" ]; then
            tsig-keygen -a hmac-sha512 $name > $link
        else
            rndc-confgen -a -k $name -c $link
        fi
        chown named: $link
        file=$link
    else
        test -l $link && rm $link
        ln -s $file $link
    fi
    echo $file
}

check_or_create_rndc() {
    check_or_create_key "rndc" $RNDC_KEY_FILE $RNDC_KEY_LINK $RNDC_KEY_NAME
}

check_or_create_tsig() {
    check_or_create_key "tsig" $TSIG_KEY_FILE $TSIG_KEY_LINK $TSIG_KEY_NAME
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

    # By default use TSIG key for xfer
    if [ -n "$TSIG_KEY_NAME" -a "$XFER_IP" = "none" ]; then
        sed -i "s~@XFER_ACL_OR_KEY@~key \"$TSIG_KEY_NAME\";~g" ${CONFIG_FILE}
    else
        sed -i "s~@XFER_ACL_OR_KEY@~none~g" ${CONFIG_FILE}
    fi
}

configure_bind() {
    RNDC_KEY_FILE=$(check_or_create_rndc)
    TSIG_KEY_FILE=$(check_or_create_tsig)

    if [ -n "$TSIG_KEY_NAME" ]; then
        echo "include \"$TSIG_KEY_LINK\";" >>${CONFIG_FILE}
    else
        # TODO(sheeprine): Add ACL by IP + key
        create_list "acl" "xfer" $XFER_IP >>${CONFIG_FILE}
    fi
    create_list "acl" "trusted" $TRUSTED_IP >>${CONFIG_FILE}
    create_list "acl" "masters" $MASTERS_IP >>${CONFIG_FILE}
    create_list "masters" "masters" $MASTERS_IP >>${CONFIG_FILE}

    create_main_config

    for zone in $(ls $MASTERS_ZONE_DIR | grep -v '\.sub\.zone$'); do
        create_zone $(echo $zone | sed "s~\.zone$~~") master
    done

    for zone in $SLAVE_ZONES; do
        create_zone $zone slave
    done
}

test -w $CONFIG_FILE && rm $CONFIG_FILE
test ! -f $CONFIG_FILE && configure_bind

VERSION=$(named -v | cut -d' ' -f2)
echo "Starting bind $VERSION..."
exec named -g -u named $@
