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
    if test -s ${selector_file};
    then
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
    else
        echo -e "\033[7;32mselector.txt empty or not exist, selector restore abortion\033[0m"
    fi
}

selector_record() {
    get_ec_parameter
    curl -H "Authorization: Bearer ${clash_secret}" http://127.0.0.1:${clash_ec_port}/proxies | sed -E 's/Selector/Selector\n/g' | sed '$d' | sed -E 's/.*name":"(.*)","now":"(.*)","type.*/\1\n"name":"\2"/' > ${selector_tmp}
    if test -s ${selector_tmp};
    then
        cp -f ${selector_tmp} ${selector_file}
    else
        echo -e "\033[7;32mSelector empty, selector.txt not updated\033[0m"
    fi
    rm -f ${selector_tmp}
}

selector_restore
