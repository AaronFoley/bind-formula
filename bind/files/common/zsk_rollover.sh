#!/bin/sh

# Modified from https://www.eriklundblad.com/log/post/automatic-zone-signing-key-rollover-in-bind/

ZONEDIR="{{ map.named_directory }}"
KEYDIR="{{ map.key_directory }}"

ZONE="$1"
INACTIVE="$2"
DELETE="$3"

if [ $# -eq 0 ]
then
    echo "Syntax: ./$(basename $0) mydomain.tld"
    exit 1
fi

ZONEFILE="${ZONEDIR}/${ZONE}"

if [ ! -f $ZONEFILE ]
then
    echo "File ${ZONE} not found!"
    exit 1
fi

OLDKEYS="$(grep -l "zone-signing key" $KEYDIR/K$ZONE.*)"

if [ -z "$OLDKEYS" ]
then
   echo "Unable to find an existing zone-signing key, exiting."
   exit 1
fi

ACTIVEKEY="$(grep -L "Inactive" $OLDKEYS)"

if [ -z "$ACTIVEKEY" ]
then
   echo "Unable to find an active zone-signing key, exiting."
   exit 1
fi

if (( $(grep -c . <<<"$ACTIVEKEY") > 1 ))
then
   echo "Found multiple active zone-signing keys, exiting."
   exit 1
fi

echo "Found key: $ACTIVEKEY"

/usr/sbin/dnssec-settime -I $INACTIVE -D $DELETE $ACTIVEKEY

{%- set keygen_options = '-r ' + salt['pillar.get']("bind:config:keygen_options:randomdev","/dev/random") %}
{%- if salt['pillar.get']("bind:config:keygen_options:nsec3",False) %}
{%- set keygen_options = keygen_options + ' -3 ' %}
{%- endif %}

KEYNAME="$(/usr/sbin/dnssec-keygen {{ keygen_options }} -K $KEYDIR -S $ACTIVEKEY -i $INACTIVE)"

echo "Generated key: ${KEYNAME}"

echo "Setting owner on generated key"
chmod 644 "$KEYDIR/$KEYNAME*.key"
chmod 640 "$KEYDIR/$KEYNAME*.private"*
chown "{{ salt['pillar.get']('bind:config:user', map.user) }}:{{ salt['pillar.get']('bind:config:group', map.group) }}" "$KEYDIR/$KEYNAME.*"