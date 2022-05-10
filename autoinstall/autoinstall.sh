#!/bin/sh

PREFIX=""
TOR_USER="tor"

PROXY_MODE=1
LUA_MODULE=1
LUCI_APP=1

OWRT_VERSION="current"
RUAB_VERSION="0.9.4-0"
RUAB_MOD_LUA_VERSION="0.9.4-0"
RUAB_LUCI_APP_VERSION="0.9.4-0"
BASE_URL="https://raw.githubusercontent.com/gSpotx2f/packages-openwrt/master"
PKG_DIR="/tmp"

if [ -n "$1" ]; then
    OWRT_VERSION="$1"
fi

### URLs

### packages
URL_RUAB_PKG="${BASE_URL}/${OWRT_VERSION}/ruantiblock_${RUAB_VERSION}_all.ipk"
URL_MOD_LUA_PKG="${BASE_URL}/${OWRT_VERSION}/ruantiblock-mod-lua_${RUAB_MOD_LUA_VERSION}_all.ipk"
URL_LUCI_APP_PKG="${BASE_URL}/${OWRT_VERSION}/luci-app-ruantiblock_${RUAB_LUCI_APP_VERSION}_all.ipk"
URL_LUCI_APP_RU_PKG="${BASE_URL}/${OWRT_VERSION}/luci-i18n-ruantiblock-ru_${RUAB_LUCI_APP_VERSION}_all.ipk"
### tor
URL_TORRC="https://raw.githubusercontent.com/gSpotx2f/ruantiblock_openwrt/master/tor/etc/tor/torrc"
### ruantiblock-mod-lua
URL_LUA_IPTOOL="https://raw.githubusercontent.com/gSpotx2f/iptool-lua/master/5.1/iptool.lua"
URL_LUA_IDN="https://raw.githubusercontent.com/haste/lua-idn/master/idn.lua"

### Local files

RUAB_CFG_DIR="${PREFIX}/etc/ruantiblock"
EXEC_DIR="${PREFIX}/usr/bin"
BACKUP_DIR="${RUAB_CFG_DIR}/autoinstall.bak.`date +%s`"
### packages
FILE_RUAB_PKG="${PKG_DIR}/ruantiblock_${RUAB_VERSION}_all.ipk"
FILE_MOD_LUA_PKG="${PKG_DIR}/ruantiblock-mod-lua_${RUAB_MOD_LUA_VERSION}_all.ipk"
FILE_LUCI_APP_PKG="${PKG_DIR}/luci-app-ruantiblock_${RUAB_LUCI_APP_VERSION}_all.ipk"
FILE_LUCI_APP_RU_PKG="${PKG_DIR}/luci-i18n-ruantiblock-ru_${RUAB_LUCI_APP_VERSION}_all.ipk"
### ruantiblock
FILE_CONFIG="${RUAB_CFG_DIR}/ruantiblock.conf"
FILE_FQDN_FILTER="${RUAB_CFG_DIR}/fqdn_filter"
FILE_IP_FILTER="${RUAB_CFG_DIR}/ip_filter"
FILE_USER_ENTRIES="${RUAB_CFG_DIR}/user_entries"
FILE_UCI_CONFIG="${PREFIX}/etc/config/ruantiblock"
FILE_INIT_SCRIPT="${PREFIX}/etc/init.d/ruantiblock"
FILE_MAIN_SCRIPT="${EXEC_DIR}/ruantiblock"
### tor
FILE_TORRC="${PREFIX}/etc/tor/torrc"
### ruantiblock-mod-lua
FILE_LUA_IPTOOL="${PREFIX}/usr/lib/lua/iptool.lua"
FILE_LUA_IDN="${PREFIX}/usr/lib/lua/idn.lua"

AWK_CMD="awk"
WGET_CMD=`which wget`
if [ $? -ne 0 ]; then
    echo " Error! wget doesn't exists" >&2
    exit 1
fi
WGET_PARAMS="--no-check-certificate -q -O "
OPKG_CMD=`which opkg`
if [ $? -ne 0 ]; then
    echo " Error! opkg doesn't exists" >&2
    exit 1
fi
UCI_CMD=`which uci`
if [ $? -ne 0 ]; then
    echo " Error! uci doesn't exists" >&2
    exit 1
fi

FileExists() {
    test -e "$1"
}

MakeDir() {
    [ -d "$1" ] || mkdir -p "$1"
    if [ $? -ne 0 ]; then
        echo "Error! Can't create directory (${1})" >&2
        exit 1
    fi
}

ChmodExec() {
    chmod 755 "$1"
}

RemoveFile() {
    if [ -e "$1" ]; then
        echo "Removing ${1}"
        rm -f "$1"
    fi
}

DlFile() {
    local _dir _file
    if [ -n "$2" ]; then
        _dir=`dirname "$2"`
        MakeDir "$_dir"
        _file="$2"
    else
        _file="-"
    fi
    $WGET_CMD $WGET_PARAMS "$_file" "$1"
    if [ $? -ne 0 ]; then
        echo "Connection error (${1})" >&2
        exit 1
    fi
    echo "Downloading ${1}"
}

BackupFile() {
    [ -e "$1" ] && cp -f "$1" "${1}.bak.`date +%s`"
}

BackupCurrentConfig() {
    local _file
    MakeDir "$BACKUP_DIR"
    for _file in "$FILE_CONFIG" "$FILE_FQDN_FILTER" "$FILE_IP_FILTER" "$FILE_USER_ENTRIES" "$FILE_UCI_CONFIG" "$FILE_TORRC"
    do
        [ -e "$_file" ] && cp -f "$_file" "${BACKUP_DIR}/`basename ${_file}`"
    done
}

RunAtStartup() {
    $FILE_INIT_SCRIPT enable
}

AppStop() {
    FileExists "$FILE_MAIN_SCRIPT" && $FILE_MAIN_SCRIPT destroy
}

AppStart() {
    modprobe ip_set > /dev/null
    modprobe ip_set_hash_ip > /dev/null
    modprobe ip_set_hash_net > /dev/null
    modprobe ip_set_list_set > /dev/null
    modprobe xt_set > /dev/null
    $FILE_INIT_SCRIPT start
}

SetCronTask() {
    echo "0 3 */3 * * ${FILE_MAIN_SCRIPT} update" >> /etc/crontabs/root
    /etc/init.d/cron restart 2> /dev/null
    /etc/init.d/cron enable
}

Reboot() {
    reboot
}

UpdatePackagesList() {
    $OPKG_CMD update
}

InstallPackages() {
    local _pkg
    for _pkg in $@
    do
        if [ -z "`$OPKG_CMD list-installed $_pkg`" ]; then
            $OPKG_CMD --force-overwrite install $_pkg
            if [ $? -ne 0 ]; then
                echo "Error during installation of the package (${_pkg})" >&2
                exit 1
            fi
        fi
    done
}

InstallBaseConfig() {
    _return_code=1
    InstallPackages "ipset" "kmod-ipt-ipset" "dnsmasq-full"
    RemoveFile "$FILE_RUAB_PKG" > /dev/null
    DlFile "$URL_RUAB_PKG" "$FILE_RUAB_PKG" && $OPKG_CMD install "$FILE_RUAB_PKG" > /dev/null
    _return_code=$?
    # костыль для остановки сервиса, который запускается автоматически после установки пакета!
    AppStop
    return $_return_code
}

InstallVPNConfig() {
    local _if_vpn
    $UCI_CMD set ruantiblock.config.proxy_mode="2"
    _if_vpn=`$UCI_CMD get network.VPN.ifname`
    if [ -z "$_if_vpn" ]; then
        _if_vpn="tun0"
    fi
    $UCI_CMD set ruantiblock.config.if_vpn="$_if_vpn"
    $UCI_CMD commit
}

TorrcSettings() {
    local _lan_ip=`$UCI_CMD get network.lan.ipaddr | $AWK_CMD -F "/" '{print $1}'`
    if [ -z "$_lan_ip" ]; then
        _lan_ip="0.0.0.0"
    fi
    $AWK_CMD -v lan_ip="$_lan_ip" -v TOR_USER="$TOR_USER" '{
            if($0 ~ /^([#]?TransPort|[#]?TransListenAddress|[#]?SOCKSPort)/ && $0 !~ "127.0.0.1") sub(/([0-9]{1,3}.){3}[0-9]{1,3}/, lan_ip, $0);
            else if($0 ~ /^User/) $2 = TOR_USER;
            print $0;
        }' "$FILE_TORRC" > "${FILE_TORRC}.tmp" && mv -f "${FILE_TORRC}.tmp" "$FILE_TORRC"
}

InstallTorConfig() {
    InstallPackages "tor" "tor-geoip"
    BackupFile "$FILE_TORRC"
    DlFile "$URL_TORRC" "$FILE_TORRC"
    TorrcSettings
    $UCI_CMD set ruantiblock.config.proxy_mode="1"
    # dnsmasq rebind protection
    $UCI_CMD set dhcp.@dnsmasq[0].rebind_localhost='1'
    $UCI_CMD set dhcp.@dnsmasq[0].rebind_domain='.onion'
    $UCI_CMD commit
}

InstallLuaModule() {
    InstallPackages "lua" "luasocket" "luasec" "luabitop"
    RemoveFile "$FILE_MOD_LUA_PKG" > /dev/null
    DlFile "$URL_MOD_LUA_PKG" "$FILE_MOD_LUA_PKG" && $OPKG_CMD install "$FILE_MOD_LUA_PKG"
    FileExists "$FILE_LUA_IPTOOL" || DlFile "$URL_LUA_IPTOOL" "$FILE_LUA_IPTOOL"
    FileExists "$FILE_LUA_IDN" || DlFile "$URL_LUA_IDN" "$FILE_LUA_IDN"
    $UCI_CMD set ruantiblock.config.bllist_module="/usr/libexec/ruantiblock/ruab_parser.lua"
    $UCI_CMD commit
}

InstallLuciApp() {
    RemoveFile "$FILE_LUCI_APP_PKG" > /dev/null
    RemoveFile "$FILE_LUCI_APP_RU_PKG" > /dev/null
    DlFile "$URL_LUCI_APP_PKG" "$FILE_LUCI_APP_PKG" && $OPKG_CMD install "$FILE_LUCI_APP_PKG" && \
    DlFile "$URL_LUCI_APP_RU_PKG" "$FILE_LUCI_APP_RU_PKG" && $OPKG_CMD install "$FILE_LUCI_APP_RU_PKG"
    rm -f /tmp/luci-modulecache/* /tmp/luci-indexcache*
    /etc/init.d/rpcd restart
    /etc/init.d/uhttpd restart
}

PrintBold() {
    printf "\033[1m - ${1}\033[0m\n"
}

InputError () {
    printf "\033[1;31m Wrong input! Try again...\033[m\n"; $1
}

ConfirmProxyMode() {
    local _reply
    printf " Select configuration [1: Tor | 2: VPN] (default: 1, quit: q) > "
    read _reply
    case $_reply in
        1|"")
            PROXY_MODE=1
            break
        ;;
        2)
            PROXY_MODE=2
            break
        ;;
        q|Q)
            printf "Bye...\n"; exit 0
        ;;
        *)
            InputError ConfirmProxyMode
        ;;
    esac
}

ConfirmLuaModule() {
    local _reply
    printf " Would you like to install the lua module? [y|n] (default: y, quit: q) > "
    read _reply
    case $_reply in
        y|Y|"")
            LUA_MODULE=1
            break
        ;;
        n|N)
            LUA_MODULE=0
            break
        ;;
        q|Q)
            printf "Bye...\n"; exit 0
        ;;
        *)
            InputError ConfirmLuaModule
        ;;
    esac
}

ConfirmLuciApp() {
    local _reply
    printf " Would you like to install the LuCI application? [y|n] (default: y, quit: q) > "
    read _reply
    case $_reply in
        y|Y|"")
            LUCI_APP=1
            break
        ;;
        n|N)
            LUCI_APP=0
            break
        ;;
        q|Q)
            printf "Bye...\n"; exit 0
        ;;
        *)
            InputError ConfirmLuciApp
        ;;
    esac
}

ConfirmProcessing() {
    local _reply
    printf " Next, the installation will begin... Continue? [y|n] (default: y, quit: q) > "
    read _reply
    case $_reply in
        y|Y|"")
            break
        ;;
        n|N|q|Q)
            printf "Bye...\n"; exit 0
        ;;
        *)
            InputError ConfirmLuciApp
        ;;
    esac
}

ConfirmProxyMode
ConfirmLuciApp
ConfirmProcessing
AppStop
PrintBold "Updating packages list..."
UpdatePackagesList
PrintBold "Saving current configuration..."
PrintBold "Installing basic configuration..."
InstallBaseConfig
if [ $? -eq 0 ]; then

    if [ $PROXY_MODE = 2 ]; then
        PrintBold "Installing VPN configuration..."
        InstallVPNConfig
    else
        PrintBold "Installing Tor configuration..."
        InstallTorConfig
        if `/etc/init.d/tor enabled`; then
            /etc/init.d/tor restart
        fi
    fi

    if [ $LUA_MODULE = 1 ]; then
        PrintBold "Installing lua module..."
        InstallLuaModule
    fi

    if [ $LUCI_APP = 1 ]; then
        PrintBold "Installing luci app..."
        InstallLuciApp
    fi

    RunAtStartup
    SetCronTask
else
    PrintBold "An error occurred while installing the ruantiblock package!"
fi

exit 0
