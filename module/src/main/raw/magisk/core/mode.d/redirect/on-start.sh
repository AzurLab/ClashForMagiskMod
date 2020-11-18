#!/system/bin/sh
#
# Script for clash setup
# - on-start.sh : On clash core started, setup proxy here
# - on-stop.sh : On clash core stoped, clean here
#
# Environments:
# - CLASH_HTTP_PORT: clash http proxy port
# - CLASH_SOCKS_PORT: clash socks proxy port
# - CLASH_REDIR_PORT: clash redir proxy port
# - CLASH_DNS_PORT: clash dns port
# - CLASH_UID: clash runing uid
# - CLASH_GID: clash running gid
# - PROXY_BLACKLIST_UID: blacklist uid
#

conf_file="/storage/emulated/0/Android/data/com.github.kr328.clashm/config.yaml"
selector_file="/storage/emulated/0/Android/data/com.github.kr328.clashm/selector.txt"

get_ec_parameter() {
     clash_ec_port=$(cat ${conf_file} | grep -E "^external-controller:" | head -n 1 | sed -E 's/external-controller: .*:([0-9]*).*/\1/')
     clash_secret=$(cat ${conf_file} | grep -E "^secret:" | head -n 1 | sed -E 's/secret: "?([^"]*)"?.*/\1/')
     if [ "${clash_ec_port}" = "" ];then
         clash_ec_port="9090"
     fi
     if [ "${clash_secret}" = "" ];then
         clash_secret=""
     fi
}

selector_restore() {
    get_ec_parameter
    va="0"
    while read line
    do
        if [ "$va" = "0" ];
        then
            va="1"
            group=$(echo $line |tr -d '\n' |od -An -tx1|tr ' ' %|tr -d '\n')
        else
            va="0"
            selector=$line
            curl -v -H "Authorization: Bearer ${clash_secret}" -X PUT -d "{${selector}}" "127.0.0.1:${clash_ec_port}/proxies/${group}"
        fi
    done < ${selector_file}
}

selector_record() {
    get_ec_parameter
    curl -H "Authorization: Bearer ${clash_secret}" http://127.0.0.1:${clash_ec_port}/proxies | sed -E 's/Selector/Selector\n/g' | sed '$d' | sed -E 's/.*name":"(.*)","now":"(.*)","type.*/\1\n"name":"\2"/' > ${selector_tmp}
    if test -s ${selector_tmp};
    then
        cp -f ${selector_tmp} ${selector_file}
    else
        echo "Selector empty, selector.txt not updated"
    fi
    rm -f ${selector_tmp}
}

assert() {
    "$@"
    if [[ $? != 0 ]];then
        echo "Command $@ failure"
        exit 1
    fi
}

if [[ "${CLASH_UID}" = "" ]];then
    echo "Clash uid not found"
    exit 1
fi

if [[ "${CLASH_REDIR_PORT}" = "" ]];then
    echo "Clash redir disabled"
    exit 1
fi

assert iptables -t nat -N CLASH_LOCAL
assert iptables -t nat -N CLASH_EXTERNAL

assert iptables -t nat -A CLASH_LOCAL -m owner --uid-owner ${CLASH_UID} -j RETURN
assert iptables -t nat -A CLASH_LOCAL -d 0.0.0.0/8 -j RETURN
assert iptables -t nat -A CLASH_LOCAL -d 127.0.0.0/8 -j RETURN
assert iptables -t nat -A CLASH_LOCAL -d 224.0.0.0/4 -j RETURN
assert iptables -t nat -A CLASH_LOCAL -d 172.16.0.0/12 -j RETURN
assert iptables -t nat -A CLASH_LOCAL -d 127.0.0.0/8 -j RETURN
assert iptables -t nat -A CLASH_LOCAL -d 169.254.0.0/16 -j RETURN
assert iptables -t nat -A CLASH_LOCAL -d 240.0.0.0/4 -j RETURN
assert iptables -t nat -A CLASH_LOCAL -d 192.168.0.0/16 -j RETURN
assert iptables -t nat -A CLASH_LOCAL -d 10.0.0.0/8 -j RETURN
assert iptables -t nat -A CLASH_LOCAL -p tcp -j REDIRECT --to-ports ${CLASH_REDIR_PORT}

for i in ${PROXY_BLACKLIST_UID}
do
  assert iptables -t nat -I CLASH_LOCAL -m owner --uid-owner $i -j RETURN
done

assert iptables -t nat -A CLASH_EXTERNAL -d 0.0.0.0/8 -j RETURN
assert iptables -t nat -A CLASH_EXTERNAL -d 127.0.0.0/8 -j RETURN
assert iptables -t nat -A CLASH_EXTERNAL -d 224.0.0.0/4 -j RETURN
assert iptables -t nat -A CLASH_EXTERNAL -d 172.16.0.0/12 -j RETURN
assert iptables -t nat -A CLASH_EXTERNAL -d 127.0.0.0/8 -j RETURN
assert iptables -t nat -A CLASH_EXTERNAL -d 169.254.0.0/16 -j RETURN
assert iptables -t nat -A CLASH_EXTERNAL -d 240.0.0.0/4 -j RETURN
assert iptables -t nat -A CLASH_EXTERNAL -d 192.168.0.0/16 -j RETURN
assert iptables -t nat -A CLASH_EXTERNAL -d 10.0.0.0/8 -j RETURN
assert iptables -t nat -A CLASH_EXTERNAL -p tcp -j REDIRECT --to-ports ${CLASH_REDIR_PORT}

assert iptables -t nat -I OUTPUT -p tcp -j CLASH_LOCAL
assert iptables -t nat -I PREROUTING -p tcp -j CLASH_EXTERNAL

if [[ "${CLASH_DNS_PORT}" = "" ]];then
    exit 0
fi

assert iptables -t nat -N CLASH_DNS_LOCAL
assert iptables -t nat -N CLASH_DNS_EXTERNAL

assert iptables -t nat -A CLASH_DNS_LOCAL -p udp ! --dport 53 -j RETURN
assert iptables -t nat -A CLASH_DNS_LOCAL -m owner --uid-owner ${CLASH_UID} -j RETURN
assert iptables -t nat -A CLASH_DNS_LOCAL -p udp -j REDIRECT --to-ports ${CLASH_DNS_PORT}

for i in ${PROXY_BLACKLIST_UID}
do
  assert iptables -t nat -I CLASH_DNS_LOCAL -m owner --uid-owner $i -j RETURN
done

assert iptables -t nat -A CLASH_DNS_EXTERNAL -p udp ! --dport 53 -j RETURN
assert iptables -t nat -A CLASH_DNS_EXTERNAL -p udp -j REDIRECT --to-ports ${CLASH_DNS_PORT}

assert iptables -t nat -I OUTPUT -p udp -j CLASH_DNS_LOCAL
assert iptables -t nat -I PREROUTING -p udp -j CLASH_DNS_EXTERNAL

selector_restore
