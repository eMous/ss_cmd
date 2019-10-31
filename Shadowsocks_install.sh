#!/bin/bash

main() {
  # 如果没有sudo权限
  if [[ ! $EUID = 0 ]]; then
    echo "--- You don't have authority, use me by root or with sudo ---"
    exit 1
  fi
  
  cd /tmp
  if [[ -f /tmp/ss_tool ]]; then rm /tmp/ss_tool; fi
  mkdir -p /tmp/ss_tool && cd /tmp/ss_tool && prompt
}
prompt() {
  # 提示信息(安装部分)
  printf '%b' "1. 从devtsai的仓库里下载shadowsocks-libev v3.3.2源码"\
  "(如果Github的连接速度异常)\n"\
  "2. 从原Github的仓库里下载shadowsocks-libev v3.3.2源码"\
  "(如果Github的连接速度正常)\n"\
  "3. 从原Github的仓库里下载最新shadowsocks-libev源码"\
  "(安装脚本不保证在v3.3.2之后的版本有效，请根据日志处理)\n"

  rm /tmp/ss_tool/ss_install.log -rf >/dev/null 2>&1
  touch /tmp/ss_tool/ss_install.log

  while true; do
    local _123
    read -p "请选择(1,2,3[default]):" _123
    case ${_123} in
      1)  install_ss -devtsai_v3.3.2;break;;
      2)  install_ss -github_v3.3.2;break;;
      3)  install_ss -github_new;break;;
      "") install_ss -github_new;break;;
    esac
  done 2>&1 >>/tmp/ss_tool/ss_install.log | tee -a /tmp/ss_tool/ss_install.log 
  # 提示信息(配置部分)
  while true; do
    local services_num
    read -p "How many proxy servers do you need?(1[default]-5):" services_num
    case ${services_num} in
      [1-5]) break;;
      "") services_num=1;break;;
    esac
  done
  while true; do
    local b_need_v2ray
    read -p "Do you need v2ray-plugin if you don't have a https server?(y/n[default]):" b_need_v2ray
    case ${b_need_v2ray} in
      [yY]) b_need_v2ray=1;break;;
      [nN]) b_need_v2ray=0;break;;
      "") b_need_v2ray=0;break;;
    esac
  done
  set_normal_ss ${services_num}
}
# 密码随即生成
randpw() { 
  < /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-8};echo;
}
# 获得一个暂时为被占用的端口
get_a_unused_port(){
  local PORT
  read LOWERPORT UPPERPORT < /proc/sys/net/ipv4/ip_local_port_range
  while :
  do
    PORT="`shuf -i $LOWERPORT-$UPPERPORT -n 1`"
    ss -lpn | grep -q ":$PORT " || break
  done
  echo $PORT
}
set_normal_ss() {
  # Add Service Shadowsocks to Firewall Zone Public 
  if [[ -z $(firewall-cmd --get-services | grep shadowsocks-libev) ]]; then
    firewall-cmd --permanent --new-service=shadowsocks-libev 
    firewall-cmd --permanent  --add-service=shadowsocks-libev
    systemctl restart firewalld
  fi
  
  local ports_array passwords_array
  for ((n=0;n<$1;n++))
  do
    if [[ -z ${conf_root} ]]; then
      conf_root=/etc/shadowsocks-libev
    fi
    port_array[$n]=$(get_a_unused_port)
    # echo ${port_array[*]}
    passwords_array[$n]=$(randpw)
    # echo ${passwords_array[*]}
    create_ss_conf -port=${port_array[$n]} -password=${passwords_array[$n]} \
    -conf_root=${conf_root}
    create_ss_unit -port=${port_array[$n]} -conf_root=${conf_root} -start=true 
  done
}
create_ss_unit() {
  local port file_name full_file_url start_or_not execstart_name execstoppost_name
  while [ $# -ne 0 ]
  do
    case $1 in
      -port=*) port=${1:6};echo $port;; 
      -conf_root=*) conf_root=${1:11}; echo $conf_root;;
      -start=*) start_or_not=${1:7}; echo $start_or_not;;
    esac
    shift
  done
  file_name="ss_${port}.conf"
  full_file_url=${conf_root}/${file_name}

  # Write excestart for service
  mkdir ${conf_root}/execstarts -p
  execstart_name=${conf_root}/execstarts/ss_${port}_start.sh
  > ${execstart_name} printf '%b' \
  '#!/bin/bash\n' \
  'ntpdate pool.ntp.org\n' \
  'ss-server -c '${full_file_url}'&\n'\
  'echo 配置防火墙策略中.. \n'\
  'firewall-cmd --permanent --service=shadowsocks-libev '\
  '--add-port='${port}'/tcp\n'\
  'firewall-cmd --permanent --service=shadowsocks-libev '\
  '--add-port='${port}'/udp\n'\
  'systemctl restart firewalld\n'
  chmod +x ${execstart_name}

  # Write execstoppost for service
  mkdir ${conf_root}/execstoppost -p
  execstoppost_name=${conf_root}/execstoppost/ss_${port}_stoppost.sh
  > ${execstoppost_name} printf '%b' \
  '#!/bin/bash \n' \
  'firewall-cmd --permanent --service=shadowsocks-libev '\
  '--remove-port='${port}'/tcp\n'\
  'firewall-cmd --permanent --service=shadowsocks-libev '\
  '--remove-port='${port}'/udp\n'\
  'systemctl restart firewalld\n'\
  'echo Firewalld Service ss_'${port}' Removed.'
  chmod +x  ${execstoppost_name}
  chmod a+x ${execstoppost_name}


  # Write service unit for systemctl
  mkdir ${conf_root}/services -p
  service_name=${conf_root}/services/ss_${port}.service
  > ${service_name}  printf '%b' \
  '[Unit]\n' \
  'Description=Shadowsocks Server Of Port '"${port}\n" \
  'After=network.target \n\n' \
  '[Service]\n' \
  'ExecStart='${execstart_name}'\n' \
  'ExecStopPost='${execstoppost_name}'\n'\
  'RemainAfterExit=yes\n'\
  'Restart=on-abort\n\n' \
  '[Install]\n' \
  'WantedBy=multi-user.target\n' 
  chmod 664 ${service_name} 
  ln -s ${service_name}  /etc/systemd/system/$(basename -- "$service_name")
  if [[ $start_or_not = "true"  ]]; then
    systemctl  enable   $(basename -- "$service_name")
    systemctl  start    $(basename -- "$service_name")
    systemctl  status   $(basename -- "$service_name")
  fi
}
create_ss_conf() {
  local port password _pwd _choice_to_file full_file_url file_name service_name 
  while [ $# -ne 0 ]
  do
    case $1 in
      -port=*) port=${1:6};echo $port;; 
      -password=*) password=${1:10};echo $password;;
      -conf_root=*) conf_root=${1:11}; echo $conf_root;;
    esac
    shift
  done
  
  file_name="ss_${port}.conf"
  # 检查conf_root是不是一个文件
  while true
  do
    if [[ -f ${conf_root} ]]; then
      echo ${conf_root}是一个文件
      while true
      do
        read -p "1.删除文件建立目录（默认） 2.切换目录 ：（1，2）" _choice_to_file
        case ${_choice_to_file} in
          1|"" ) rm -rf ${conf_root};echo "目录已删除";break;;
          2 ) 
          read -p "当前目录是$(pwd),请输入新的用于存放配置文件的目录（勿以'/'结尾）：" \
          conf_root
          break;;
        esac
      done
    elif [[ ! -d ${conf_root} ]]; then
      mkdir ${conf_root} -p
      echo "${conf_root} 目录不存在，现已经递归建立"
    else
      echo "${conf_root}目录存在"
      full_file_url=${conf_root}/${file_name}
      > ${full_file_url} printf '%b' \
      '{\n' \
      '"server":"0.0.0.0",\n' \
      '"server_port":'"${port},\n" \
      '"local_port":1080,\n' \
      '"password":"'${password}'",\n' \
      '"timeout":400,\n' \
      '"method":"xchacha20-ietf-poly1305",\n' \
      '"mode":"tcp_and_udp"\n' \
      '}\n'
      break
    fi
  done
}
install_ss() {
  cd /tmp/ss_tool  
  # check yum lock
  if [[ -f "/var/run/yum.pid" ]] ; then
    echo_l "有别的程序正在使用yum, 参见https://www.thegeekdiary.com/yum-command-fails\
    -with-another-app-is-currently-holding-the-yum-lock-in-centos-rhel-7/"
    while true; do
      read -p "是否需要强制关闭（y/n）" yn
      case $yn in
        [Yy] ) rm -f /var/run/yum.pid; yum clean all; break;;
        [Nn] ) exit 1;;
      esac
    done
  fi
  
  echo_l "--------------Updating yum...--------------"
  yum update -y 
  echo_l "--------------Yum updated.--------------" 
  echo_l "--------------Installing dependences...--------------" 
  yum install epel-release -y 
  yum install gcc gettext autoconf libtool \
  automake make pcre-devel asciidoc xmlto \
  c-ares-devel libev-devel libsodium-devel mbedtls-devel git -y 
  echo_l "--------------Dependences installed.--------------" 
  echo_l "--------------Updating yum agian...--------------" 
  yum update -y 
  echo_l "--------------Yum updated.--------------" 
  
  echo_l "--------------Installing libsodium--------------" 
  if [[ ! "$(whereis libsodium)" ]] ; then
    # Installation of libsodium
    export LIBSODIUM_VER=1.0.16
    wget https://download.libsodium.org/libsodium/releases/libsodium-$LIBSODIUM_VER.tar.gz
    tar xvf libsodium-$LIBSODIUM_VER.tar.gz
    pushd libsodium-$LIBSODIUM_VER
    ./configure --prefix=/usr && make
    sudo make install
    popd
    sudo ldconfig
  fi 
  echo_l "--------------Libsodium installed--------------" 
  echo_l "--------------Installing mbedtls--------------" 
  if [[ ! "$(whereis mbedtls)" ]] ; then
    # Installation of MbedTLS
    export MBEDTLS_VER=2.6.0
    wget https://tls.mbed.org/download/mbedtls-$MBEDTLS_VER-gpl.tgz
    tar xvf mbedtls-$MBEDTLS_VER-gpl.tgz
    pushd mbedtls-$MBEDTLS_VER
    make SHARED=1 CFLAGS="-O2 -fPIC"
    sudo make DESTDIR=/usr install
    popd
    sudo ldconfig
  fi 
  echo_l "--------------Mbedtls installed--------------" 

  # Download Shadowsocks
  SS_GIT_DIR=$(pwd)"/shadowsocks-libev"
  if [[ -d $SS_GIT_DIR ]] ; then 
    rm $SS_GIT_DIR -rf
  fi
  if [[ ${1} = "-github_new" ]] ; then
    echo_l "--------------Downloading From Github Latest--------------"
    git clone --recursive https://github.com/shadowsocks/shadowsocks-libev.git 
    cd shadowsocks-libev
  elif [[ ${1} = "-github_v3.3.2" ]] ; then
    echo_l "--------------Downloading From Github v3.3.2--------------"
    local github_url_v332=$(concat "https://github.com/shadowsocks/shadowsocks-libev/" \
    "releases/download/v3.3.2/shadowsocks-libev-3.3.2.tar.gz")
    wget ${github_url_v332} -O $(pwd)"/shadowsocks-libev-3.3.2.tar.gz" 
    tar zxvf shadowsocks-libev-3.3.2.tar.gz 
    rm -f shadowsocks-libev-3.3.2.tar.gz 
    cd shadowsocks-libev-3.3.2
  elif [[ ${1} = "-devtsai_v3.3.2" ]] ; then
    echo_l "--------------Downloading From Devtsai v3.3.2--------------"
    local devtsai_url_v332=$(concat \
    "https://ss.showyoumycode.com/files/shadowsocks-libev-3.3.2.tar.gz")
    wget ${devtsai_url_v332} -O $(pwd)"/shadowsocks-libev-3.3.2.tar.gz" 
    tar zxvf shadowsocks-libev-3.3.2.tar.gz 
    rm -f shadowsocks-libev-3.3.2.tar.gz 
    cd shadowsocks-libev-3.3.2
  fi
  # Start building
  if [[ -f "autogen.sh" ]] ; then
    # 所有的release版本都不包括autogen.sh
    echo_l "--------------Autogening--------------" 
    ./autogen.sh 
  fi
  echo_l "--------------Configuring--------------" 
  ./configure
  echo_l "--------------Making--------------" 
  make 
  echo_l "--------------Make Installing--------------" 
  make install
  echo_l "--------------Shadowsocks-libev Installation Finish--------------" 

}

# 拼接字符串
concat() {
  local tmp_arg
  for each_arg in $@
  do
    tmp_arg=${tmp_arg}${each_arg}
  done
  echo ${tmp_arg}
}
# echo with log
echo_l() {
  local log_file_path

  #log_file_path=$2
  #if [[ -z $2 ]]; then
  #  log_file_path=/tmp/ss_tool/ss_install.log 
  #fi
  echo $1 1>&2 #| tee -a $2
}
main "$@"
