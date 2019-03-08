#!/bin/bash

configure() {
    local device=$1
    local maxrate=$2
    local limited=$3

    # Delete qdiscs, classes and filters
    tc qdisc del dev $device root 2> /dev/null
    tc qdisc del dev $device ingress 2> /dev/null

    # Root htb qdisc -- direct pkts to class 1:10 unless otherwise classified
    tc qdisc add dev $device root handle 1: htb default 10
    
    # Class 1:1 top of bandwith sharing tree
    # Class 1:10 -- rate-limited queue
    # Class 1:20 -- maximum rate queue
    tc class add dev $device parent 1: classid 1:1 htb rate $maxrate burst 20k
    tc class add dev $device parent 1:1 classid 1:10 htb \
        rate $limited ceil $maxrate burst 20k
    tc class add dev $device parent 1:1 classid 1:20 htb \
        rate $maxrate ceil $maxrate burst 20k

    # SFQ ensures equitable sharing of classified sessions
    tc qdisc add dev $device parent 1:10 handle 10: sfq perturb 10
    tc qdisc add dev $device parent 1:20 handle 20: sfq perturb 10

    # Classify ICMP into 1:20
    tc filter add dev $device parent 1:0 protocol ip prio 2 u32 \
        match ip protocol 1 0xff flowid 1:20

    # Classify TCP-ACK into 1:20
    tc filter add dev $device parent 1: protocol ip prio 2 u32 \
        match ip protocol 6 0xff \
        match u8 0x05 0x0f at 0 \
        match u16 0x0000 0xffc0 at 2 \
        match u8 0x10 0xff at 33 \
        flowid 1:20
}

main() {
    # Enable rate reporting in the htb scheduler
    echo 1 > /sys/module/sch_htb/parameters/htb_rate_est

    configure WEST 20mbit 5mbit
    configure EAST 20mbit 5mbit

    # Classify terminal server traffic
    tc filter add dev WEST protocol ip parent 1: prio 1 u32 \
        match ip dport 3389 0xffff flowid 1:20

    # Classify terminal server traffic
    tc filter add dev EAST protocol ip parent 1: prio 1 u32 \
        match ip sport 3389 0xffff flowid 1:20
}

main "$@"
