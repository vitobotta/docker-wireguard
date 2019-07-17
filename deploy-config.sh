#!/bin/bash

# brew install nmap awk ipcalc wireguard-tools

command -v nmap >/dev/null 2>&1 || { echo >&2 "nmap is required but it's not installed.  Aborting."; exit 1; }
command -v awk >/dev/null 2>&1 || { echo >&2 "awk is required but it's not installed.  Aborting."; exit 1; }
command -v ipcalc >/dev/null 2>&1 || { echo >&2 "ipcalc is required but it's not installed.  Aborting."; exit 1; }
command -v wg >/dev/null 2>&1 || { echo >&2 "wireguard is required but it's not installed.  Aborting."; exit 1; }


check_ipv4_address() {
  if [ -n "$1" -a -z "${*##*\.*}" ]; then
    ipcalc $1 | \
      awk 'BEGIN{FS=":";is_invalid=0} /^INVALID/ {is_invalid=1; print $1} END{exit is_invalid}'
  else
    return 125
  fi
}


POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
  --hosts)
    HOSTS_ARG="$2"
    shift # past argument
    shift # past value
  ;;
  --ssh-user)
    SSH_USER="$2"
    shift # past argument
    shift # past value
  ;;
  --subnet)
    SUBNET="$2"
    shift # past argument
    shift # past value
  ;;
  --wg-interface)
    WG_INTERFACE="$2"
    shift # past argument
    shift # past value
  ;;
  --listen-port)
    LISTEN_PORT="$2"
    shift # past argument
    shift # past value
  ;;
  *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
  ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters


SSH_USER=${SSH_USER:-rancher}
SUBNET=${SUBNET:-"192.168.37.0/24"}
LISTEN_PORT=${LISTEN_PORT:-51820}
WG_INTERFACE=${WG_INTERFACE:-wg0}


# Ensure at least two hosts have been specified

if [[ -z "$HOSTS_ARG" ]]; then
  echo "Must provide two or more hosts (IP addresses) to configure a Wireguard VPN." 1>&2
  exit 1
fi


IFS=, read -r -a hosts_array <<< "$HOSTS_ARG"

if (( ${#hosts_array[@]} <= 1 )); then
  echo "Must provide two or more hosts (IP addresses) to configure a Wireguard VPN." 1>&2
  exit 1
fi

# Ensure the IPs specified are all different

uniq=($(printf "%s\n" "${hosts_array[@]}" | sort -u | tr '\n' ' '))

if (( ${#hosts_array[@]} != ${#uniq[@]} )); then
  echo "Please ensure there are no duplicates in the IPs specified."
  exit 1
fi

# Validate the IPs

invalid_hosts=()

for host_ip in ${hosts_array[@]}; do
  check_output=$(check_ipv4_address $host_ip)
  check_exit_code=$(echo $?)

  if [ "$check_exit_code" -ne "0" ]; then
    invalid_hosts+=($host_ip)
  fi
done

if [ ${#invalid_hosts[@]} -ne 0 ]; then
  echo "These host IPs don't seem valid IP addresses:"
  printf '%s\n' "${invalid_hosts[@]}"
  exit 1
fi

# Check if we can connect to the hosts via SSH

cant_connect=()

for host_ip in ${hosts_array[@]}; do
  ssh -n -q -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=1 -o ConnectionAttempts=1 $SSH_USER@$host_ip exit
  
  if [ "$?" -ne "0" ]
  then
    cant_connect+=($host_ip)
  fi
done

if [ ${#cant_connect[@]} -ne 0 ]; then
  echo "Unable to connect to the following hosts via SSH with user $SSH_USER:"
  printf '%s\n' "${cant_connect[@]}"
  exit 1
fi

# Determine the usable ips for the subnet specified and check if they are enough to cover all the hosts

IFS=$'\n' read -rd '' -a subnet_ips <<<"`nmap -nsL $SUBNET | awk '/Nmap scan report/{print $NF}'`"

if [[ "${subnet_ips[0]}" == *.0 ]];
then
  unset 'subnet_ips[0]'
fi

IFS= usable_subnet_ips=(${subnet_ips[@]})

if (( ${#usable_subnet_ips[@]} > 1 )); then
  unset 'usable_subnet_ips[${#usable_subnet_ips[@]}-1]'
fi

IFS= usable_subnet_ips=(${usable_subnet_ips[@]})

if (( ${#usable_subnet_ips[@]} <  ${#hosts_array[@]} )); then
  echo "Subnet $SUBNET does't cover enough VPN IP addresses for the hosts."
  exit 1
fi

#  Generate private and public keys

private_keys=()
public_keys=()

for host_ip in ${hosts_array[@]}; do
  private_key_file=`mktemp`
  public_key_file=`mktemp`

  wg genkey | tee $private_key_file | wg pubkey > $public_key_file

  private_keys+=(`cat $private_key_file`)
  public_keys+=(`cat $public_key_file`)

  rm $private_key_file
  rm $public_key_file
done

# Generate and deploy Wireguard configuration to each host

for ((i = 0; i < ${#hosts_array[@]}; i++))
do
  host_config_file=`mktemp -d`/$WG_INTERFACE.conf

  cat > $host_config_file <<EOF
[Interface]
Address = ${usable_subnet_ips[$i]}
PrivateKey = ${private_keys[$i]}
ListenPort = $LISTEN_PORT
SaveConfig = true

EOF

  for ((j = 0; j < ${#hosts_array[@]}; j++))
  do
    if (( $j != $i )); then
      cat >> $host_config_file <<EOF
[Peer]
PublicKey = ${public_keys[$j]}
Endpoint = ${hosts_array[$j]}:$LISTEN_PORT
AllowedIPs = ${usable_subnet_ips[$j]}/32

EOF
    fi
  done

  host_ip="${hosts_array[$i]}"

  echo "Deploying Wireguard configuration to host: $host_ip ..."

  ssh -n -q -o StrictHostKeyChecking=no $SSH_USER@$host_ip mkdir -p wireguard

  home_directory=`ssh -n -q -o StrictHostKeyChecking=no $SSH_USER@$host_ip pwd`

  scp -q -o StrictHostKeyChecking=no $host_config_file $SSH_USER@$host_ip:wireguard

  echo "... deployed config to $home_directory/wireguard/$WG_INTERFACE.conf"

  rm $host_config_file
done



  



